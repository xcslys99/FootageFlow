using System.Windows.Media;
using System.Windows.Media.Imaging;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows.Services;

/// <summary>Bounded, memory-only thumbnail fingerprints; no full video is fetched.</summary>
public sealed class DuplicateThumbnailHashService
{
    public static DuplicateThumbnailHashService Shared { get; } = new();
    private readonly Dictionary<string, ulong> _cache = new(StringComparer.Ordinal);
    private readonly Queue<string> _order = new();

    public async Task<Dictionary<string, ulong>> HashesAsync(
        IReadOnlyList<MediaAsset> assets, IReadOnlyList<string> candidateIDs,
        CancellationToken cancellationToken)
    {
        var candidates = candidateIDs.ToHashSet(StringComparer.Ordinal);
        var hashes = new Dictionary<string, ulong>(StringComparer.Ordinal);
        foreach (var asset in assets.Where(value => candidates.Contains(value.StableId)))
        {
            cancellationToken.ThrowIfCancellationRequested();
            foreach (var url in asset.EffectiveThumbnailURLs.Take(2))
            {
                if (_cache.TryGetValue(url, out var cached))
                {
                    hashes[asset.StableId] = cached;
                    break;
                }
                try
                {
                    var payload = await ThumbnailLoaderService.Shared.LoadOneAsync(
                        url, cancellationToken: cancellationToken);
                    var hash = await Task.Run(() => DecodeAndHash(payload.Data), cancellationToken);
                    if (hash is null) continue;
                    _cache[url] = hash.Value;
                    _order.Enqueue(url);
                    if (_order.Count > 240) _cache.Remove(_order.Dequeue());
                    hashes[asset.StableId] = hash.Value;
                    break;
                }
                catch (OperationCanceledException) { throw; }
                catch { /* A malformed or unavailable image is never a search failure. */ }
            }
        }
        return hashes;
    }

    public void Clear() { _cache.Clear(); _order.Clear(); }

    public static ulong? DifferenceHash(IReadOnlyList<byte> pixels)
    {
        if (pixels.Count != 72 || pixels.Max() - pixels.Min() < 12) return null;
        ulong hash = 0;
        for (var row = 0; row < 8; row++)
            for (var column = 0; column < 8; column++)
            {
                hash <<= 1;
                if (pixels[row * 9 + column] > pixels[row * 9 + column + 1]) hash |= 1;
            }
        return hash;
    }

    public static ulong? HashImageData(byte[] data) => DecodeAndHash(data);

    private static ulong? DecodeAndHash(byte[] data)
    {
        try
        {
            using var stream = new MemoryStream(data, writable: false);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnDemand);
            var frame = decoder.Frames.FirstOrDefault();
            if (frame is null || frame.PixelWidth <= 0 || frame.PixelHeight <= 0 ||
                frame.PixelWidth > 4096 || frame.PixelHeight > 4096 ||
                (long)frame.PixelWidth * frame.PixelHeight > 16_000_000) return null;
            var scale = Math.Min(1.0, 128.0 / Math.Max(frame.PixelWidth, frame.PixelHeight));
            var resized = new TransformedBitmap(frame, new ScaleTransform(scale, scale));
            var gray = new FormatConvertedBitmap(resized, PixelFormats.Gray8, null, 0);
            var width = gray.PixelWidth;
            var height = gray.PixelHeight;
            if (width == 0 || height == 0) return null;
            var pixels = new byte[width * height];
            gray.CopyPixels(pixels, width, 0);
            var sample = new byte[72];
            for (var row = 0; row < 8; row++)
                for (var column = 0; column < 9; column++)
                    sample[row * 9 + column] = pixels[
                        Math.Min(height - 1, row * height / 8) * width +
                        Math.Min(width - 1, column * width / 9)];
            return DifferenceHash(sample);
        }
        catch { return null; }
    }
}
