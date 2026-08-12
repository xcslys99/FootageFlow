using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows.Services;

public sealed class YtDlpPlatformService
{
    private readonly string _executable = Path.Combine(AppContext.BaseDirectory, "Tools", "yt-dlp.exe");
    private readonly string _ffmpeg = Path.Combine(AppContext.BaseDirectory, "Tools", "ffmpeg.exe");
    private readonly string _ffprobe = Path.Combine(AppContext.BaseDirectory, "Tools", "ffprobe.exe");
    public bool IsAvailable => File.Exists(_executable);

    public async Task<byte[]> SearchAsync(string query, int limit, CancellationToken cancellationToken)
    {
        var count = Math.Clamp(limit, 1, 12);
        var result = await RunAsync(
            ["--ignore-config", "--no-progress", "--no-warnings", "--flat-playlist",
             "--dump-single-json", "--playlist-end", count.ToString(), $"ytsearch{count}:{query}"],
            TimeSpan.FromSeconds(75), cancellationToken);
        EnsureSuccess(result);
        return Encoding.UTF8.GetBytes(result.Output);
    }

    public async Task<string> DownloadAsync(
        string sourceUrl,
        string directory,
        string fileStem,
        CancellationToken cancellationToken)
        => await DownloadAsync(sourceUrl, directory, fileStem, null, null, cancellationToken);

    public async Task<LinkAnalysisResult> AnalyzeAsync(string sourceUrl, CancellationToken cancellationToken)
    {
        if (!LinkUrlSafety.TryCreate(sourceUrl, out var uri))
            throw new ExternalToolException("unsupportedURL", "Unsupported URL");
        var result = await RunAsync(
            ["--ignore-config", "--no-progress", "--no-warnings", "--no-playlist", "--skip-download",
             "--dump-single-json", "--socket-timeout", "15", uri.AbsoluteUri],
            TimeSpan.FromSeconds(120), cancellationToken);
        EnsureSuccess(result);
        try
        {
            using var document = JsonDocument.Parse(result.Output);
            var root = document.RootElement;
            var id = String(root, "id") ?? throw new JsonException();
            var reportedOriginal = String(root, "webpage_url");
            var original = reportedOriginal is not null && LinkUrlSafety.TryCreate(reportedOriginal, out var safeOriginal)
                ? safeOriginal.AbsoluteUri : uri.AbsoluteUri;
            var extractor = String(root, "extractor_key") ?? String(root, "extractor") ?? uri.Host;
            var source = SourceName(extractor, uri.Host);
            var heights = new HashSet<int>();
            var hasAudio = false;
            var formatCount = 0;
            if (root.TryGetProperty("formats", out var formats) && formats.ValueKind == JsonValueKind.Array)
                foreach (var format in formats.EnumerateArray())
                {
                    if (Bool(format, "has_drm") == true) continue;
                    formatCount++;
                    var video = String(format, "vcodec") is { } videoCodec && videoCodec != "none";
                    var audio = String(format, "acodec") is { } audioCodec && audioCodec != "none";
                    hasAudio |= audio;
                    if (video && Int(format, "height") is { } height) heights.Add(height);
                }
            var languages = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            CollectLanguages(root, "subtitles", languages);
            CollectLanguages(root, "automatic_captions", languages);
            return new LinkAnalysisResult
            {
                Id = $"{source.ToLowerInvariant()}:{id}", OriginalURL = original,
                SourceName = source, Title = String(root, "title") ?? id,
                Creator = String(root, "channel") ?? String(root, "uploader"),
                ThumbnailURL = String(root, "thumbnail"), Duration = Double(root, "duration"),
                ProgressiveHeights = heights.OrderDescending().ToArray(), HasAudio = hasAudio,
                SubtitleLanguages = languages.Order().ToArray(), FormatCount = formatCount
            };
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException)
        {
            throw new ExternalToolException("invalidResponse", "The media information could not be read.");
        }
    }

