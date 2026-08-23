import Foundation

/// Stable identifiers shared by the native command surfaces. Platform layers
/// decide how a command is presented, while the actions stay product-level.
enum WorkspaceCommandID: String, CaseIterable, Codable, Hashable, Sendable {
  case searchMedia
  case searchResearch
  case searchAll
  case focusSearch
  case clearSearch
  case globalSearch
  case commandPalette
  case newProject
  case openProjects
  case openResearchNotes
  case openRightsAudit
  case generateCredits
  case exportProject
  case findDuplicates
  case generateContactSheet
  case openFavorites
  case openDownloads
  case openHistory
  case openSavedSearches
  case openSmartCollections
  case openProviderHealth
  case openSettings
  case checkForUpdates
  case retryFailedDownloads

  var titleKey: String { "workspace.command.\(rawValue).title" }
  var subtitleKey: String { "workspace.command.\(rawValue).subtitle" }
}

struct WorkspaceCommand: Identifiable, Hashable, Sendable {
  var id: WorkspaceCommandID
  var shortcut: String

  init(_ id: WorkspaceCommandID, shortcut: String = "") {
    self.id = id
    self.shortcut = shortcut
  }

  static let catalog: [WorkspaceCommand] = [
    .init(.searchMedia), .init(.searchResearch), .init(.searchAll),
    .init(.focusSearch, shortcut: "⌘F"),
    .init(.clearSearch),
    .init(.globalSearch, shortcut: "⌘⇧G"),
    .init(.commandPalette, shortcut: "⌘K"),
    .init(.newProject, shortcut: "⌘N"),
    .init(.openProjects, shortcut: "⌘O"), .init(.openResearchNotes, shortcut: "⌘⇧R"),
    .init(.openRightsAudit), .init(.generateCredits), .init(.exportProject),
    .init(.findDuplicates), .init(.generateContactSheet),
    .init(.openFavorites, shortcut: "⌘⇧F"), .init(.openDownloads, shortcut: "⌘⇧D"),
    .init(.openHistory),
    .init(.openSavedSearches), .init(.openSmartCollections), .init(.openProviderHealth),
    .init(.openSettings, shortcut: "⌘,"), .init(.checkForUpdates),
    .init(.retryFailedDownloads),
  ]

  /// A dependency-free matcher for prefix, substring, and abbreviated command
  /// input. Platform views keep their native selection and execution behavior.
  static func fuzzyMatches(_ candidate: String, query: String) -> Bool {
    let normalizedCandidate = normalizeForMatch(candidate)
    let normalizedQuery = normalizeForMatch(query)
    guard !normalizedQuery.isEmpty else { return true }
    if normalizedCandidate.contains(normalizedQuery) { return true }

    var cursor = normalizedCandidate.startIndex
    for character in normalizedQuery {
      guard let found = normalizedCandidate[cursor...].firstIndex(of: character) else {
        return false
      }
      cursor = normalizedCandidate.index(after: found)
    }
    return true
  }

  private static func normalizeForMatch(_ value: String) -> String {
    value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current
      )
      .filter { !$0.isWhitespace && !$0.isPunctuation }
  }
}

/// An app-level search recipe. It saves only the user's search controls and
/// never stores source files, credentials, or provider response bodies.
struct SavedSearchRecord: Identifiable, Codable, Hashable, Sendable {
  var id: UUID = UUID()
  var name: String
  var query: String
  var keywords: [SearchKeyword] = []
  var searchScope: SearchScope = .media
  var mediaType: MediaType = .video
  var orientation: AssetOrientation = .all
  var resolution: ResolutionFilter = .all
  var duration: DurationFilter = .all
  var licenseFilter: LicenseFilter = .all
  var yearFrom: Int?
  var yearTo: Int?
  var downloadableOnly = false
  var relevanceMode: SearchRelevanceMode = .balanced
  var providerIDs: [String] = ProviderID.searchCases.map(\.rawValue)
  var createdAt: Date = .now
  var updatedAt: Date = .now

  var providerSet: Set<ProviderID> { Set(providerIDs.compactMap(ProviderID.init(rawValue:))) }

