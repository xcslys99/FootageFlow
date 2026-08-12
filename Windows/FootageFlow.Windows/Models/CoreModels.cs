using System.Text.Json.Serialization;
using FootageFlow.Windows.Infrastructure;
using FootageFlow.Windows.Services;

namespace FootageFlow.Windows.Models;

public sealed class CoreRequest
{
    public string Id { get; init; } = Guid.NewGuid().ToString("N");
    public required string Action { get; init; }
    public string? Query { get; init; }
    public string? MediaType { get; init; }
    public string? Orientation { get; init; }
    public string? Resolution { get; init; }
    public string? Duration { get; init; }
    public int? YearFrom { get; init; }
    public int? YearTo { get; init; }
    public bool? DownloadableOnly { get; init; }
    public int? PageSize { get; init; }
    public ProviderContinuation? Continuation { get; init; }
    public IReadOnlyList<string>? ProviderIDs { get; init; }
    public IReadOnlyDictionary<string, string>? ApiKeys { get; init; }
    public string? Language { get; init; }
    public MediaAsset? Asset { get; init; }
    public IReadOnlyList<MediaAsset>? Assets { get; init; }
    public string? RelevanceMode { get; init; }
    public string? MediaPath { get; init; }
    public string? ProjectName { get; init; }
    public string? ProjectID { get; init; }
    public string? ProjectScript { get; init; }
    public string? RecordID { get; init; }
    public string? LocalPath { get; init; }
    public IReadOnlyList<string>? Keywords { get; init; }
    public int? ResultCount { get; init; }
    public int? SegmentIndex { get; init; }
    public string? ExternalToolOutputBase64 { get; init; }
    public string? FeedbackDestination { get; init; }
    public bool? SmartExpansion { get; init; }
    public string? DeferredUpdateVersion { get; init; }
    public DateTimeOffset? DeferredUpdateUntil { get; init; }
    public bool? ForceUpdatePrompt { get; init; }
}

public sealed class CoreResponse
{
    public string Id { get; init; } = "";
    public bool Success { get; init; }
    public string Version { get; init; } = "";
    public string Platform { get; init; } = "";
    public IReadOnlyList<ProviderDescriptor>? Providers { get; init; }
    public IReadOnlyList<ProviderBatch>? ProviderBatches { get; init; }
    public IReadOnlyList<MediaAsset>? Assets { get; init; }
    public IReadOnlyList<SearchKeyword>? Keywords { get; init; }
    public IReadOnlyList<string>? Segments { get; init; }
    public PersistentDatabase? Database { get; init; }
    public ProjectRecord? Project { get; init; }
    public string? FileName { get; init; }
    public string? ErrorCode { get; init; }
    public string? ErrorMessage { get; init; }
    public string? Text { get; init; }
    public string? UpdateStatus { get; init; }
    public AppReleaseInfo? Release { get; init; }
}

public sealed class AppReleaseInfo
{
    public string Version { get; init; } = "";
    public string Title { get; init; } = "";
    public string Notes { get; init; } = "";
    public string PageURL { get; init; } = "";
    public DateTimeOffset? PublishedAt { get; init; }
}

public sealed class PersistentDatabase
{
    public IReadOnlyList<ProjectRecord> Projects { get; init; } = [];
    public IReadOnlyList<ScriptSegmentRecord> Segments { get; init; } = [];
    public IReadOnlyList<SavedAssetRecord> Favorites { get; init; } = [];
    public IReadOnlyList<SearchHistoryRecord> History { get; init; } = [];
    public IReadOnlyList<DownloadRecord> Downloads { get; init; } = [];
}

public sealed class ProjectRecord
{
    public Guid Id { get; init; }
    public string Name { get; init; } = "";
    public DateTimeOffset CreatedAt { get; init; }
    public DateTimeOffset UpdatedAt { get; init; }
    public string Script { get; init; } = "";
}

public sealed class ScriptSegmentRecord
{
    public Guid Id { get; init; }
    public Guid? ProjectID { get; init; }
    public int Index { get; init; }
    public string Text { get; init; } = "";
    public IReadOnlyList<SearchKeyword> Keywords { get; init; } = [];
    public DateTimeOffset CreatedAt { get; init; }
}

