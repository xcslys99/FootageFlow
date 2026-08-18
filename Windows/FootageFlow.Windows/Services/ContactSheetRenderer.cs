using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows.Services;

/// <summary>Native WPF rendering glue for the Shared Core contact-sheet plan.</summary>
public static class ContactSheetRenderer
{
    public static async Task RenderPngAsync(ContactSheetPlan plan, string outputPath, CancellationToken cancellationToken = default)
    {
        var width = 1800;
        var columns = Math.Clamp(plan.Columns, 3, 5);
        var padding = 40;
        var gap = 24;
        var cellWidth = (width - padding * 2 - gap * (columns - 1)) / columns;
        var imageHeight = (int)(cellWidth * 9d / 16d);
        var textHeight = plan.IncludeRights ? 92 : 68;
        var rows = Math.Max(1, (int)Math.Ceiling(plan.Items.Count / (double)columns));
        var height = padding * 2 + 58 + rows * (imageHeight + textHeight + gap);

        var images = new Dictionary<int, BitmapSource>();
        using var slots = new SemaphoreSlim(4, 4);
        var jobs = plan.Items.Select(async item =>
        {
            await slots.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                var image = await LoadItemAsync(item, cancellationToken).ConfigureAwait(false);
                if (image is not null) lock (images) images[item.Index] = image;
            }
            catch (OperationCanceledException) { throw; }
            catch { }
            finally { slots.Release(); }
        }).ToArray();
        await Task.WhenAll(jobs);
        cancellationToken.ThrowIfCancellationRequested();

