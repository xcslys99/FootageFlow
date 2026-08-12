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
}

struct SearchHistoryRecord: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var originalQuery: String
  var keywords: [String]
  var providerIDs: [String]
  var projectID: UUID?
  var searchedAt: Date = .now
  var resultCount: Int

  init(
    originalQuery: String, keywords: [String], providers: Set<ProviderID>, projectID: UUID?,
    resultCount: Int
  ) {
    self.originalQuery = originalQuery
    self.keywords = keywords
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

struct PersistentDatabase: Codable {
  var projects: [ProjectRecord] = []
  var segments: [ScriptSegmentRecord] = []
  var favorites: [SavedAssetRecord] = []
  var history: [SearchHistoryRecord] = []
  var downloads: [DownloadRecord] = []
}