public sealed class SavedAssetRecord
{
    public string Id { get; init; } = "";
    public string StableID { get; init; } = "";
    public string ProviderRaw { get; init; } = "";
    public string Title { get; init; } = "";
    public string? ThumbnailURL { get; init; }
    public string SourcePageURL { get; init; } = "";
    public string? LicenseName { get; init; }
    public string LicenseStatusRaw { get; init; } = "UNKNOWN";
    public Guid? ProjectID { get; init; }
    public int? SegmentIndex { get; init; }
    public DateTimeOffset SavedAt { get; init; }
    public MediaAsset Asset { get; init; } = new();
}

public sealed class SearchHistoryRecord
{
    public Guid Id { get; init; }
    public string OriginalQuery { get; init; } = "";
    public IReadOnlyList<string> Keywords { get; init; } = [];
    public IReadOnlyList<string> ProviderIDs { get; init; } = [];
    public Guid? ProjectID { get; init; }
    public DateTimeOffset SearchedAt { get; init; }
    public int ResultCount { get; init; }
}

public sealed class DownloadRecord
{
    public Guid Id { get; init; }
    public string StableAssetID { get; init; } = "";
    public string ProviderRaw { get; init; } = "";
    public string? SourceName { get; init; }
    public string Title { get; init; } = "";
    public string FileName { get; init; } = "";
    public string LocalPath { get; init; } = "";
    public string? ThumbnailURL { get; init; }
    public string SourcePageURL { get; init; } = "";
    public Guid? ProjectID { get; init; }
    public DateTimeOffset DownloadedAt { get; init; }
    public string? OutputPresetRaw { get; init; }
    public double? ClipStartSeconds { get; init; }
    public double? ClipEndSeconds { get; init; }
    public double? ClipDurationSeconds { get; init; }
    public string DisplaySource => string.IsNullOrWhiteSpace(SourceName) ? ProviderRaw : SourceName;
    [JsonIgnore] public string WorkflowSummary { get; set; } = "";
}

public sealed class ProviderDescriptor
{
    public string Id { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Mode { get; init; } = "";
    public bool RequiresAPIKey { get; init; }
    public ProviderCapabilities Capabilities { get; init; } = new();
}

public sealed class ProviderCapabilities
{
    public string Search { get; init; } = "unavailable";
    public string Preview { get; init; } = "unavailable";
    public string Metadata { get; init; } = "unavailable";
    public string License { get; init; } = "unavailable";
    public string Download { get; init; } = "unavailable";
    public string Pagination { get; init; } = "unavailable";
    public bool SupportsVideo { get; init; }
    public bool SupportsImage { get; init; }
    public bool SupportsAudio { get; init; }
    public IReadOnlyList<string> AccessMethods { get; init; } = [];
}

public sealed class ProviderBatch
{
    public string Provider { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Mode { get; init; } = "";
    public ProviderState State { get; init; } = new();
    public IReadOnlyList<MediaAsset> Assets { get; init; } = [];
    public ProviderContinuation? Continuation { get; init; }
    public int? TotalResults { get; init; }
    public string? ErrorCode { get; init; }
}

public sealed class ProviderContinuation
{
    public int? Page { get; init; }
    public int? Offset { get; init; }
    public string? Token { get; init; }
    public string? Cursor { get; init; }
    public string? NextURL { get; init; }
}

public sealed class ProviderState
{
    public string Availability { get; init; } = "unavailable";
    public string? Message { get; init; }
    public string? Mode { get; init; }
}

public sealed class SearchKeyword
{
    public Guid Id { get; set; }
    public string Text { get; set; } = "";
    public bool IsEnabled { get; set; }
}

public sealed class MediaAsset : ObservableObject
{
    private bool _isSelected;
    public string Id { get; init; } = "";
    public string Provider { get; init; } = "";
    public string Title { get; init; } = "";
    public string? Description { get; init; }
    public string? ThumbnailURL { get; init; }
    public IReadOnlyList<string>? ThumbnailCandidates { get; init; }
    public string? PreviewURL { get; init; }
    public string? DownloadURL { get; init; }
    public string SourcePageURL { get; init; } = "";
    public string? Creator { get; init; }
    public string? License { get; init; }
    public string? LicenseURL { get; init; }
    public string LicenseStatus { get; init; } = "UNKNOWN";
    public int? Width { get; init; }
    public int? Height { get; init; }
    public double? Duration { get; init; }
    public string? FileType { get; init; }
    public string MediaType { get; init; } = "video";
    public DateTimeOffset? PublishedDate { get; init; }
    public bool Downloadable { get; init; }
    public Dictionary<string, string> OriginalMetadata { get; init; } = [];
    public string SearchKeyword { get; init; } = "";
    public double RelevanceScore { get; init; }
    public string? DownloadStrategy { get; init; }
    public RightsInfo? RightsInfo { get; init; }
    public string? DownloadAvailability { get; init; }
    [JsonIgnore] public bool IsSelected { get => _isSelected; set => Set(ref _isSelected, value); }