        // The caller is a WPF UI event. Avoid ConfigureAwait(false) above so the
        // drawing objects are created on the dispatcher thread.
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawRectangle(Brushes.White, null, new Rect(0, 0, width, height));
            DrawText(drawing, plan.ProjectName, 30, FontWeights.Bold, Brushes.Black, new Point(padding, padding - 8), width - padding * 2);
            foreach (var item in plan.Items)
            {
                var zero = item.Index - 1;
                var column = zero % columns;
                var row = zero / columns;
                var x = padding + column * (cellWidth + gap);
                var y = padding + 58 + row * (imageHeight + textHeight + gap);
                var imageRect = new Rect(x, y, cellWidth, imageHeight);
                drawing.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(232, 236, 242)), null, imageRect, 8, 8);
                if (images.TryGetValue(item.Index, out var image))
                    drawing.DrawImage(image, Fit(image.PixelWidth, image.PixelHeight, imageRect));
                else
                    DrawText(drawing, "FootageFlow", 17, FontWeights.SemiBold, Brushes.DimGray, new Point(x + 16, y + imageHeight / 2 - 10), cellWidth - 32);
                DrawText(drawing, $"{item.Index:00}  {item.Title}", 16, FontWeights.SemiBold, Brushes.Black, new Point(x, y + imageHeight + 8), cellWidth);
                DrawText(drawing, item.Provider, 13, FontWeights.Normal, Brushes.DimGray, new Point(x, y + imageHeight + 32), cellWidth);
                if (plan.IncludeRights)
                    DrawText(drawing, item.RightsStatus, 12, FontWeights.Normal, Brushes.DimGray, new Point(x, y + imageHeight + 53), cellWidth);
            }
        }
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None);
        encoder.Save(stream);
    }

    private static BitmapSource? Decode(byte[] data)
    {
        try
        {
            using var stream = new MemoryStream(data, writable: false);
            var image = new BitmapImage();
            image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.StreamSource = stream; image.EndInit();
            image.Freeze();
            return image;
        }
        catch { return null; }
    }

    private static async Task<BitmapSource?> LoadItemAsync(ContactSheetItem item, CancellationToken cancellationToken)
    {
        // The shared thumbnail service reads its cache before requesting the
        // provider URL. Local media and FFmpeg frame extraction are fallbacks,
        // not a parallel thumbnail implementation.
        if (!string.IsNullOrWhiteSpace(item.ThumbnailURL))
        {
            try
            {
                var payload = await ThumbnailLoaderService.Shared.LoadOneAsync(
                    item.ThumbnailURL, cancellationToken: cancellationToken).ConfigureAwait(false);
                if (Decode(payload.Data) is { } thumbnail) return thumbnail;
            }
            catch (OperationCanceledException) { throw; }
            catch { }
        }
        if (!string.IsNullOrWhiteSpace(item.LocalPath) && File.Exists(item.LocalPath))
        {
            var extension = Path.GetExtension(item.LocalPath).TrimStart('.').ToLowerInvariant();
            if (new[] { "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "webp", "heic" }.Contains(extension))
            {
                try { return Decode(await File.ReadAllBytesAsync(item.LocalPath, cancellationToken).ConfigureAwait(false)); }
                catch (OperationCanceledException) { throw; }
                catch { }
            }
            else
            {
                var frame = await ExtractVideoFrameAsync(item.LocalPath, item.Duration, cancellationToken).ConfigureAwait(false);
                if (frame is not null) return Decode(frame);
            }
        }
        return null;
    }

    /// Best-effort local video preview: 15% into the timeline avoids title
    /// frames and keeps contact-sheet generation independent from downloads.
    private static async Task<byte[]?> ExtractVideoFrameAsync(
        string path, double? knownDuration, CancellationToken cancellationToken)
    {
        var ffmpeg = Path.Combine(AppContext.BaseDirectory, "Tools", "ffmpeg.exe");
        if (!File.Exists(ffmpeg)) return null;
        var duration = knownDuration ?? await ProbeDurationAsync(path, cancellationToken).ConfigureAwait(false);
        var seconds = duration is > 0 ? duration.Value * 0.15 : 1;
        try
        {
            var (exitCode, output) = await RunToolBytesAsync(ffmpeg,
                ["-hide_banner", "-loglevel", "error", "-ss", seconds.ToString("0.###", CultureInfo.InvariantCulture),
                 "-i", path, "-frames:v", "1", "-vf", "scale=680:-2", "-f", "image2pipe", "-vcodec", "png", "pipe:1"],
                TimeSpan.FromSeconds(30), cancellationToken).ConfigureAwait(false);
            return exitCode == 0 && output.Length > 0 ? output : null;
        }
        catch (OperationCanceledException) { throw; }
        catch { return null; }
    }

    private static async Task<double?> ProbeDurationAsync(string path, CancellationToken cancellationToken)
    {
        var ffprobe = Path.Combine(AppContext.BaseDirectory, "Tools", "ffprobe.exe");
        if (!File.Exists(ffprobe)) return null;
        try
        {
            var (exitCode, output) = await RunToolBytesAsync(ffprobe,
                ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path],
                TimeSpan.FromSeconds(15), cancellationToken).ConfigureAwait(false);
            return exitCode == 0 && double.TryParse(System.Text.Encoding.UTF8.GetString(output).Trim(),
                NumberStyles.Float, CultureInfo.InvariantCulture, out var duration) ? duration : null;
        }
        catch (OperationCanceledException) { throw; }
        catch { return null; }
    }

    private static async Task<(int ExitCode, byte[] Output)> RunToolBytesAsync(
        string executable, IReadOnlyList<string> arguments, TimeSpan timeout, CancellationToken cancellationToken)
    {
        using var process = new System.Diagnostics.Process
        {
            StartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = executable, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            }
        };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        if (!process.Start()) throw new InvalidOperationException("FFmpeg could not start.");
        using var output = new MemoryStream();
        var copy = process.StandardOutput.BaseStream.CopyToAsync(output, cancellationToken);
        var errors = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try
        {
            await process.WaitForExitAsync(linked.Token).ConfigureAwait(false);
            await Task.WhenAll(copy, errors).ConfigureAwait(false);
        }
        catch
        {
            try { if (!process.HasExited) process.Kill(true); } catch { }
            throw;
        }
        return (process.ExitCode, output.ToArray());
    }

    private static Rect Fit(double imageWidth, double imageHeight, Rect bounds)
    {
        var scale = Math.Max(bounds.Width / imageWidth, bounds.Height / imageHeight);
        var width = imageWidth * scale;
        var height = imageHeight * scale;
        return new Rect(bounds.X + (bounds.Width - width) / 2, bounds.Y + (bounds.Height - height) / 2, width, height);
    }

    private static void DrawText(DrawingContext drawing, string text, double size, FontWeight weight, Brush brush, Point origin, double width)
    {
        var formatted = new FormattedText(text ?? "", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(SystemFonts.MessageFontFamily, FontStyles.Normal, weight, FontStretches.Normal), size, brush, 1)
        { MaxTextWidth = Math.Max(20, width), MaxTextHeight = size * 2.2, Trimming = TextTrimming.CharacterEllipsis };
        drawing.DrawText(formatted, origin);
    }
}