  init(
    name: String, query: String, keywords: [SearchKeyword] = [], searchScope: SearchScope = .media,
    mediaType: MediaType = .video, orientation: AssetOrientation = .all,
    resolution: ResolutionFilter = .all, duration: DurationFilter = .all,
    licenseFilter: LicenseFilter = .all, yearFrom: Int? = nil, yearTo: Int? = nil,
    downloadableOnly: Bool = false, relevanceMode: SearchRelevanceMode = .balanced,
    providerIDs: [String] = ProviderID.searchCases.map(\.rawValue)
  ) {
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    self.keywords = keywords
    self.searchScope = searchScope
    self.mediaType = mediaType
    self.orientation = orientation
    self.resolution = resolution
    self.duration = duration
    self.licenseFilter = licenseFilter
    self.yearFrom = yearFrom
    self.yearTo = yearTo
    self.downloadableOnly = downloadableOnly
    self.relevanceMode = relevanceMode
    self.providerIDs = providerIDs
  }
}

enum WorkspaceItemKind: String, Codable, CaseIterable, Hashable, Sendable {
  case project, media, favorite, download, searchHistory, savedSearch, researchReference,
    researchNote,
    localFile

  var localizationKey: String { "workspace.kind.\(rawValue)" }
}

struct WorkspaceSearchEntry: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var kind: WorkspaceItemKind
  var title: String
  var detail: String
  var projectID: UUID?
  var sourceURL: URL?
  var localPath: String?
  var date: Date?
  var searchableText: String

  init(
    id: String, kind: WorkspaceItemKind, title: String, detail: String = "", projectID: UUID? = nil,
    sourceURL: URL? = nil, localPath: String? = nil, date: Date? = nil,
    searchableText: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.projectID = projectID
    self.sourceURL = sourceURL
    self.localPath = localPath
    self.date = date
    self.searchableText = searchableText ?? [title, detail].joined(separator: " ")
  }
}

struct WorkspaceSearchSnapshot: Sendable {
  var projects: [ProjectRecord]
  var favorites: [SavedAssetRecord]
  var downloads: [DownloadRecord]
  var history: [SearchHistoryRecord]
  var savedSearches: [SavedSearchRecord]
  var researchReferences: [ResearchReferenceRecord]
}

enum SmartCollectionID: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
  case downloadedMedia
  case recentDownloads
  case recentFavorites
  case unknownRights
  case attributionRequired
  case researchWithoutNotes
  case recentResearch
  case missingLocalMedia
  case possibleDuplicates

  var id: String { rawValue }
  var titleKey: String { "smartCollection.\(rawValue)" }
}

struct SmartCollectionSummary: Identifiable, Hashable, Sendable {
  var id: SmartCollectionID
  var count: Int
}

struct ProjectDashboardSummary: Identifiable, Hashable, Sendable {
  var id: UUID { project.id }
  var project: ProjectRecord
  var favoriteCount: Int
  var downloadCount: Int
  var researchReferenceCount: Int
  var researchNoteCount: Int
  var segmentCount: Int
  var lastActivity: Date
  var rightsUnknownCount: Int
  var attributionRequiredCount: Int
  var missingLocalMediaCount: Int
  var possibleDuplicateCount: Int
}

enum ProviderHealthState: String, Codable, CaseIterable, Hashable, Sendable {
  case ready, checking, healthy, limited, apiKeyRequired, authenticationRequired, degraded,
    unavailable, rateLimited, disabled, unknown

  var localizationKey: String { "provider.health.\(rawValue)" }
}

struct ProviderHealthRecord: Identifiable, Codable, Hashable, Sendable {
  var id: String { providerID }
  var providerID: String
  var state: ProviderHealthState
  var message: String?
  var testedAt: Date?
  var responseTimeMilliseconds: Int?

  init(
    providerID: String, state: ProviderHealthState = .ready, message: String? = nil,
    testedAt: Date? = nil, responseTimeMilliseconds: Int? = nil
  ) {
    self.providerID = providerID
    self.state = state
    self.message = message
    self.testedAt = testedAt
    self.responseTimeMilliseconds = responseTimeMilliseconds
  }
}

