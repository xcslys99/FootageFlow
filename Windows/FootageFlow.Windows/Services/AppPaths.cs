namespace FootageFlow.Windows.Services;

public static class AppPaths
{
    public static string DataRoot { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FootageFlow");
    public static string SettingsFile => Path.Combine(DataRoot, "settings.json");
    public static string LogDirectory => Path.Combine(DataRoot, "Logs");
    public static string DefaultDownloadRoot
    {
        get
        {
            var videos = Environment.GetFolderPath(Environment.SpecialFolder.MyVideos);
            if (string.IsNullOrWhiteSpace(videos))
                videos = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Videos");
            return Path.Combine(videos, "FootageFlow");
        }
    }
}