    public async Task<string> DownloadAsync(
        string sourceUrl,
        string directory,
        string fileStem,
        IReadOnlyDictionary<string, string>? metadata,
        IProgress<YtDlpProgress>? progress,
        CancellationToken cancellationToken)
    {
        var selector = metadata?.GetValueOrDefault("linkFormatSelector") ??
            "bestvideo[height<=720]+bestaudio/best[height<=720]";
        var arguments = new List<string>
        {
            "--ignore-config", "--no-warnings", "--no-playlist", "--no-overwrites",
            "--socket-timeout", "15", "--retries", "1", "--fragment-retries", "1", "--newline",
            "--progress-template", "download:FFPROGRESS:%(progress._percent_str)s|%(progress.speed)s",
            "--format", selector, "--paths", directory, "--output", $"{fileStem}.%(ext)s",
            "--print", "after_move:FFFILE:%(filepath)s"
        };
        var outputPreset = metadata?.GetValueOrDefault("linkOutputPreset") ?? "original";
        double clipStart = 0, clipEnd = 0;
        var hasClip = double.TryParse(metadata?.GetValueOrDefault("linkClipStart"),
                NumberStyles.Float, CultureInfo.InvariantCulture, out clipStart) &&
            double.TryParse(metadata?.GetValueOrDefault("linkClipEnd"),
                NumberStyles.Float, CultureInfo.InvariantCulture, out clipEnd) && clipEnd > clipStart;
        var needsFfmpeg = hasClip || selector.Contains('+') ||
            outputPreset is "editingCompatibleMP4" or "audioOnly";
        if (needsFfmpeg)
        {
            if (!File.Exists(_ffmpeg) || !File.Exists(_ffprobe))
                throw new ExternalToolException("externalToolUnavailable", "Editing media support is missing. Please reinstall FootageFlow.");
        }
        if (File.Exists(_ffmpeg))
        {
            arguments.Add("--ffmpeg-location"); arguments.Add(Path.GetDirectoryName(_ffmpeg)!);
        }
        if (hasClip)
        {
            arguments.Add("--download-sections");
            arguments.Add($"*{clipStart.ToString("0.###", CultureInfo.InvariantCulture)}-{clipEnd.ToString("0.###", CultureInfo.InvariantCulture)}");
            arguments.Add("--force-keyframes-at-cuts");
        }
        if (outputPreset == "audioOnly")
        {
            arguments.Add("--extract-audio"); arguments.Add("--audio-format"); arguments.Add("m4a");
            arguments.Add("--audio-quality"); arguments.Add("0");
        }
        if (metadata?.GetValueOrDefault("linkDownloadSubtitles") == "true")
        {
            arguments.Add("--write-subs");
            if (metadata.GetValueOrDefault("linkSubtitleLanguages") is { Length: > 0 } languages)
            {
                arguments.Add("--sub-langs"); arguments.Add(languages);
            }
        }
        arguments.Add(sourceUrl);
        var result = await RunStreamingAsync(arguments, TimeSpan.FromHours(1), cancellationToken, line =>
        {
            var update = ParseProgress(line);
            if (update is not null) progress?.Report(update);
        });
        EnsureSuccess(result);
        var lines = result.Output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
        var path = lines.LastOrDefault(line => line.StartsWith("FFFILE:", StringComparison.Ordinal))?[7..].Trim()
            ?? lines.LastOrDefault(line => !line.StartsWith("FFPROGRESS:", StringComparison.Ordinal))?.Trim();
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            throw new ExternalToolException("invalidResponse", "The downloaded file could not be found.");
        var root = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var candidate = Path.GetFullPath(path);
        if (!candidate.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            throw new ExternalToolException("invalidResponse", "The download path was rejected for safety.");
        if (outputPreset == "editingCompatibleMP4")
        {
            var duration = hasClip ? clipEnd - clipStart :
                double.TryParse(metadata?.GetValueOrDefault("linkMediaDuration"), NumberStyles.Float,
                    CultureInfo.InvariantCulture, out var parsedDuration) ? parsedDuration : 0;
            return await TranscodeEditingCompatibleAsync(
                candidate, directory, fileStem, duration, progress, cancellationToken);
        }
        return candidate;
    }

    private async Task<string> TranscodeEditingCompatibleAsync(
        string input, string directory, string fileStem, double duration,
        IProgress<YtDlpProgress>? progress, CancellationToken cancellationToken)
    {
        var temporary = Path.Combine(directory, $".{fileStem}.{Guid.NewGuid():N}.footageflow.mp4");
        try
        {
            var canStreamCopy = await IsEditingCompatibleSourceAsync(input, cancellationToken);
            var arguments = new List<string>
            {
                "-hide_banner", "-nostdin", "-y", "-i", input, "-map", "0:v:0", "-map", "0:a:0?"
            };
            if (canStreamCopy) arguments.AddRange(["-c", "copy"]);
            else arguments.AddRange([
                "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "192k"
            ]);
            arguments.AddRange([
                "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", temporary
            ]);
            var result = await RunToolStreamingAsync(_ffmpeg,
                arguments, TimeSpan.FromHours(1), cancellationToken, line =>
                {
                    if (duration <= 0 || !line.StartsWith("out_time_ms=", StringComparison.Ordinal) ||
                        !double.TryParse(line[12..], NumberStyles.Float, CultureInfo.InvariantCulture,
                            out var microseconds)) return;
                    progress?.Report(new YtDlpProgress(Math.Min(99, 75 + microseconds / 1_000_000 / duration * 25), 0));
                });
            if (result.ExitCode != 0 || !File.Exists(temporary))
                throw new ExternalToolException("conversionFailed", "The editing-compatible MP4 could not be created.");
            var probe = await RunToolAsync(_ffprobe,
                ["-v", "error", "-show_entries", "stream=codec_type,codec_name,pix_fmt", "-of", "json", temporary],
                TimeSpan.FromMinutes(1), cancellationToken);
            using var document = JsonDocument.Parse(probe.Output);
            var streams = document.RootElement.GetProperty("streams").EnumerateArray().ToArray();
            if (probe.ExitCode != 0 || !streams.Any(stream => String(stream, "codec_type") == "video" &&
                    String(stream, "codec_name") == "h264" && String(stream, "pix_fmt") == "yuv420p") ||
                streams.Any(stream => String(stream, "codec_type") == "audio" && String(stream, "codec_name") != "aac"))
                throw new ExternalToolException("conversionFailed", "The converted MP4 did not pass compatibility validation.");
            var output = Path.Combine(directory, fileStem + ".mp4");
            if (File.Exists(output) && !Path.GetFullPath(input).Equals(Path.GetFullPath(output), StringComparison.OrdinalIgnoreCase))
                throw new ExternalToolException("duplicate", "A file with this name already exists.");
            if (Path.GetFullPath(input).Equals(Path.GetFullPath(output), StringComparison.OrdinalIgnoreCase)) File.Delete(input);
            else if (File.Exists(input)) File.Delete(input);
            File.Move(temporary, output);
            progress?.Report(new YtDlpProgress(100, 0));
            return output;
        }
        finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch { } }
    }

    private async Task<bool> IsEditingCompatibleSourceAsync(
        string input, CancellationToken cancellationToken)
    {
        if (!Path.GetExtension(input).Equals(".mp4", StringComparison.OrdinalIgnoreCase)) return false;
        try
        {
            var probe = await RunToolAsync(_ffprobe,
                ["-v", "error", "-show_entries", "stream=codec_type,codec_name,pix_fmt", "-of", "json", input],
                TimeSpan.FromMinutes(1), cancellationToken);
            if (probe.ExitCode != 0) return false;
            using var document = JsonDocument.Parse(probe.Output);
            var streams = document.RootElement.GetProperty("streams").EnumerateArray().ToArray();
            return streams.Any(stream => String(stream, "codec_type") == "video" &&
                    String(stream, "codec_name") == "h264" && String(stream, "pix_fmt") == "yuv420p") &&
                !streams.Any(stream => String(stream, "codec_type") == "audio" &&
                    String(stream, "codec_name") != "aac");
        }
        catch (OperationCanceledException) { throw; }
        catch { return false; }
    }

    private async Task<ToolResult> RunStreamingAsync(
        IReadOnlyList<string> arguments, TimeSpan timeout, CancellationToken cancellationToken,
        Action<string> onLine)
    {
        if (!IsAvailable)
            throw new ExternalToolException("externalToolUnavailable", "Media support is missing. Please reinstall FootageFlow.");
        using var process = CreateProcess(arguments);
        var output = new StringBuilder();
        var gate = new object();
        process.OutputDataReceived += (_, args) =>
        {
            if (args.Data is null) return;
            lock (gate) output.AppendLine(args.Data);
            onLine(args.Data);
        };
        if (!process.Start()) throw new ExternalToolException("externalToolUnavailable", "Media support could not be started.");
        process.BeginOutputReadLine();
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try { await process.WaitForExitAsync(linked.Token); process.WaitForExit(); }
        catch (OperationCanceledException)
        {
            TryKill(process);
            if (cancellationToken.IsCancellationRequested) throw;
            throw new ExternalToolException("timeout", "The media site took too long to respond.");
        }
        var error = await errorTask;
        lock (gate) return new ToolResult(process.ExitCode, output.ToString(), error);
    }

    private async Task<ToolResult> RunAsync(
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (!IsAvailable)
            throw new ExternalToolException("externalToolUnavailable", "YouTube support is missing. Please reinstall FootageFlow.");
        using var process = CreateProcess(arguments);
        if (!process.Start())
            throw new ExternalToolException("externalToolUnavailable", "YouTube support could not be started.");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try { await process.WaitForExitAsync(linked.Token); }
        catch (OperationCanceledException)
        {
            TryKill(process);
            if (cancellationToken.IsCancellationRequested) throw;
            throw new ExternalToolException("timeout", "YouTube took too long to respond. Please try again later.");
        }
        return new ToolResult(process.ExitCode, await outputTask, await errorTask);
    }

    private static async Task<ToolResult> RunToolAsync(
        string executable, IReadOnlyList<string> arguments, TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var process = CreateToolProcess(executable, arguments);
        if (!process.Start()) throw new ExternalToolException("externalToolUnavailable", "Media support could not be started.");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try { await process.WaitForExitAsync(linked.Token); }
        catch (OperationCanceledException) { TryKill(process); throw; }
        return new ToolResult(process.ExitCode, await outputTask, await errorTask);
    }

    private static async Task<ToolResult> RunToolStreamingAsync(
        string executable, IReadOnlyList<string> arguments, TimeSpan timeout,
        CancellationToken cancellationToken, Action<string> onLine)
    {
        using var process = CreateToolProcess(executable, arguments);
        var output = new StringBuilder();
        process.OutputDataReceived += (_, args) => { if (args.Data is not null) { output.AppendLine(args.Data); onLine(args.Data); } };
        if (!process.Start()) throw new ExternalToolException("externalToolUnavailable", "Media support could not be started.");
        process.BeginOutputReadLine();
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutSource.Token);
        try { await process.WaitForExitAsync(linked.Token); process.WaitForExit(); }
        catch (OperationCanceledException) { TryKill(process); throw; }
        return new ToolResult(process.ExitCode, output.ToString(), await errorTask);
    }

