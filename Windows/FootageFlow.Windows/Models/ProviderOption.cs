using FootageFlow.Windows.Infrastructure;

namespace FootageFlow.Windows.Models;

public sealed class ProviderOption(string id, string displayName, bool enabled) : ObservableObject
{
    private bool _enabled = enabled;
    private string _status = "Available";
    private string _mode = "Public interface";
    private string _capabilities = "";
    public string Id { get; } = id;
    public string DisplayName { get; } = displayName;
    public bool Enabled { get => _enabled; set => Set(ref _enabled, value); }
    public string Status { get => _status; set => Set(ref _status, value); }
    public string Mode { get => _mode; set => Set(ref _mode, value); }
    public string Capabilities { get => _capabilities; set => Set(ref _capabilities, value); }
    public bool SupportsApiKey => Id is "pexels" or "pixabay" or "youtube" or "nationalArchives" or "europeana" or "coverr" or "vimeo";
    public bool CanOpenOfficialSearch => Id is "nasa" or "libraryOfCongress" or "nationalArchives" or "europeana" or "peertube" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" or "dailymotion";
}
