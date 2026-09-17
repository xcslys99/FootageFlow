using System.Collections.ObjectModel;
using FootageFlow.Windows.Infrastructure;

namespace FootageFlow.Windows.Models;

public sealed class SearchDuplicateReview
{
    public int ResultCount { get; init; }
    public int UniqueCount { get; init; }
    public IReadOnlyList<SearchDuplicateGroup> Groups { get; init; } = [];
    public IReadOnlyList<SearchDuplicateEntry> Entries { get; init; } = [];
    public IReadOnlyList<string> ThumbnailCandidateIDs { get; init; } = [];
}

public sealed class SearchDuplicateGroup
{
    public string Id { get; init; } = "";
    public IReadOnlyList<string> MemberIDs { get; init; } = [];
    public string RecommendedID { get; init; } = "";
    public string Confidence { get; init; } = "";
    public IReadOnlyList<string> Evidence { get; init; } = [];
}

public sealed class SearchDuplicateEntry
{
    public string Id { get; init; } = "";
    public IReadOnlyList<string> MemberIDs { get; init; } = [];
    public string RecommendedID { get; init; } = "";
    public string? Confidence { get; init; }
}

public sealed class SearchDuplicateDisplayItem : ObservableObject
{
    private bool _expanded;
    public required string Id { get; init; }
    public required MediaAsset Recommended { get; init; }
    public ObservableCollection<MediaAsset> OtherVersions { get; } = [];
    public bool IsGroup => OtherVersions.Count > 0;
    public string Header { get; set; } = "";
    public string RecommendedLabel { get; set; } = "";
    public bool Expanded { get => _expanded; set => Set(ref _expanded, value); }
}
