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
public sealed record LinkChoice(string Id, string Label);

public sealed class LinkDownloadItem(string rawUrl) : ObservableObject
{
    private bool _isSelected = true;
    private string _selectedQuality = "best";
    private bool _downloadSubtitles;
    private string _subtitleLanguage = "";
    private LinkAnalysisResult? _analysis;
    private string? _errorMessage;
    private string _selectedScope = "full";
    private string _outputPreset = "original";
    private string _clipStart = "00:00:00";
    private string _clipEnd = "";
    private Func<string, string>? _clipErrorLabel;

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
    public string SelectedScope { get => _selectedScope; set { if (Set(ref _selectedScope, value)) NotifyClip(); } }
    public string OutputPreset { get => _outputPreset; set { if (Set(ref _outputPreset, value)) OnPropertyChanged(nameof(DownloadIdentity)); } }
    public string ClipStart { get => _clipStart; set { if (Set(ref _clipStart, value)) NotifyClip(); } }
    public string ClipEnd { get => _clipEnd; set { if (Set(ref _clipEnd, value)) NotifyClip(); } }
    public bool IsReady => Analysis is not null && string.IsNullOrWhiteSpace(ErrorMessage) &&
        (SelectedScope != "clip" || ClipError is null);
    public string? ClipError
    {
        get
        {
            if (SelectedScope != "clip") return null;
            if (Analysis?.Duration is not > 0) return "unknownDuration";
            if (!Timecode.TryParse(ClipStart, out var start) || !Timecode.TryParse(ClipEnd, out var end))
                return "invalidFormat";
            if (start < 0 || end <= start || end - start < .5) return "invalidRange";
            return end > Analysis.Duration.Value + .05 ? "beyondDuration" : null;
        }
    }
    public string? ClipErrorText => ClipError is { } value ? _clipErrorLabel?.Invoke(value) ?? value : null;
    public double? ClipStartSeconds => Timecode.TryParse(ClipStart, out var value) ? value : null;
    public double? ClipEndSeconds => Timecode.TryParse(ClipEnd, out var value) ? value : null;
    public double? ClipDuration => ClipStartSeconds is { } start && ClipEndSeconds is { } end && end > start
        ? end - start : null;
    public string DownloadIdentity => $"{Analysis?.Id ?? "link"}:{SelectedQuality}:{OutputPreset}" +
        (SelectedScope == "clip" ? $":clip:{ClipStartSeconds}-{ClipEndSeconds}" : "") +
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
    public IReadOnlyList<LinkChoice> ScopeChoices { get; private set; } = [];
    public IReadOnlyList<LinkChoice> OutputChoices { get; private set; } = [];

    public void ConfigureQualityLabels(Func<string, string> label)
    {
        QualityChoices = AvailableQualities.Where(id => id != "audioOnly")
            .Select(id => new LinkQualityChoice(id, label(id))).ToArray();
        OnPropertyChanged(nameof(QualityChoices));
    }

    public void ConfigureCreatorLabels(
        Func<string, string> scopeLabel, Func<string, string> outputLabel,
        Func<string, string> clipErrorLabel)
    {
        ScopeChoices = new[] { "full", "clip" }.Select(id => new LinkChoice(id, scopeLabel(id))).ToArray();
        OutputChoices = new[] { "original", "editingCompatibleMP4", "audioOnly" }
            .Select(id => new LinkChoice(id, outputLabel(id))).ToArray();
        _clipErrorLabel = clipErrorLabel;
        OnPropertyChanged(nameof(ScopeChoices)); OnPropertyChanged(nameof(OutputChoices));
        OnPropertyChanged(nameof(ClipErrorText));
    }

    public void InitializeClipEnd()
    {
        if (Analysis?.Duration is > 0) ClipEnd = Timecode.Format(Analysis.Duration.Value);
    }

    private void NotifyClip()
    {
        OnPropertyChanged(nameof(ClipError)); OnPropertyChanged(nameof(ClipStartSeconds));
        OnPropertyChanged(nameof(ClipEndSeconds)); OnPropertyChanged(nameof(ClipDuration));
        OnPropertyChanged(nameof(IsReady)); OnPropertyChanged(nameof(DownloadIdentity));
        OnPropertyChanged(nameof(ClipErrorText));
    }

    private static string? DurationText(double? value) => value is null
        ? null : $"{(int)(value.Value / 60):00}:{(int)(value.Value % 60):00}";
}

public static class Timecode
{
    public static bool TryParse(string? raw, out double seconds)
    {
        seconds = 0;
        if (string.IsNullOrWhiteSpace(raw)) return false;
        var fields = raw.Trim().Split(':');
        if (fields.Length is < 1 or > 3) return false;
        var values = new List<double>();
        foreach (var field in fields)
        {
            if (!double.TryParse(field, System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var value) || value < 0 ||
                double.IsNaN(value) || double.IsInfinity(value)) return false;
            values.Add(value);
        }
        if (values.Skip(1).Any(value => value >= 60)) return false;
        seconds = values.Count switch
        {
            1 => values[0], 2 => values[0] * 60 + values[1],
            3 => values[0] * 3600 + values[1] * 60 + values[2], _ => 0
        };
        return true;
    }

    public static string Format(double seconds)
    {
        var total = Math.Max(0, (int)Math.Floor(seconds));
        return $"{total / 3600:00}:{total / 60 % 60:00}:{total % 60:00}";
    }
}
