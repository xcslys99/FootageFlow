using System.Collections.Concurrent;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;

namespace FootageFlow.Windows.Services;

public enum ThumbnailImageFormat { Jpeg, Png, WebP, Avif, Gif }

public sealed record ThumbnailPayload(byte[] Data, ThumbnailImageFormat Format, Uri FinalUri, bool FromCache);

public sealed class ThumbnailLoadException(string reason, int? statusCode = null) : Exception(reason)
{
    public string Reason { get; } = reason;
    public int? StatusCode { get; } = statusCode;
}

public sealed class ThumbnailLoaderService : IDisposable
{
    public static ThumbnailLoaderService Shared { get; } = new();
    private const int MaximumBytes = 20 * 1024 * 1024;
    private static readonly TimeSpan SuccessTtl = TimeSpan.FromHours(6);
    private static readonly TimeSpan FailureTtl = TimeSpan.FromSeconds(45);
    private readonly HttpClient _client;
    private readonly bool _ownsClient;
    private readonly ConcurrentDictionary<string, (ThumbnailPayload Payload, DateTimeOffset Expires)> _success = new();
    private readonly ConcurrentDictionary<string, (ThumbnailLoadException Error, DateTimeOffset Expires)> _failures = new();

    public ThumbnailLoaderService(HttpMessageHandler? handler = null)
    {
        if (handler is null)
        {
            handler = new SocketsHttpHandler
            {
                AllowAutoRedirect = false,
                AutomaticDecompression = DecompressionMethods.All,
                UseCookies = false,
                ConnectTimeout = TimeSpan.FromSeconds(8)
            };
        }
        _client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
        _ownsClient = true;
    }