    [JsonIgnore] public string StableId => $"{Provider}:{Id}";
    [JsonIgnore] public IReadOnlyList<string> EffectiveThumbnailURLs => ThumbnailUrlNormalizer.Normalize(
        Provider,
        new[] { ThumbnailURL }
            .Concat(ThumbnailCandidates ?? [])
            .Concat(MediaType == "image" ? new[] { PreviewURL, DownloadURL } : [])
            .Concat(new[]
            {
                OriginalMetadata.GetValueOrDefault("thumbnail"),
                OriginalMetadata.GetValueOrDefault("previewImage"),
                OriginalMetadata.GetValueOrDefault("poster"),
                OriginalMetadata.GetValueOrDefault("image")
            }),
        SourcePageURL,
        OriginalMetadata);
    [JsonIgnore] public string SourceDisplayName =>
        OriginalMetadata.GetValueOrDefault("sourceName") ?? Provider;
    [JsonIgnore] public string Resolution => Width is > 0 && Height is > 0 ? $"{Width}×{Height}" : "—";
    [JsonIgnore] public string DurationText => Duration is null
        ? "—"
        : $"{(int)(Duration.Value / 60):00}:{(int)(Duration.Value % 60):00}";
    [JsonIgnore] public long PixelCount => (long)(Width ?? 0) * (Height ?? 0);
    [JsonIgnore] public DateTimeOffset SortPublishedDate => PublishedDate ?? DateTimeOffset.MinValue;
    [JsonIgnore] public double SortDuration => Duration ?? -1;
    [JsonIgnore] public bool IsDirectlyDownloadable => DownloadAvailability == "direct" ||
        (DownloadAvailability is null && Downloadable && !string.IsNullOrWhiteSpace(DownloadURL));
    [JsonIgnore] public bool SupportsEditingOutput => Downloadable && DownloadStrategy == "ytDLP";
    [JsonIgnore] public bool RightsKnown => RightsInfo?.Known ?? LicenseStatus != "UNKNOWN";
    [JsonIgnore] public bool OpenLicense => RightsInfo?.OpenLicense ??
        LicenseStatus is "SAFE" or "ATTRIBUTION_REQUIRED" or "PUBLIC_DOMAIN";
    [JsonIgnore] public bool PublicDomain => RightsInfo?.PublicDomain ?? LicenseStatus == "PUBLIC_DOMAIN";

    public MediaAsset CloneForWorkflow(
        string workflowId, Dictionary<string, string> metadata, string mediaType, string? fileType) =>
        new()
        {
            Id = workflowId, Provider = Provider, Title = Title, Description = Description,
            ThumbnailURL = ThumbnailURL, ThumbnailCandidates = ThumbnailCandidates,
            PreviewURL = PreviewURL, DownloadURL = DownloadURL, SourcePageURL = SourcePageURL,
            Creator = Creator, License = License, LicenseURL = LicenseURL,
            LicenseStatus = LicenseStatus, Width = Width, Height = Height, Duration = Duration,
            FileType = fileType, MediaType = mediaType, PublishedDate = PublishedDate,
            Downloadable = Downloadable, OriginalMetadata = metadata,
            SearchKeyword = SearchKeyword, RelevanceScore = RelevanceScore,
            DownloadStrategy = DownloadStrategy, RightsInfo = RightsInfo,
            DownloadAvailability = DownloadAvailability
        };
}

public sealed class RightsInfo
{
    public string? Statement { get; init; }
    public string? Uri { get; init; }
    public string? Source { get; init; }
    public bool Known { get; init; }
    public bool PublicDomain { get; init; }
    public bool OpenLicense { get; init; }
    public bool AttributionRequired { get; init; }
    public bool? CommercialUseKnown { get; init; }
}