enum WorkspaceCollections {
  private static let recentInterval: TimeInterval = 30 * 24 * 60 * 60

  static func summaries(snapshot: WorkspaceSearchSnapshot) -> [SmartCollectionSummary] {
    let unknownFavorites = snapshot.favorites.filter {
      $0.licenseStatusRaw == LicenseStatus.unknown.rawValue
    }
    let unknownDownloads = snapshot.downloads.filter { $0.asset?.licenseStatus == .unknown }
    let attributionFavorites = snapshot.favorites.filter {
      $0.licenseStatusRaw == LicenseStatus.attributionRequired.rawValue
    }
    let attributionDownloads = snapshot.downloads.filter {
      $0.asset?.licenseStatus == .attributionRequired
    }
    let missing = snapshot.downloads.filter {
      !FileManager.default.fileExists(atPath: $0.localPath)
    }
    let possibleDuplicates = duplicateCount(
      favorites: snapshot.favorites, downloads: snapshot.downloads, projectID: nil)
    let recentDate = Date.now.addingTimeInterval(-recentInterval)
    return [
      .init(id: .downloadedMedia, count: snapshot.downloads.count),
      .init(
        id: .recentDownloads,
        count: snapshot.downloads.filter { $0.downloadedAt >= recentDate }.count),
      .init(
        id: .recentFavorites,
        count: snapshot.favorites.filter { $0.savedAt >= recentDate }.count),
      .init(id: .unknownRights, count: unknownFavorites.count + unknownDownloads.count),
      .init(
        id: .attributionRequired, count: attributionFavorites.count + attributionDownloads.count),
      .init(
        id: .researchWithoutNotes,
        count: snapshot.researchReferences.filter {
          $0.myNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count),
      .init(
        id: .recentResearch,
        count: snapshot.researchReferences.filter { $0.updatedAt >= recentDate }.count),
      .init(id: .missingLocalMedia, count: missing.count),
      .init(id: .possibleDuplicates, count: possibleDuplicates),
    ]
  }

  static func dashboards(snapshot: WorkspaceSearchSnapshot, segments: [ScriptSegmentRecord])
    -> [ProjectDashboardSummary]
  {
    snapshot.projects.map { project in
      let favorites = snapshot.favorites.filter { $0.projectID == project.id }
      let downloads = snapshot.downloads.filter { $0.projectID == project.id }
      let references = snapshot.researchReferences.filter { $0.projectID == project.id }
      let notes = references.filter {
        !$0.myNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      let lastActivity =
        [project.updatedAt]
        + favorites.map(\.savedAt) + downloads.map(\.downloadedAt) + references.map(\.updatedAt)
      let unknown =
        favorites.filter { $0.licenseStatusRaw == LicenseStatus.unknown.rawValue }.count
        + downloads.filter { $0.asset?.licenseStatus == .unknown }.count
      let attribution =
        favorites.filter {
          $0.licenseStatusRaw == LicenseStatus.attributionRequired.rawValue
        }.count + downloads.filter { $0.asset?.licenseStatus == .attributionRequired }.count
      let missing = downloads.filter { !FileManager.default.fileExists(atPath: $0.localPath) }.count
      return ProjectDashboardSummary(
        project: project, favoriteCount: favorites.count, downloadCount: downloads.count,
        researchReferenceCount: references.count, researchNoteCount: notes.count,
        segmentCount: segments.filter { $0.projectID == project.id }.count,
        lastActivity: lastActivity.max() ?? project.updatedAt, rightsUnknownCount: unknown,
        attributionRequiredCount: attribution, missingLocalMediaCount: missing,
        possibleDuplicateCount: duplicateCount(
          favorites: favorites, downloads: downloads, projectID: project.id))
    }
    .sorted { $0.lastActivity > $1.lastActivity }
  }

  private static func duplicateCount(
    favorites: [SavedAssetRecord], downloads: [DownloadRecord], projectID _: UUID?
  ) -> Int {
    let identifiers = favorites.map(\.stableID) + downloads.map(\.stableAssetID)
    return Dictionary(grouping: identifiers, by: { $0 }).values.reduce(into: 0) {
      if $1.count > 1 { $0 += $1.count - 1 }
    }
  }
}
