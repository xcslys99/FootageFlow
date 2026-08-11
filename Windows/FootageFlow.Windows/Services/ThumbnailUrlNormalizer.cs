namespace FootageFlow.Windows.Services;

public static class ThumbnailUrlNormalizer
{
    public static IReadOnlyList<string> Normalize(
        string? provider,
        IEnumerable<string?> values,
        string? originalPageUrl,
        IReadOnlyDictionary<string, string>? metadata = null)
    {
        var pageOrigin = Origin(originalPageUrl);
        Uri? instanceOrigin = null;
        if (string.Equals(provider, "peertube", StringComparison.OrdinalIgnoreCase))
        {
            metadata ??= new Dictionary<string, string>();
            instanceOrigin = Origin(metadata.GetValueOrDefault("instanceURL"))
                ?? OriginFromHost(metadata.GetValueOrDefault("instanceHost"))
                ?? OriginFromHost(metadata.GetValueOrDefault("host"))
                ?? pageOrigin;
        }
        var baseUri = instanceOrigin ?? pageOrigin;
        var output = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var raw in values)
        {
            var normalized = NormalizeOne(raw, baseUri);
            if (normalized is not null && seen.Add(normalized)) output.Add(normalized);
        }
        return output;
    }

    public static string? NormalizeOne(string? rawValue, Uri? baseUri = null)
    {
        var value = System.Net.WebUtility.HtmlDecode(rawValue?.Trim());
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (value.StartsWith("//", StringComparison.Ordinal)) value = $"https:{value}";
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri))
        {
            if (baseUri is null || !Uri.TryCreate(baseUri, value, out uri)) return null;
        }
        if (uri.Scheme.Equals("http", StringComparison.OrdinalIgnoreCase))
        {
            var builder = new UriBuilder(uri) { Scheme = Uri.UriSchemeHttps, Port = -1 };
            uri = builder.Uri;
        }
        if (!uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrWhiteSpace(uri.Host)
            || !string.IsNullOrEmpty(uri.UserInfo)) return null;
        return uri.AbsoluteUri;
    }

    private static Uri? Origin(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || string.IsNullOrWhiteSpace(uri.Host))
            return null;
        return new UriBuilder(Uri.UriSchemeHttps, uri.Host, uri.IsDefaultPort ? -1 : uri.Port).Uri;
    }

    private static Uri? OriginFromHost(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return Origin(value.Contains("://", StringComparison.Ordinal) ? value : $"https://{value}");
    }
}