    public async Task<ThumbnailPayload> LoadOneAsync(
        string value, bool forceRetry = false, CancellationToken cancellationToken = default)
    {
        var normalized = ThumbnailUrlNormalizer.NormalizeOne(value)
            ?? throw new ThumbnailLoadException("malformed URL");
        var uri = new Uri(normalized);
        if (_success.TryGetValue(normalized, out var success))
        {
            if (success.Expires > DateTimeOffset.UtcNow)
                return success.Payload with { FromCache = true };
            _success.TryRemove(normalized, out _);
        }
        if (forceRetry) _failures.TryRemove(normalized, out _);
        else if (_failures.TryGetValue(normalized, out var failure))
        {
            if (failure.Expires > DateTimeOffset.UtcNow) throw failure.Error;
            _failures.TryRemove(normalized, out _);
        }

        try
        {
            var payload = await FetchAsync(uri, cancellationToken).ConfigureAwait(false);
            _failures.TryRemove(normalized, out _);
            _success[normalized] = (payload, DateTimeOffset.UtcNow.Add(SuccessTtl));
            TrimSuccessCache();
            return payload;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (OperationCanceledException)
        {
            var error = new ThumbnailLoadException("timeout");
            RecordFailure(normalized, error); Log(uri, null, error.Reason);
            throw error;
        }
        catch (ThumbnailLoadException error)
        {
            RecordFailure(normalized, error); Log(uri, error.StatusCode, error.Reason);
            throw;
        }
        catch
        {
            var error = new ThumbnailLoadException("unavailable");
            RecordFailure(normalized, error); Log(uri, null, error.Reason);
            throw error;
        }
    }

    public async Task<ThumbnailPayload> LoadFirstAsync(
        IEnumerable<string?> values, bool forceRetry = false,
        CancellationToken cancellationToken = default)
    {
        ThumbnailLoadException? lastError = null;
        foreach (var value in values)
        {
            if (string.IsNullOrWhiteSpace(value)) continue;
            try { return await LoadOneAsync(value, forceRetry, cancellationToken).ConfigureAwait(false); }
            catch (OperationCanceledException) { throw; }
            catch (ThumbnailLoadException error) { lastError = error; }
        }
        throw lastError ?? new ThumbnailLoadException("thumbnail unavailable");
    }

    public void MarkDecodeFailure(string value)
    {
        var normalized = ThumbnailUrlNormalizer.NormalizeOne(value);
        if (normalized is null) return;
        _success.TryRemove(normalized, out _);
        RecordFailure(normalized, new ThumbnailLoadException("decode failed"));
    }

    private async Task<ThumbnailPayload> FetchAsync(Uri initialUri, CancellationToken cancellationToken)
    {
        var current = initialUri;
        for (var redirect = 0; redirect <= 5; redirect++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            request.Headers.UserAgent.ParseAdd("FootageFlow/0.7.0 (thumbnail loader)");
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("image/jpeg"));
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("image/png"));
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("image/gif", 0.9));
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("image/webp", 0.8));
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("image/avif", 0.7));
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(12));
            using var response = await _client.SendAsync(
                request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
            if (response.StatusCode is HttpStatusCode.MovedPermanently or HttpStatusCode.Redirect
                or HttpStatusCode.RedirectMethod or HttpStatusCode.TemporaryRedirect
                or HttpStatusCode.PermanentRedirect)
            {
                if (redirect == 5 || response.Headers.Location is null)
                    throw new ThumbnailLoadException("too many redirects", (int)response.StatusCode);
                var next = response.Headers.Location.IsAbsoluteUri
                    ? response.Headers.Location
                    : new Uri(current, response.Headers.Location);
                var normalized = ThumbnailUrlNormalizer.NormalizeOne(next.AbsoluteUri)
                    ?? throw new ThumbnailLoadException("insecure redirect", (int)response.StatusCode);
                current = new Uri(normalized);
                continue;
            }
            if (!response.IsSuccessStatusCode)
                throw new ThumbnailLoadException("HTTP error", (int)response.StatusCode);
            if (response.Content.Headers.ContentLength is > MaximumBytes)
                throw new ThumbnailLoadException("image too large", (int)response.StatusCode);
            var data = await response.Content.ReadAsByteArrayAsync(timeout.Token).ConfigureAwait(false);
            if (data.Length == 0 || data.Length > MaximumBytes)
                throw new ThumbnailLoadException("invalid image", (int)response.StatusCode);
            var contentType = response.Content.Headers.ContentType?.MediaType;
            if (contentType?.Contains("html", StringComparison.OrdinalIgnoreCase) == true
                || contentType?.Contains("json", StringComparison.OrdinalIgnoreCase) == true)
                throw new ThumbnailLoadException("non-image response", (int)response.StatusCode);
            var format = DetectFormat(data, contentType)
                ?? throw new ThumbnailLoadException("unsupported image response", (int)response.StatusCode);
            return new ThumbnailPayload(data, format, current, false);
        }
        throw new ThumbnailLoadException("too many redirects");
    }

    public static ThumbnailImageFormat? DetectFormat(byte[] data, string? contentType = null)
    {
        if (data.Length >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return ThumbnailImageFormat.Jpeg;
        if (data.Length >= 8 && data[..8].SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A })) return ThumbnailImageFormat.Png;
        if (data.Length >= 6 && System.Text.Encoding.ASCII.GetString(data, 0, 6).StartsWith("GIF8", StringComparison.Ordinal)) return ThumbnailImageFormat.Gif;
        if (data.Length >= 12 && System.Text.Encoding.ASCII.GetString(data, 0, 4) == "RIFF" && System.Text.Encoding.ASCII.GetString(data, 8, 4) == "WEBP") return ThumbnailImageFormat.WebP;
        if (data.Length >= 12 && System.Text.Encoding.ASCII.GetString(data, 4, 4) == "ftyp")
        {
            var brand = System.Text.Encoding.ASCII.GetString(data, 8, Math.Min(data.Length - 8, 16));
            if (brand.Contains("avif", StringComparison.Ordinal) || brand.Contains("avis", StringComparison.Ordinal)) return ThumbnailImageFormat.Avif;
        }
        return contentType?.Split(';')[0].Trim().ToLowerInvariant() switch
        {
            "image/jpeg" or "image/jpg" => ThumbnailImageFormat.Jpeg,
            "image/png" => ThumbnailImageFormat.Png,
            "image/webp" => ThumbnailImageFormat.WebP,
            "image/avif" => ThumbnailImageFormat.Avif,
            "image/gif" => ThumbnailImageFormat.Gif,
            _ => null
        };
    }

    private void RecordFailure(string key, ThumbnailLoadException error) =>
        _failures[key] = (error, DateTimeOffset.UtcNow.Add(FailureTtl));

    private void TrimSuccessCache()
    {
        if (_success.Count <= 240) return;
        foreach (var key in _success.OrderBy(value => value.Value.Expires).Take(_success.Count - 240).Select(value => value.Key))
            _success.TryRemove(key, out _);
    }

    private static void Log(Uri uri, int? status, string reason)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.LogDirectory);
            var line = $"{DateTimeOffset.UtcNow:O} provider=thumbnail host={uri.Host} status={status?.ToString() ?? "-"} reason={reason}\n";
            File.AppendAllText(Path.Combine(AppPaths.LogDirectory, "FootageFlow.log"), line);
        }
        catch { }
    }

    public void Dispose() { if (_ownsClient) _client.Dispose(); }
}
