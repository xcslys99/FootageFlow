namespace FootageFlow.Windows.Models;

public sealed class AppSettingsModel
{
    public string Language { get; set; } = "en";
    public string DownloadRoot { get; set; } = "";
    public HashSet<string> EnabledProviders { get; set; } =
        ["pexels", "pixabay", "wikimedia", "internetArchive", "youtube"];
    public bool ContinuedWithoutApiKey { get; set; }
}
