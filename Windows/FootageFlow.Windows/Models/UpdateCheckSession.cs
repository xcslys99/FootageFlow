namespace FootageFlow.Windows.Models;

/// <summary>
/// Keeps automatic update prompting bounded to one check and one dialog per app session.
/// This state is intentionally never serialized: restarting FootageFlow creates a fresh session.
/// </summary>
public sealed class UpdateCheckSession
{
    private bool _launchCheckStarted;
    private bool _automaticPromptShown;

    public bool TryBeginLaunchCheck()
    {
        if (_launchCheckStarted) return false;
        _launchCheckStarted = true;
        return true;
    }

    public bool ShouldPresent(bool manual)
    {
        if (manual) return true;
        if (_automaticPromptShown) return false;
        _automaticPromptShown = true;
        return true;
    }
}

public static class UpdateReleaseUrlValidator
{
    public static bool IsTrusted(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
        return uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase) &&
               uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) &&
               uri.IsDefaultPort && string.IsNullOrEmpty(uri.UserInfo) &&
               uri.AbsolutePath.StartsWith(
                   "/xcslys99/FootageFlow/releases/", StringComparison.Ordinal);
    }
}