    private static Process CreateToolProcess(string executable, IReadOnlyList<string> arguments)
    {
        var process = new Process { StartInfo = new ProcessStartInfo
        {
            FileName = executable, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = AppPaths.DataRoot
        }};
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        return process;
    }

    private Process CreateProcess(IReadOnlyList<string> arguments)
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = _executable, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                WorkingDirectory = AppPaths.DataRoot
            }
        };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        return process;
    }

    private static void EnsureSuccess(ToolResult result)
    {
        if (result.ExitCode == 0) return;
        var message = result.Error.ToLowerInvariant();
        if (message.Contains("429") || message.Contains("too many requests"))
            throw new ExternalToolException("rateLimited", "Too many requests. Please try again later.");
        if (message.Contains("video unavailable") || message.Contains("has been removed"))
            throw new ExternalToolException("videoUnavailable", "This video is no longer available.");
        if (message.Contains("not available in your country") || message.Contains("geo-restricted"))
            throw new ExternalToolException("regionalRestriction", "This video is unavailable in your region.");
        if (message.Contains("sign in") || message.Contains("login") || message.Contains("private video") ||
            message.Contains("members-only") || message.Contains("age-restricted"))
            throw new ExternalToolException("temporarilyBlocked", "This video requires access that FootageFlow does not use.");
        if (message.Contains("unsupported url") || message.Contains("no suitable extractor"))
            throw new ExternalToolException("unsupportedURL", "Unsupported URL");
        throw new ExternalToolException("requestFailed", "The media site could not complete this request. Open the source page or try again later.");
    }

    private static YtDlpProgress? ParseProgress(string line)
    {
        var index = line.IndexOf("FFPROGRESS:", StringComparison.Ordinal);
        if (index < 0) return null;
        var fields = line[(index + 11)..].Split('|', 2);
        if (!double.TryParse(fields[0].Replace("%", "").Trim(), NumberStyles.Float,
                CultureInfo.InvariantCulture, out var percent)) return null;
        var speed = fields.Length > 1 && double.TryParse(fields[1].Trim(), NumberStyles.Float,
            CultureInfo.InvariantCulture, out var parsed) ? parsed : 0;
        return new YtDlpProgress(Math.Clamp(percent, 0, 100), speed);
    }

    private static void CollectLanguages(JsonElement root, string property, HashSet<string> target)
    {
        if (!root.TryGetProperty(property, out var values) || values.ValueKind != JsonValueKind.Object) return;
        foreach (var item in values.EnumerateObject()) target.Add(item.Name);
    }

    private static string SourceName(string extractor, string host)
    {
        var value = extractor.ToLowerInvariant();
        if (value.Contains("youtube")) return "YouTube";
        if (value.Contains("twitter") || value.Contains("x.com")) return "X / Twitter";
        if (value.Contains("vimeo")) return "Vimeo";
        if (value.Contains("dailymotion")) return "Dailymotion";
        return string.IsNullOrWhiteSpace(extractor) ? host : extractor;
    }

    private static string? String(JsonElement value, string property) =>
        value.TryGetProperty(property, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
    private static int? Int(JsonElement value, string property) =>
        value.TryGetProperty(property, out var item) && item.TryGetInt32(out var result) ? result : null;
    private static double? Double(JsonElement value, string property) =>
        value.TryGetProperty(property, out var item) && item.TryGetDouble(out var result) ? result : null;
    private static bool? Bool(JsonElement value, string property) =>
        value.TryGetProperty(property, out var item) && item.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? item.GetBoolean() : null;

    private static void TryKill(Process process)
    {
        try { if (!process.HasExited) process.Kill(true); }
        catch { }
    }

    private sealed record ToolResult(int ExitCode, string Output, string Error);
}

