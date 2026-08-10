using FootageFlow.Windows.Infrastructure;

namespace FootageFlow.Windows.Models;

public sealed class LinkAnalysisResult
{
    public string Id { get; init; } = "";
    public string OriginalURL { get; init; } = "";
    public string SourceName { get; init; } = "";
    public string Title { get; init; } = "";
    public string? Creator { get; init; }
    public string? ThumbnailURL { get; init; }
    public double? Duration { get; init; }
    public IReadOnlyList<int> ProgressiveHeights { get; init; } = [];
    public bool HasAudio { get; init; }
    public IReadOnlyList<string> SubtitleLanguages { get; init; } = [];
    public int FormatCount { get; init; }
}

public sealed record LinkQualityChoice(string Id, string Label);

public sealed class LinkDownloadItem(string rawUrl) : ObservableObject
{
    private bool _isSelected = true;
    private string _selectedQuality = "best";
    private bool _downloadSubtitles;
    private string _subtitleLanguage = "";
    private LinkAnalysisResult? _analysis;
    private string? _errorMessage;

    public Guid Id { get; } = Guid.NewGuid();
    public string RawURL { get; } = rawUrl;
    public bool IsSelected { get => _isSelected; set => Set(ref _isSelected, value); }
    public string SelectedQuality { get => _selectedQuality; set => Set(ref _selectedQuality, value); }
    public bool DownloadSubtitles { get => _downloadSubtitles; set => Set(ref _downloadSubtitles, value); }
    public string SubtitleLanguage { get => _subtitleLanguage; set => Set(ref _subtitleLanguage, value); }
    public LinkAnalysisResult? Analysis
    {
        get => _analysis;
        set
        {
            if (!Set(ref _analysis, value)) return;
            OnPropertyChanged(nameof(IsReady)); OnPropertyChanged(nameof(Title));
            OnPropertyChanged(nameof(SourceSummary)); OnPropertyChanged(nameof(ThumbnailURL));
            OnPropertyChanged(nameof(AvailableQualities)); OnPropertyChanged(nameof(SubtitleLanguages));
            OnPropertyChanged(nameof(HasSubtitles)); OnPropertyChanged(nameof(FormatCount));
        }
    }
    public string? ErrorMessage { get => _errorMessage; set => Set(ref _errorMessage, value); }
    public bool IsReady => Analysis is not null && string.IsNullOrWhiteSpace(ErrorMessage);
    public string DownloadIdentity => $"{Analysis?.Id ?? "link"}:{SelectedQuality}" +
        (DownloadSubtitles ? $":subs:{(string.IsNullOrWhiteSpace(SubtitleLanguage) ? "all" : SubtitleLanguage)}" : "");
    public string Title => Analysis?.Title ?? RawURL;
    public string? ThumbnailURL => Analysis?.ThumbnailURL;
    public string SourceSummary => string.Join(" · ", new[]
        { Analysis?.SourceName, Analysis?.Creator, DurationText(Analysis?.Duration) }.Where(value => !string.IsNullOrWhiteSpace(value)));
    public int FormatCount => Analysis?.FormatCount ?? 0;
    public IReadOnlyList<string> SubtitleLanguages => Analysis?.SubtitleLanguages ?? [];
    public bool HasSubtitles => SubtitleLanguages.Count > 0;
    public IReadOnlyList<string> AvailableQualities
    {
        get
        {
            var result = new List<string> { "best" };
            var heights = Analysis?.ProgressiveHeights ?? [];
            if (heights.Any(value => value >= 1080)) result.Add("p1080");
            if (heights.Any(value => value >= 720)) result.Add("p720");
            if (heights.Any(value => value >= 480)) result.Add("p480");
            if (Analysis?.HasAudio == true) result.Add("audioOnly");
            return result;
        }
    }

    public IReadOnlyList<LinkQualityChoice> QualityChoices { get; private set; } = [];

    public void ConfigureQualityLabels(Func<string, string> label)
    {
        QualityChoices = AvailableQualities.Select(id => new LinkQualityChoice(id, label(id))).ToArray();
        OnPropertyChanged(nameof(QualityChoices));
    }

    private static string? DurationText(double? value) => value is null
        ? null : $"{(int)(value.Value / 60):00}:{(int)(value.Value % 60):00}";
}
