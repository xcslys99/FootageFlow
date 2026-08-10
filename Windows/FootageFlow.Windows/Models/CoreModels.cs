using System.Text.Json.Serialization;

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
    public int? PageSize { get; init; }
    public IReadOnlyList<string>? ProviderIDs { get; init; }
    public IReadOnlyDictionary<string, string>? ApiKeys { get; init; }
    public string? Language { get; init; }
    public MediaAsset? Asset { get; init; }
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
    public string Title { get; init; } = "";
    public string FileName { get; init; } = "";
    public string LocalPath { get; init; } = "";
    public string? ThumbnailURL { get; init; }
    public string SourcePageURL { get; init; } = "";
    public Guid? ProjectID { get; init; }
    public DateTimeOffset DownloadedAt { get; init; }
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
    public bool SupportsVideo { get; init; }
    public bool SupportsImage { get; init; }
    public IReadOnlyList<string> AccessMethods { get; init; } = [];
}

public sealed class ProviderBatch
{
    public string Provider { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Mode { get; init; } = "";
    public ProviderState State { get; init; } = new();
    public IReadOnlyList<MediaAsset> Assets { get; init; } = [];
    public string? ErrorCode { get; init; }
}

public sealed class ProviderState
{
    public string Availability { get; init; } = "unavailable";
    public string? Message { get; init; }
    public string? Mode { get; init; }
}

public sealed class SearchKeyword
{
    public Guid Id { get; init; }
    public string Text { get; init; } = "";
    public bool IsEnabled { get; init; }
}

public sealed class MediaAsset
{
    public string Id { get; init; } = "";
    public string Provider { get; init; } = "";
    public string Title { get; init; } = "";
    public string? Description { get; init; }
    public string? ThumbnailURL { get; init; }
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

    [JsonIgnore] public string StableId => $"{Provider}:{Id}";
    [JsonIgnore] public string Resolution => Width is > 0 && Height is > 0 ? $"{Width}×{Height}" : "—";
    [JsonIgnore] public string DurationText => Duration is null ? "—" : TimeSpan.FromSeconds(Duration.Value).ToString(@"mm\:ss");
    [JsonIgnore] public string LicenseText => string.IsNullOrWhiteSpace(License) ? LicenseStatus : License;
}
