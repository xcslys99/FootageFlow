using System.Text.Json;
using FootageFlow.Windows.Models;

namespace FootageFlow.Windows.Services;

public sealed class SettingsService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public AppSettingsModel Current { get; private set; } = new();

    public SettingsService()
    {
        Directory.CreateDirectory(AppPaths.DataRoot);
        Load();
        if (string.IsNullOrWhiteSpace(Current.DownloadRoot)) Current.DownloadRoot = AppPaths.DefaultDownloadRoot;
    }

    public void Save()
    {
        Directory.CreateDirectory(AppPaths.DataRoot);
        var temporary = AppPaths.SettingsFile + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(Current, JsonOptions));
        File.Move(temporary, AppPaths.SettingsFile, true);
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(AppPaths.SettingsFile)) return;
            Current = JsonSerializer.Deserialize<AppSettingsModel>(
                File.ReadAllText(AppPaths.SettingsFile), JsonOptions) ?? new AppSettingsModel();
        }
        catch
        {
            Current = new AppSettingsModel();
        }
    }
}
