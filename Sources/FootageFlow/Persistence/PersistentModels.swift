import Foundation

struct ProjectRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var name: String
  var createdAt: Date = .now
  var updatedAt: Date = .now
  var script: String = ""
}

struct ScriptSegmentRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var projectID: UUID?
  var index: Int
  var text: String
  var keywords: [SearchKeyword]
  var createdAt: Date = .now
}

struct SavedAssetRecord: Identifiable, Codable, Hashable {
  var id: String { "\(stableID)|\(projectID?.uuidString ?? "none")" }
  var stableID: String
  var providerRaw: String
  var title: String
  var thumbnailURL: String?
  var sourcePageURL: String
  var licenseName: String?
  var licenseStatusRaw: String
  var projectID: UUID?
  var segmentIndex: Int?
  var savedAt: Date
  var asset: MediaAsset

  init(asset: MediaAsset, projectID: UUID? = nil, segmentIndex: Int? = nil) {
    stableID = asset.stableID
    providerRaw = asset.provider.rawValue
    title = asset.title
    thumbnailURL = asset.thumbnailURL?.absoluteString
    sourcePageURL = asset.sourcePageURL.absoluteString
    licenseName = asset.license
    licenseStatusRaw = asset.licenseStatus.rawValue
    self.projectID = projectID
    self.segmentIndex = segmentIndex
    savedAt = .now
    self.asset = asset
  }

  init(
    stableID: String, providerRaw: String, title: String, thumbnailURL: String?,
    sourcePageURL: String,
    licenseName: String?, licenseStatusRaw: String, projectID: UUID?, segmentIndex: Int?,
    savedAt: Date,
    asset: MediaAsset
  ) {
    self.stableID = stableID
    self.providerRaw = providerRaw
    self.title = title
    self.thumbnailURL = thumbnailURL
    self.sourcePageURL = sourcePageURL
    self.licenseName = licenseName
    self.licenseStatusRaw = licenseStatusRaw
    self.projectID = projectID
    self.segmentIndex = segmentIndex
    self.savedAt = savedAt
    self.asset = asset
  }
}

struct SearchHistoryRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var originalQuery: String
  var keywords: [String]
  var keywordDetails: [SearchKeyword]?
  var providerIDs: [String]
  var projectID: UUID?
  var searchedAt: Date = .now
  var resultCount: Int

  init(
    originalQuery: String, keywords: [String], providers: Set<ProviderID>, projectID: UUID?,
    resultCount: Int, keywordDetails: [SearchKeyword]? = nil
  ) {
    self.originalQuery = originalQuery
    self.keywords = keywords
    self.keywordDetails = keywordDetails
    providerIDs = providers.map(\.rawValue).sorted()
    self.projectID = projectID
    self.resultCount = resultCount
  }
}

struct DownloadRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var stableAssetID: String
  var providerRaw: String
  var sourceName: String?
  var title: String
  var fileName: String
  var localPath: String
  var thumbnailURL: String?
  var sourcePageURL: String
  var projectID: UUID?
  var downloadedAt: Date = .now
  var outputPresetRaw: String?
  var clipStartSeconds: Double?
  var clipEndSeconds: Double?
  var clipDurationSeconds: Double?
  /// A full, non-secret asset snapshot was added in v0.8.0. It stays optional so
  /// records written by earlier FootageFlow versions remain readable.
  var asset: MediaAsset?

  init(asset: MediaAsset, fileURL: URL, projectID: UUID?) {
    stableAssetID = asset.stableID
    providerRaw = asset.provider.rawValue
    sourceName = asset.sourceDisplayName
    title = asset.title
    fileName = fileURL.lastPathComponent
    localPath = fileURL.path
    thumbnailURL = asset.thumbnailURL?.absoluteString
    sourcePageURL = asset.sourcePageURL.absoluteString
    self.projectID = projectID
    outputPresetRaw = asset.originalMetadata["linkOutputPreset"]
    clipStartSeconds = asset.originalMetadata["linkClipStart"].flatMap(Double.init)
    clipEndSeconds = asset.originalMetadata["linkClipEnd"].flatMap(Double.init)
    clipDurationSeconds = asset.originalMetadata["linkClipDuration"].flatMap(Double.init)
    self.asset = asset
  }

  init(
    stableAssetID: String, providerRaw: String, sourceName: String?, title: String,
    fileName: String,
    localPath: String, thumbnailURL: String?, sourcePageURL: String, projectID: UUID?,
    downloadedAt: Date, outputPresetRaw: String?, clipStartSeconds: Double?,
    clipEndSeconds: Double?,
    clipDurationSeconds: Double?, asset: MediaAsset?
  ) {
    self.stableAssetID = stableAssetID
    self.providerRaw = providerRaw
    self.sourceName = sourceName
    self.title = title
    self.fileName = fileName
    self.localPath = localPath
    self.thumbnailURL = thumbnailURL
    self.sourcePageURL = sourcePageURL
    self.projectID = projectID
    self.downloadedAt = downloadedAt
    self.outputPresetRaw = outputPresetRaw
    self.clipStartSeconds = clipStartSeconds
    self.clipEndSeconds = clipEndSeconds
    self.clipDurationSeconds = clipDurationSeconds
    self.asset = asset
  }

  var workflowSummary: String? {
    guard let outputPresetRaw,
      let output = EditingOutputPreset(rawValue: outputPresetRaw)
    else { return nil }
    var parts = ["\(tr("link.outputFormat")): \(output.label)"]
    if let start = clipStartSeconds, let end = clipEndSeconds {
      parts.append("\(tr("link.clip.start")): \(TimecodeParser.string(start))")
      parts.append("\(tr("link.clip.end")): \(TimecodeParser.string(end))")
      if let duration = clipDurationSeconds {
        parts.append(tr("link.clip.duration", TimecodeParser.string(duration)))
      }
    }
    return parts.joined(separator: " · ")
  }
}

/// User acknowledgement only. It deliberately never changes source-supplied
/// rights metadata or turns an unknown license into a known one.
struct ProjectReviewRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var projectID: UUID
  var stableAssetID: String
  var reviewedAt: Date = .now
}

enum DuplicateDecision: String, Codable, Hashable, Sendable {
  case keepBoth
  case notDuplicate
}

/// A project-scoped decision for one deterministic pair of assets. Keeping it
/// separate from provider metadata preserves the original provider record.
struct DuplicateDecisionRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var projectID: UUID
  var pairKey: String
  var decision: DuplicateDecision
  var updatedAt: Date = .now
}

struct FileHashCacheRecord: Identifiable, Codable, Hashable {
  var id: String { localPath }
  var localPath: String
  var fileSize: Int64
  var modificationDate: Date
  var sha256: String
  var calculatedAt: Date = .now
}

struct PersistentDatabase: Codable {
  var projects: [ProjectRecord] = []
  var segments: [ScriptSegmentRecord] = []
  var favorites: [SavedAssetRecord] = []
  var history: [SearchHistoryRecord] = []
  var downloads: [DownloadRecord] = []
  // Optional collections provide additive, backward-compatible decoding for
  // databases created before the v0.8.0 project workflow release.
  var reviewedAssets: [ProjectReviewRecord]? = []
  var duplicateDecisions: [DuplicateDecisionRecord]? = []
  var fileHashCache: [FileHashCacheRecord]? = []
}