public sealed record YtDlpProgress(double Percent, double BytesPerSecond);

public sealed class ExternalToolException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public static class LinkUrlSafety
{
    private static readonly HashSet<string> SensitiveQueryNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "authorization", "cookie", "password", "token", "accesstoken", "apikey", "secret",
        "clientsecret", "session", "sessionid"
    };

    public static bool TryCreate(string value, out Uri uri)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out uri!) ||
            uri.Scheme is not ("http" or "https") || !string.IsNullOrEmpty(uri.UserInfo) ||
            string.IsNullOrWhiteSpace(uri.Host) || IsLocalOrPrivate(uri.Host) || HasSensitiveQuery(uri))
        {
            uri = null!;
            return false;
        }
        return true;
    }

    private static bool HasSensitiveQuery(Uri uri)
    {
        foreach (var part in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var rawName = part.Split('=', 2)[0];
            string decoded;
            try { decoded = Uri.UnescapeDataString(rawName); }
            catch { decoded = rawName; }
            var normalized = new string(decoded.ToLowerInvariant().Where(char.IsLetter).ToArray());
            if (SensitiveQueryNames.Contains(normalized)) return true;
        }
        return false;
    }

    private static bool IsLocalOrPrivate(string host)
    {
        var normalized = host.Trim('[', ']').ToLowerInvariant();
        if (normalized == "localhost" || normalized.EndsWith(".localhost") || normalized.EndsWith(".local"))
            return true;
        if (!IPAddress.TryParse(normalized, out var address)) return false;
        if (IPAddress.IsLoopback(address)) return true;
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
        {
            var bytes = address.GetAddressBytes();
            return address.IsIPv6LinkLocal || address.IsIPv6SiteLocal || address.IsIPv6Multicast ||
                   (bytes[0] & 0xfe) == 0xfc;
        }
        var octets = address.GetAddressBytes();
        return octets[0] is 0 or 10 or 127 ||
               octets[0] == 100 && octets[1] is >= 64 and <= 127 ||
               octets[0] == 169 && octets[1] == 254 ||
               octets[0] == 172 && octets[1] is >= 16 and <= 31 ||
               octets[0] == 192 && octets[1] == 168 || octets[0] >= 224;
    }
}
