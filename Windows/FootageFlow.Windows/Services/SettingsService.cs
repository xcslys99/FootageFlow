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

    private readonly string? _settingsFile;
    public AppSettingsModel Current { get; private set; } = new();

    public SettingsService(AppSettingsModel? initial = null, string? settingsFile = null)
    {
        if (initial is not null)
        {
            Current = initial;
            _settingsFile = settingsFile;
            return;
        }
        _settingsFile = settingsFile ?? AppPaths.SettingsFile;
        Directory.CreateDirectory(AppPaths.DataRoot);
        Load();
        if (!Current.DiscoveryProvidersV3Added)
        {
            Current.EnabledProviders.UnionWith(
                ["nasa", "libraryOfCongress", "nationalArchives", "europeana"]);
            Current.DiscoveryProvidersV3Added = true;
            Save();
        }
        if (!Current.SearchExpansionProvidersV5Added)
        {
            Current.EnabledProviders.UnionWith(
                ["peertube", "videvo", "videezy", "mixkit", "coverr", "vimeo"]);
            Current.SearchExpansionProvidersV5Added = true;
            Save();
        }
        if (!Current.CreatorWorkflowProvidersV6Added)
        {
            Current.EnabledProviders.UnionWith(["openverse", "dailymotion"]);
            Current.CreatorWorkflowProvidersV6Added = true;
            Save();
        }
        if (string.IsNullOrWhiteSpace(Current.DownloadRoot)) Current.DownloadRoot = AppPaths.DefaultDownloadRoot;
    }

    public void Save()
    {
        if (string.IsNullOrWhiteSpace(_settingsFile)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsFile)!);
        var temporary = _settingsFile + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(Current, JsonOptions));
        File.Move(temporary, _settingsFile, true);
    }

    private void Load()
    {
        try
        {
            if (string.IsNullOrWhiteSpace(_settingsFile) || !File.Exists(_settingsFile)) return;
            Current = JsonSerializer.Deserialize<AppSettingsModel>(
                File.ReadAllText(_settingsFile), JsonOptions) ?? new AppSettingsModel();
        }
        catch
        {
            Current = new AppSettingsModel();
        }
    }
}
