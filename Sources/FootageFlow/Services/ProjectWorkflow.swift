import Foundation

// MARK: - Project asset inventory

/// A lossless-enough, project-scoped view over the existing favorites and
/// downloads collections. It is deliberately a view model, not a second
/// project database: the existing records remain the source of truth.
struct ProjectAssetItem: Identifiable, Codable, Hashable {
  var stableID: String
  var providerRaw: String
  var providerName: String
  var providerNativeID: String?
  var title: String
  var creator: String?
  var thumbnailURL: URL?
  var sourcePageURL: URL?
  var mediaURL: URL?
  var mediaType: MediaType?
  var fileType: String?
  var width: Int?
  var height: Int?
  var duration: Double?
  var license: String?
  var licenseURL: URL?
  var licenseStatus: LicenseStatus
  var rightsInfo: RightsInfo?
  var searchKeyword: String?
  var segmentIndex: Int?
  var savedAt: Date?
  var downloadedAt: Date?
  var localFileName: String?
  /// Available only in-memory. It is intentionally removed from standard
  /// exports and portable project manifests.
  var localPath: String?
  var outputPresetRaw: String?
  var clipStartSeconds: Double?
  var clipEndSeconds: Double?
  var sourceSidecarFileName: String?
  /// A portable backup deliberately does not carry large media. This transient
  /// marker makes the resulting missing-reference state visible after import.
  var localMediaMissing: Bool

  var id: String { stableID }
  var effectiveRightsInfo: RightsInfo {
    rightsInfo
      ?? RightsInfo(
        statement: license, uri: licenseURL, source: providerName,
        known: licenseStatus != .unknown,
        publicDomain: licenseStatus == .publicDomain,
        openLicense: [.safe, .attributionRequired, .publicDomain].contains(licenseStatus),
        attributionRequired: licenseStatus == .attributionRequired)
  }
  var rightsKnown: Bool { effectiveRightsInfo.known }
  var originalPageAvailable: Bool {
    guard let sourcePageURL, let scheme = sourcePageURL.scheme?.lowercased(),
      ["https", "http"].contains(scheme), sourcePageURL.host?.isEmpty == false
    else { return false }
    return true
  }

  init(saved: SavedAssetRecord) {
    self.init(asset: saved.asset, segmentIndex: saved.segmentIndex, savedAt: saved.savedAt)
  }

  init(download: DownloadRecord) {
    let asset = download.asset
    stableID = download.stableAssetID
    providerRaw = asset?.provider.rawValue ?? download.providerRaw
    providerName =
      asset?.sourceDisplayName
      ?? download.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? download.providerRaw
    providerNativeID = asset?.id ?? ProjectAssetItem.nativeID(from: download.stableAssetID)
    title = asset?.title ?? download.title
    creator = asset?.creator
    thumbnailURL = asset?.thumbnailURL ?? URL(string: download.thumbnailURL ?? "")
    sourcePageURL = asset?.sourcePageURL ?? URL(string: download.sourcePageURL)
    mediaURL = asset?.downloadURL
    mediaType = asset?.mediaType
    fileType = asset?.fileType ?? URL(fileURLWithPath: download.fileName).pathExtension.nilIfEmpty
    width = asset?.width
    height = asset?.height
    duration = asset?.duration ?? download.clipDurationSeconds
    license = asset?.license
    licenseURL = asset?.licenseURL
    licenseStatus = asset?.licenseStatus ?? .unknown
    rightsInfo = asset?.rightsInfo
    searchKeyword = asset?.searchKeyword
    segmentIndex = nil
    savedAt = nil
    downloadedAt = download.downloadedAt
    localFileName = download.fileName
    localPath = download.localPath
    outputPresetRaw = download.outputPresetRaw
    clipStartSeconds = download.clipStartSeconds
    clipEndSeconds = download.clipEndSeconds
    sourceSidecarFileName = ProjectAssetItem.sidecarName(for: download.fileName)
    localMediaMissing =
      !download.fileName.isEmpty
      && (download.localPath.isEmpty || !FileManager.default.fileExists(atPath: download.localPath))
  }

  init(
    asset: MediaAsset, segmentIndex: Int? = nil, savedAt: Date? = nil, downloadedAt: Date? = nil,
    localFileName: String? = nil, localPath: String? = nil, outputPresetRaw: String? = nil,
    clipStartSeconds: Double? = nil, clipEndSeconds: Double? = nil,
    sourceSidecarFileName: String? = nil
  ) {
    stableID = asset.stableID
    providerRaw = asset.provider.rawValue
    providerName = asset.sourceDisplayName
    providerNativeID = asset.id
    title = asset.title
    creator = asset.creator
    thumbnailURL = asset.thumbnailURL
    sourcePageURL = asset.sourcePageURL
    mediaURL = asset.downloadURL
    mediaType = asset.mediaType
    fileType = asset.fileType
    width = asset.width
    height = asset.height
    duration = asset.duration
    license = asset.license
    licenseURL = asset.licenseURL
    licenseStatus = asset.licenseStatus
    rightsInfo = asset.rightsInfo
    searchKeyword = asset.searchKeyword
    self.segmentIndex = segmentIndex
    self.savedAt = savedAt
    self.downloadedAt = downloadedAt
    self.localFileName = localFileName
    self.localPath = localPath
    self.outputPresetRaw = outputPresetRaw ?? asset.originalMetadata["linkOutputPreset"]
    self.clipStartSeconds =
      clipStartSeconds ?? asset.originalMetadata["linkClipStart"].flatMap(Double.init)
    self.clipEndSeconds =
      clipEndSeconds ?? asset.originalMetadata["linkClipEnd"].flatMap(Double.init)
    self.sourceSidecarFileName = sourceSidecarFileName ?? localFileName.map(Self.sidecarName(for:))
    localMediaMissing =
      localFileName.map { _ in
        guard let localPath, !localPath.isEmpty else { return true }
        return !FileManager.default.fileExists(atPath: localPath)
      } ?? false
  }

  mutating func merge(download: DownloadRecord) {
    downloadedAt = max(downloadedAt ?? .distantPast, download.downloadedAt)
    localFileName = download.fileName
    localPath = download.localPath
    outputPresetRaw = download.outputPresetRaw ?? outputPresetRaw
    clipStartSeconds = download.clipStartSeconds ?? clipStartSeconds
    clipEndSeconds = download.clipEndSeconds ?? clipEndSeconds
    sourceSidecarFileName = Self.sidecarName(for: download.fileName)
    localMediaMissing =
      download.localPath.isEmpty
      || !FileManager.default.fileExists(atPath: download.localPath)
    if mediaURL == nil { mediaURL = download.asset?.downloadURL }
    if thumbnailURL == nil { thumbnailURL = URL(string: download.thumbnailURL ?? "") }
  }

  private static func nativeID(from stableID: String) -> String? {
    stableID.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
  }

  private static func sidecarName(for fileName: String) -> String {
    ((fileName as NSString).deletingPathExtension as String) + ".source.json"
  }
}

enum ProjectAssetInventory {
  static func items(projectID: UUID, database: PersistentDatabase) -> [ProjectAssetItem] {
    var values: [String: ProjectAssetItem] = [:]
    for saved in database.favorites where saved.projectID == projectID {
      values[saved.stableID] = ProjectAssetItem(saved: saved)
    }
    for download in database.downloads where download.projectID == projectID {
      if var existing = values[download.stableAssetID] {
        existing.merge(download: download)
        values[download.stableAssetID] = existing
      } else {
        values[download.stableAssetID] = ProjectAssetItem(download: download)
      }
    }
    return values.values.sorted {
      ($0.savedAt ?? $0.downloadedAt ?? .distantPast)
        < ($1.savedAt ?? $1.downloadedAt ?? .distantPast)
    }.enumerated().map { _, value in value }
  }
}

// MARK: - Rights audit

struct RightsAuditEntry: Identifiable, Codable, Hashable {
  var item: ProjectAssetItem
  var reviewed: Bool
  var publicDomain: Bool
  var rightsKnown: Bool
  var attributionRequired: Bool
  var originalPageUnavailable: Bool

  var id: String { item.stableID }
  var needsReview: Bool { !reviewed && (!rightsKnown || originalPageUnavailable) }
}

struct RightsAuditSummary: Codable, Hashable {
  var totalAssets: Int = 0
  var publicDomain: Int = 0
  var rightsKnown: Int = 0
  var attributionRequired: Int = 0
  var rightsUnknown: Int = 0
  var originalPageUnavailable: Int = 0
}

struct RightsAuditReport: Codable, Hashable {
  var entries: [RightsAuditEntry]
  var summary: RightsAuditSummary
}

/// The audit's display filter is intentionally separate from the source
/// metadata. It is shared by the two platform UIs so each client exposes the
/// same review workflow without changing provider-supplied rights facts.
enum RightsAuditFilter: String, CaseIterable, Codable, Hashable {
  case all
  case needsReview
  case attributionRequired
  case publicDomain
  case rightsUnknown

  func includes(_ entry: RightsAuditEntry) -> Bool {
    switch self {
    case .all: return true
    case .needsReview: return entry.needsReview
    case .attributionRequired: return entry.attributionRequired
    case .publicDomain: return entry.publicDomain
    case .rightsUnknown: return !entry.rightsKnown
    }
  }

  var localizationKey: String {
    switch self {
    case .all: return "project.filterAll"
    case .needsReview: return "project.needsReview"
    case .attributionRequired: return "license.attribution"
    case .publicDomain: return "license.publicDomain"
    case .rightsUnknown: return "project.rightsUnknown"
    }
  }
}

enum RightsAuditEngine {
  static func audit(
    items: [ProjectAssetItem], reviewed: [ProjectReviewRecord], projectID: UUID
  ) -> RightsAuditReport {
    let reviewedIDs = Set(reviewed.filter { $0.projectID == projectID }.map(\.stableAssetID))
    let entries = items.map { item in
      let rights = item.effectiveRightsInfo
      return RightsAuditEntry(
        item: item, reviewed: reviewedIDs.contains(item.stableID),
        publicDomain: rights.publicDomain,
        rightsKnown: rights.known, attributionRequired: rights.attributionRequired,
        originalPageUnavailable: !item.originalPageAvailable)
    }
    var summary = RightsAuditSummary(totalAssets: entries.count)
    for entry in entries {
      if entry.publicDomain { summary.publicDomain += 1 }
      if entry.rightsKnown { summary.rightsKnown += 1 } else { summary.rightsUnknown += 1 }
      if entry.attributionRequired { summary.attributionRequired += 1 }
      if entry.originalPageUnavailable { summary.originalPageUnavailable += 1 }
    }
    return RightsAuditReport(entries: entries, summary: summary)
  }
}

// MARK: - Safe attribution reports and credits

enum AttributionExportFormat: String, Codable, CaseIterable, Identifiable {
  case markdown = "md"
  case csv
  case json
  case html

  var id: String { rawValue }
  var fileExtension: String { rawValue }
}

struct AttributionExportOptions: Codable, Hashable {
  var includeLocalFilePaths = false
  var includeUTF8BOM = true
}

enum CreditsStyle: String, Codable, CaseIterable, Identifiable {
  case concise
  case detailed
  var id: String { rawValue }
}

struct AttributionExportHeader: Codable, Hashable {
  var projectName: String
  var createdAt: Date
  var updatedAt: Date
  var generatedAt: Date
  var applicationVersion: String
  var assetCount: Int
}

struct AttributionExportAsset: Codable, Hashable {
  var index: Int
  var title: String
  var creator: String
  var provider: String
  var providerNativeID: String
  var originalURL: String
  var mediaURL: String
  var mediaType: String
  var license: String
  var licenseURL: String
  var rightsStatus: String
  var attribution: String
  var downloadDate: Date?
  var localFileName: String
  var localFilePath: String?
  var clipStart: Double?
  var clipEnd: Double?
  var outputPreset: String
  var sourceSidecar: String
}

struct AttributionReportPayload: Codable, Hashable {
  var schemaVersion = 1
  var application = "FootageFlow"
  var exportType = "attribution-report"
  var generatedAt: Date
  var applicationVersion: String
  var project: AttributionExportHeader
  var assets: [AttributionExportAsset]
}

enum ProjectExportSanitizer {
  private static let secretWords = [
    "api", "token", "cookie", "authorization", "password", "secret", "credential", "session",
  ]

  static func safeURL(_ value: URL?) -> String {
    guard let value else { return tr("common.notProvided") }
    return LinkURLSecurity.redactedString(value) ?? tr("common.notProvided")
  }

  static func safeText(_ value: String?) -> String {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    guard let clean else { return tr("common.notProvided") }
    return redactedContent(clean)
  }

  /// Exports and portable manifests may contain user-authored text. Redact
  /// common accidental credential assignments and private paths even when the
  /// value did not originate in a provider metadata dictionary.
  static func redactedContent(_ value: String) -> String {
    var result = value
    let patterns = [
      #"(?i)\b(api[_-]?key|token|authorization|password|secret|cookie|session)\s*([:=])\s*[^\s,;&\"']+"#,
      #"(?i)\bBearer\s+[A-Za-z0-9._~+/-]{12,}"#,
      #"(?i)(?:/Users|/Volumes|/home)/[^\s\"']+"#,
      #"(?i)[A-Z]:\\Users\\[^\s\"']+"#,
    ]
    for pattern in patterns {
      guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(result.startIndex..., in: result)
      if pattern.contains("Users") || pattern.contains("Volumes") || pattern.contains("/home") {
        result = expression.stringByReplacingMatches(
          in: result, range: range, withTemplate: "[LOCAL PATH REDACTED]")
      } else if pattern.contains("Bearer") {
        result = expression.stringByReplacingMatches(
          in: result, range: range, withTemplate: "Bearer [REDACTED]")
      } else {
        result = expression.stringByReplacingMatches(
          in: result, range: range, withTemplate: "$1$2[REDACTED]")
      }
    }
    return result
  }

  static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
    metadata.reduce(into: [:]) { result, element in
      let key = element.key.lowercased().replacingOccurrences(of: "_", with: "")
      guard !secretWords.contains(where: { key.contains($0) }) else { return }
      if let url = URL(string: element.value), url.scheme != nil {
        result[element.key] = LinkURLSecurity.redactedString(url)
      } else {
        result[element.key] = redactedContent(element.value)
      }
    }
  }
}

enum AttributionExporter {
  static func payload(
    project: ProjectRecord, items: [ProjectAssetItem], now: Date = .now,
    options: AttributionExportOptions = .init()
  ) -> AttributionReportPayload {
    let assets = items.enumerated().map { index, item in
      let rights = item.effectiveRightsInfo
      return AttributionExportAsset(
        index: index + 1, title: ProjectExportSanitizer.safeText(item.title),
        creator: ProjectExportSanitizer.safeText(item.creator),
        provider: ProjectExportSanitizer.safeText(item.providerName),
        providerNativeID: ProjectExportSanitizer.safeText(item.providerNativeID),
        originalURL: ProjectExportSanitizer.safeURL(item.sourcePageURL),
        mediaURL: ProjectExportSanitizer.safeURL(item.mediaURL),
        mediaType: item.mediaType?.rawValue ?? tr("common.notProvided"),
        license: ProjectExportSanitizer.safeText(rights.statement ?? item.license),
        licenseURL: ProjectExportSanitizer.safeURL(rights.uri ?? item.licenseURL),
        rightsStatus: rightsStatus(item), attribution: attributionText(for: item),
        downloadDate: item.downloadedAt,
        localFileName: ProjectExportSanitizer.safeText(item.localFileName),
        localFilePath: options.includeLocalFilePaths ? item.localPath : nil,
        clipStart: item.clipStartSeconds, clipEnd: item.clipEndSeconds,
        outputPreset: ProjectExportSanitizer.safeText(item.outputPresetRaw),
        sourceSidecar: ProjectExportSanitizer.safeText(item.sourceSidecarFileName))
    }
    let header = AttributionExportHeader(
      projectName: ProjectExportSanitizer.safeText(project.name), createdAt: project.createdAt,
      updatedAt: project.updatedAt,
      generatedAt: now, applicationVersion: FootageFlowVersion.current, assetCount: assets.count)
    return AttributionReportPayload(
      generatedAt: now, applicationVersion: FootageFlowVersion.current, project: header,
      assets: assets)
  }

  static func data(
    format: AttributionExportFormat, project: ProjectRecord, items: [ProjectAssetItem],
    options: AttributionExportOptions = .init(), now: Date = .now
  ) throws -> Data {
    let report = payload(project: project, items: items, now: now, options: options)
    switch format {
    case .json:
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      return try encoder.encode(report)
    case .markdown:
      return Data(markdown(report).utf8)
    case .html:
      return Data(html(report).utf8)
    case .csv:
      let text = csv(report, includeLocalPaths: options.includeLocalFilePaths)
      let prefix = options.includeUTF8BOM ? "\u{FEFF}" : ""
      return Data((prefix + text).utf8)
    }
  }

  static func credits(items: [ProjectAssetItem], style: CreditsStyle) -> String {
    items.enumerated().map { index, item in
      let rights = item.effectiveRightsInfo
      let unknown = rights.known ? "" : " — \(tr("project.rightsUnknownVerify"))"
      switch style {
      case .concise:
        return
          "\(index + 1). \(ProjectExportSanitizer.safeText(item.title)) — \(ProjectExportSanitizer.safeText(item.creator)) — \(item.providerName)\(unknown)"
      case .detailed:
        return [
          "\(index + 1). \(ProjectExportSanitizer.safeText(item.title))",
          "\(tr("attribution.creator")): \(ProjectExportSanitizer.safeText(item.creator))",
          "\(tr("attribution.source")): \(item.providerName)",
          "\(tr("attribution.rights")): \(ProjectExportSanitizer.safeText(rights.statement ?? item.license))",
          "\(tr("attribution.originalURL")): \(ProjectExportSanitizer.safeURL(item.sourcePageURL))",
          "\(tr("project.attribution")): \(attributionText(for: item))\(unknown)",
        ].joined(separator: "\n")
      }
    }.joined(separator: style == .concise ? "\n" : "\n\n")
  }

  static func attributionText(for item: ProjectAssetItem) -> String {
    let rights = item.effectiveRightsInfo
    let creator = ProjectExportSanitizer.safeText(item.creator)
    let license = ProjectExportSanitizer.safeText(rights.statement ?? item.license)
    return
      "\(creator) — \(ProjectExportSanitizer.safeText(item.title)) — \(item.providerName) — \(license)"
  }

  static func rightsStatus(_ item: ProjectAssetItem) -> String {
    let rights = item.effectiveRightsInfo
    if !item.originalPageAvailable { return tr("project.originalPageUnavailable") }
    if !rights.known { return tr("project.rightsUnknown") }
    if rights.publicDomain { return tr("license.publicDomain") }
    if rights.attributionRequired { return tr("license.attribution") }
    return tr("project.rightsKnown")
  }

  private static func markdown(_ report: AttributionReportPayload) -> String {
    var lines = [
      "# FootageFlow Attribution Report", "",
      "- Project: \(markdownText(report.project.projectName))",
      "- Generated: \(iso(report.generatedAt))",
      "- Assets: \(report.assets.count)",
    ]
    for asset in report.assets {
      lines += [
        "", "## \(asset.index). \(markdownText(asset.title))", "",
        "- Creator: \(markdownText(asset.creator))",
        "- Provider: \(markdownText(asset.provider))",
        "- Original source: \(markdownURL(asset.originalURL))",
        "- License: \(markdownText(asset.license))",
        "- License URL: \(markdownURL(asset.licenseURL))",
        "- Rights status: \(markdownText(asset.rightsStatus))",
        "- Attribution: \(markdownText(asset.attribution))",
        "- Local file: \(markdownText(asset.localFileName))",
      ]
      if asset.rightsStatus == tr("project.rightsUnknown")
        || asset.rightsStatus == tr("project.originalPageUnavailable")
      {
        lines.append(
          "- Warning: Rights / license unknown. Verify the original source before reuse.")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func csv(_ report: AttributionReportPayload, includeLocalPaths: Bool) -> String {
    var headers = [
      "Index", "Title", "Creator", "Provider", "Provider Native ID", "Original URL", "Media URL",
      "Media Type", "License", "License URL", "Rights Status", "Attribution", "Download Date",
      "Local File Name", "Clip Start", "Clip End", "Output Preset", "Source Sidecar",
    ]
    if includeLocalPaths { headers.append("Local File Path") }
    var lines = [headers.map(csvField).joined(separator: ",")]
    for asset in report.assets {
      var fields: [String] = []
      fields.append(String(asset.index))
      fields.append(asset.title)
      fields.append(asset.creator)
      fields.append(asset.provider)
      fields.append(asset.providerNativeID)
      fields.append(asset.originalURL)
      fields.append(asset.mediaURL)
      fields.append(asset.mediaType)
      fields.append(asset.license)
      fields.append(asset.licenseURL)
      fields.append(asset.rightsStatus)
      fields.append(asset.attribution)
      fields.append(asset.downloadDate.map { iso($0) } ?? tr("common.notProvided"))
      fields.append(asset.localFileName)
      fields.append(asset.clipStart.map { String($0) } ?? tr("common.notProvided"))
      fields.append(asset.clipEnd.map { String($0) } ?? tr("common.notProvided"))
      fields.append(asset.outputPreset)
      fields.append(asset.sourceSidecar)
      if includeLocalPaths { fields.append(asset.localFilePath ?? tr("common.notProvided")) }
      lines.append(fields.map(csvField).joined(separator: ","))
    }
    return lines.joined(separator: "\r\n") + "\r\n"
  }

  private static func html(_ report: AttributionReportPayload) -> String {
    let rows = report.assets.map { asset in
      let warning =
        asset.rightsStatus == tr("project.rightsUnknown")
        || asset.rightsStatus == tr("project.originalPageUnavailable")
      return """
          <article class=\"asset\">
            <h2>\(asset.index). \(htmlText(asset.title))</h2>
            <dl>
              <dt>Creator</dt><dd>\(htmlText(asset.creator))</dd>
              <dt>Provider</dt><dd>\(htmlText(asset.provider))</dd>
              <dt>Original source</dt><dd>\(htmlLink(asset.originalURL))</dd>
              <dt>License</dt><dd>\(htmlText(asset.license))</dd>
              <dt>License URL</dt><dd>\(htmlLink(asset.licenseURL))</dd>
              <dt>Rights status</dt><dd>\(htmlText(asset.rightsStatus))</dd>
              <dt>Attribution</dt><dd>\(htmlText(asset.attribution))</dd>
              <dt>Local file</dt><dd>\(htmlText(asset.localFileName))</dd>
            </dl>
            \(warning ? "<p class=\"warning\">Rights / license unknown. Verify the original source before reuse.</p>" : "")
          </article>
        """
    }.joined(separator: "\n")
    return """
      <!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>FootageFlow Attribution Report</title>
      <style>body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;max-width:980px;margin:36px auto;padding:0 24px;color:#172033}header,.asset{border:1px solid #dce3ed;border-radius:12px;padding:20px;margin:16px 0}.asset{break-inside:avoid}h1,h2{margin-top:0}dl{display:grid;grid-template-columns:150px 1fr;gap:7px 14px}dt{font-weight:600}.warning{color:#9f2d20;font-weight:600}a{color:#0b63ce;overflow-wrap:anywhere}@media print{body{max-width:none;margin:0}.asset{border-color:#bbb}}</style>
      </head><body><header><h1>FootageFlow Attribution Report</h1><p><strong>Project:</strong> \(htmlText(report.project.projectName))<br><strong>Generated:</strong> \(htmlText(iso(report.generatedAt)))<br><strong>Assets:</strong> \(report.assets.count)</p></header>\(rows)</body></html>
      """
  }

  private static func csvField(_ value: String) -> String {
    // Excel and other spreadsheet programs may interpret leading formula
    // characters even in an imported quoted cell. Prefix them defensively;
    // this is presentation-only and does not alter stored project metadata.
    let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'\(value)" : value
    return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
  private static func markdownText(_ value: String) -> String {
    value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
  }
  private static func markdownURL(_ value: String) -> String {
    guard value.hasPrefix("https://") || value.hasPrefix("http://") else {
      return markdownText(value)
    }
    return "[\(markdownText(value))](\(value.replacingOccurrences(of: ")", with: "%29")))"
  }
  private static func htmlText(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
  private static func htmlLink(_ value: String) -> String {
    guard value.hasPrefix("https://") || value.hasPrefix("http://") else { return htmlText(value) }
    let escaped = htmlText(value)
    return "<a href=\"\(escaped)\" rel=\"noreferrer\">\(escaped)</a>"
  }
  private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

// MARK: - Portable Project Backup v1

struct PortableProjectInfo: Codable, Hashable {
  var name: String
  var createdAt: Date
  var updatedAt: Date
  var script: String
}

struct PortableSavedAssetRecord: Codable, Hashable {
  var stableID: String
  var providerRaw: String
  var title: String
  var thumbnailURL: URL?
  var sourcePageURL: URL
  var licenseName: String?
  var licenseStatusRaw: String
  var segmentIndex: Int?
  var savedAt: Date
  var asset: MediaAsset
}

struct PortableDownloadRecord: Codable, Hashable {
  var stableAssetID: String
  var providerRaw: String
  var sourceName: String?
  var title: String
  var fileName: String
  var relativeFileReference: String?
  var thumbnailURL: String?
  var sourcePageURL: String
  var downloadedAt: Date
  var outputPresetRaw: String?
  var clipStartSeconds: Double?
  var clipEndSeconds: Double?
  var clipDurationSeconds: Double?
  var asset: MediaAsset?
}

struct PortableProjectManifest: Codable, Hashable {
  var schemaVersion = 1
  var application = "FootageFlow"
  var applicationVersion: String
  var createdAt: Date
  var project: PortableProjectInfo
  var segments: [ScriptSegmentRecord]
  var favorites: [PortableSavedAssetRecord]
  var searchHistory: [SearchHistoryRecord]
  var downloads: [PortableDownloadRecord]
  var reviewedStableAssetIDs: [String]
  var duplicateDecisions: [PortableDuplicateDecision]
}

struct PortableDuplicateDecision: Codable, Hashable {
  var pairKey: String
  var decision: DuplicateDecision
  var updatedAt: Date
}

struct ImportedProjectPayload {
  var project: ProjectRecord
  var segments: [ScriptSegmentRecord]
  var favorites: [SavedAssetRecord]
  var history: [SearchHistoryRecord]
  var downloads: [DownloadRecord]
  var reviewedAssets: [ProjectReviewRecord]
  var duplicateDecisions: [DuplicateDecisionRecord]
}

enum PortableProjectError: LocalizedError {
  case unreadable
  case unsupportedSchema
  case invalidManifest

  var errorDescription: String? {
    switch self {
    case .unreadable: return tr("project.importUnreadable")
    case .unsupportedSchema: return tr("project.importUnsupported")
    case .invalidManifest: return tr("project.importInvalid")
    }
  }
}

enum PortableProjectCodec {
  static func manifest(
    project: ProjectRecord, database: PersistentDatabase, now: Date = .now
  ) -> PortableProjectManifest {
    let favorites = database.favorites.filter { $0.projectID == project.id }.map { saved in
      let asset = sanitized(saved.asset)
      return PortableSavedAssetRecord(
        stableID: saved.stableID, providerRaw: saved.providerRaw,
        title: ProjectExportSanitizer.safeText(saved.title),
        thumbnailURL: redactedURL(saved.thumbnailURL),
        sourcePageURL: redactedURL(saved.sourcePageURL) ?? asset.sourcePageURL,
        licenseName: saved.licenseName, licenseStatusRaw: saved.licenseStatusRaw,
        segmentIndex: saved.segmentIndex, savedAt: saved.savedAt,
        asset: asset)
    }
    let downloads = database.downloads.filter { $0.projectID == project.id }.map { value in
      PortableDownloadRecord(
        stableAssetID: value.stableAssetID, providerRaw: value.providerRaw,
        sourceName: value.sourceName.map(ProjectExportSanitizer.redactedContent),
        title: ProjectExportSanitizer.safeText(value.title), fileName: value.fileName,
        relativeFileReference: safeRelativeFile(value.fileName),
        thumbnailURL: redactedURL(value.thumbnailURL)?.absoluteString,
        sourcePageURL: ProjectExportSanitizer.safeURL(URL(string: value.sourcePageURL)),
        downloadedAt: value.downloadedAt, outputPresetRaw: value.outputPresetRaw,
        clipStartSeconds: value.clipStartSeconds, clipEndSeconds: value.clipEndSeconds,
        clipDurationSeconds: value.clipDurationSeconds, asset: value.asset.map(sanitized))
    }
    var history = database.history.filter { $0.projectID == project.id }
    // Project ids belong to the importing device and are remapped during import.
    for index in history.indices {
      history[index].projectID = nil
      history[index].originalQuery = ProjectExportSanitizer.redactedContent(
        history[index].originalQuery)
      history[index].keywords = history[index].keywords.map(ProjectExportSanitizer.redactedContent)
      if var details = history[index].keywordDetails {
        for detailIndex in details.indices {
          details[detailIndex].text = ProjectExportSanitizer.redactedContent(
            details[detailIndex].text)
        }
        history[index].keywordDetails = details
      }
    }
    var segments = database.segments.filter { $0.projectID == project.id }
    for index in segments.indices {
      segments[index].projectID = nil
      segments[index].text = ProjectExportSanitizer.redactedContent(segments[index].text)
      for keywordIndex in segments[index].keywords.indices {
        segments[index].keywords[keywordIndex].text = ProjectExportSanitizer.redactedContent(
          segments[index].keywords[keywordIndex].text)
      }
    }
    return PortableProjectManifest(
      applicationVersion: FootageFlowVersion.current, createdAt: now,
      project: PortableProjectInfo(
        name: ProjectExportSanitizer.safeText(project.name), createdAt: project.createdAt,
        updatedAt: project.updatedAt,
        script: ProjectExportSanitizer.redactedContent(project.script)),
      segments: segments, favorites: favorites, searchHistory: history, downloads: downloads,
      reviewedStableAssetIDs: database.reviewedAssets?.filter { $0.projectID == project.id }.map(
        \.stableAssetID) ?? [],
      duplicateDecisions: database.duplicateDecisions?.filter { $0.projectID == project.id }.map {
        PortableDuplicateDecision(
          pairKey: $0.pairKey, decision: $0.decision, updatedAt: $0.updatedAt)
      } ?? [])
  }

  static func data(_ manifest: PortableProjectManifest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(manifest)
  }

  static func decode(_ data: Data) throws -> PortableProjectManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let manifest = try? decoder.decode(PortableProjectManifest.self, from: data) else {
      throw PortableProjectError.unreadable
    }
    try validate(manifest)
    return manifest
  }

  static func validate(_ manifest: PortableProjectManifest) throws {
    guard manifest.application == "FootageFlow", manifest.schemaVersion == 1 else {
      throw PortableProjectError.unsupportedSchema
    }
    guard !manifest.project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PortableProjectError.invalidManifest
    }
    let allAssets = manifest.favorites.map(\.asset) + manifest.downloads.compactMap(\.asset)
    guard allAssets.allSatisfy(isSafe) else { throw PortableProjectError.invalidManifest }
    guard
      manifest.downloads.allSatisfy({ value in
        guard let reference = value.relativeFileReference else { return true }
        return !reference.contains("..") && !reference.contains("/") && !reference.contains("\\")
      })
    else {
      throw PortableProjectError.invalidManifest
    }
  }

  static func importedPayload(
    from manifest: PortableProjectManifest, existingProjectNames: Set<String>, now: Date = .now
  ) throws -> ImportedProjectPayload {
    try validate(manifest)
    let normalized = manifest.project.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let name =
      existingProjectNames.contains(normalized.localizedLowercase)
      ? "\(normalized) (Imported)" : normalized
    let project = ProjectRecord(
      id: UUID(), name: name, createdAt: now, updatedAt: now, script: manifest.project.script)
    let segments = manifest.segments.map { source -> ScriptSegmentRecord in
      ScriptSegmentRecord(
        id: UUID(), projectID: project.id, index: source.index, text: source.text,
        keywords: source.keywords, createdAt: source.createdAt)
    }
    let favorites = manifest.favorites.map { source -> SavedAssetRecord in
      SavedAssetRecord(
        stableID: source.stableID, providerRaw: source.providerRaw, title: source.title,
        thumbnailURL: source.thumbnailURL?.absoluteString,
        sourcePageURL: source.sourcePageURL.absoluteString,
        licenseName: source.licenseName, licenseStatusRaw: source.licenseStatusRaw,
        projectID: project.id, segmentIndex: source.segmentIndex, savedAt: source.savedAt,
        asset: source.asset)
    }
    var history = manifest.searchHistory
    for index in history.indices {
      history[index].id = UUID()
      history[index].projectID = project.id
    }
    let downloads = manifest.downloads.map { source -> DownloadRecord in
      DownloadRecord(
        stableAssetID: source.stableAssetID, providerRaw: source.providerRaw,
        sourceName: source.sourceName,
        title: source.title, fileName: source.fileName,
        // A portable manifest deliberately does not claim that a relative
        // filename exists on the importing machine. Metadata stays available
        // and the UI correctly reports missing local media.
        localPath: "", thumbnailURL: source.thumbnailURL,
        sourcePageURL: source.sourcePageURL, projectID: project.id,
        downloadedAt: source.downloadedAt,
        outputPresetRaw: source.outputPresetRaw, clipStartSeconds: source.clipStartSeconds,
        clipEndSeconds: source.clipEndSeconds, clipDurationSeconds: source.clipDurationSeconds,
        asset: source.asset)
    }
    return ImportedProjectPayload(
      project: project, segments: segments, favorites: favorites, history: history,
      downloads: downloads,
      reviewedAssets: manifest.reviewedStableAssetIDs.map {
        ProjectReviewRecord(projectID: project.id, stableAssetID: $0, reviewedAt: now)
      },
      duplicateDecisions: manifest.duplicateDecisions.map {
        DuplicateDecisionRecord(
          projectID: project.id, pairKey: $0.pairKey, decision: $0.decision,
          updatedAt: $0.updatedAt)
      })
  }

  private static func safeRelativeFile(_ name: String) -> String? {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !clean.contains("/"), !clean.contains("\\") else { return nil }
    return clean
  }

  private static func redactedURL(_ raw: String?) -> URL? {
    guard let raw, let url = URL(string: raw), let value = LinkURLSecurity.redactedString(url)
    else { return nil }
    return URL(string: value)
  }

  private static func sanitized(_ asset: MediaAsset) -> MediaAsset {
    var value = asset
    value.title = ProjectExportSanitizer.redactedContent(value.title)
    value.description = value.description.map(ProjectExportSanitizer.redactedContent)
    value.creator = value.creator.map(ProjectExportSanitizer.redactedContent)
    value.license = value.license.map(ProjectExportSanitizer.redactedContent)
    value.searchKeyword = ProjectExportSanitizer.redactedContent(value.searchKeyword)
    value.originalMetadata = ProjectExportSanitizer.sanitizedMetadata(value.originalMetadata)
    if let string = LinkURLSecurity.redactedString(value.sourcePageURL),
      let url = URL(string: string)
    {
      value.sourcePageURL = url
    }
    if let url = value.downloadURL, let string = LinkURLSecurity.redactedString(url) {
      value.downloadURL = URL(string: string)
    }
    return value
  }

  private static func isSafe(_ asset: MediaAsset) -> Bool {
    !asset.originalMetadata.keys.contains { key in
      let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
      return [
        "apikey", "token", "cookie", "authorization", "password", "secret", "credential", "session",
      ].contains {
        normalized.contains($0)
      }
    }
  }
}

// MARK: - Duplicate detection and lazy SHA-256

enum DuplicateReason: String, Codable, CaseIterable, Hashable {
  case sameProviderID
  case sameOriginalURL
  case sameDownloadURL
  case sameSHA256
  case possibleMetadata

  var isExact: Bool { self == .sameProviderID || self == .sameOriginalURL || self == .sameSHA256 }
}

struct DuplicateGroup: Identifiable, Codable, Hashable {
  var reason: DuplicateReason
  var items: [ProjectAssetItem]
  var key: String
  /// A UI-ready, localized reason produced by the Shared Core Host for
  /// Windows. The raw reason remains the stable machine-readable value.
  var displayReason: String?
  var id: String { "\(reason.rawValue):\(key)" }
  var decisionKey: String { items.map(\.stableID).sorted().joined(separator: "|") }
}

enum URLCanonicalizer {
  private static let trackingPrefixes = ["utm_", "ref", "source", "fbclid", "gclid"]

  static func canonical(_ url: URL?) -> String? {
    guard var components = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
      let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = components.host?.lowercased(), !host.isEmpty, components.user == nil,
      components.password == nil
    else { return nil }
    components.scheme = scheme
    components.host = host
    components.fragment = nil
    if components.path.count > 1, components.path.hasSuffix("/") {
      components.path.removeLast()
    }
    components.percentEncodedQueryItems = components.percentEncodedQueryItems?.filter { item in
      let name = item.name.lowercased()
      return !trackingPrefixes.contains { prefix in name == prefix || name.hasPrefix(prefix) }
    }.sorted { $0.name < $1.name }
    return components.string
  }
}

enum DuplicateDetectionEngine {
  static func displayReason(_ reason: DuplicateReason) -> String {
    switch reason {
    case .sameProviderID: return tr("project.duplicateSameProviderID")
    case .sameOriginalURL: return tr("project.duplicateSameOriginalURL")
    case .sameDownloadURL: return tr("project.duplicateSameDownloadURL")
    case .sameSHA256: return tr("project.duplicateSameSHA256")
    case .possibleMetadata: return tr("project.duplicatePossibleMetadata")
    }
  }

  static func find(items: [ProjectAssetItem], hashes: [String: String] = [:]) -> [DuplicateGroup] {
    var groups: [DuplicateGroup] = []
    func append(_ reason: DuplicateReason, key: String?, filter: (ProjectAssetItem) -> Bool) {
      guard let key, !key.isEmpty else { return }
      let values = items.filter(filter)
      guard values.count > 1 else { return }
      groups.append(
        DuplicateGroup(
          reason: reason, items: values, key: key, displayReason: displayReason(reason)))
    }
    let providerKeys = Dictionary(grouping: items) {
      "\($0.providerRaw)|\($0.providerNativeID ?? $0.stableID)"
    }
    for (key, values) in providerKeys where values.count > 1 {
      groups.append(
        DuplicateGroup(
          reason: .sameProviderID, items: values, key: key,
          displayReason: displayReason(.sameProviderID)))
    }
    let originalKeys = Dictionary(grouping: items) {
      URLCanonicalizer.canonical($0.sourcePageURL) ?? ""
    }
    for (key, values) in originalKeys where !key.isEmpty && values.count > 1 {
      groups.append(
        DuplicateGroup(
          reason: .sameOriginalURL, items: values, key: key,
          displayReason: displayReason(.sameOriginalURL)))
    }
    let downloadKeys = Dictionary(grouping: items) { URLCanonicalizer.canonical($0.mediaURL) ?? "" }
    for (key, values) in downloadKeys where !key.isEmpty && values.count > 1 {
      groups.append(
        DuplicateGroup(
          reason: .sameDownloadURL, items: values, key: key,
          displayReason: displayReason(.sameDownloadURL)))
    }
    let hashKeys = Dictionary(grouping: items) { hashes[$0.stableID] ?? "" }
    for (key, values) in hashKeys where !key.isEmpty && values.count > 1 {
      groups.append(
        DuplicateGroup(
          reason: .sameSHA256, items: values, key: key,
          displayReason: displayReason(.sameSHA256)))
    }
    let metadataKeys = Dictionary(grouping: items) { item in
      let title = item.title.folding(
        options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let creator =
        item.creator?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        ?? ""
      let duration = item.duration.map { String(Int($0.rounded())) } ?? ""
      let dimensions = "\(item.width ?? 0)x\(item.height ?? 0)"
      return "\(title)|\(creator)|\(duration)|\(dimensions)"
    }
    for (key, values) in metadataKeys where values.count > 1 && !key.hasPrefix("||") {
      groups.append(
        DuplicateGroup(
          reason: .possibleMetadata, items: values, key: key,
          displayReason: displayReason(.possibleMetadata)))
    }
    return groups.sorted {
      if $0.reason.isExact != $1.reason.isExact { return $0.reason.isExact }
      return $0.items.count > $1.items.count
    }
  }
}

enum FileHashService {
  static func sha256(of fileURL: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var hasher = SHA256Hasher()
    while true {
      try Task.checkCancellation()
      let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
      if chunk.isEmpty { break }
      hasher.update(chunk)
    }
    return hasher.finalize()
  }

  static func cachedHash(for item: ProjectAssetItem, cache: [FileHashCacheRecord]) -> String? {
    guard let path = item.localPath, !path.isEmpty,
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let size = (attributes[.size] as? NSNumber)?.int64Value,
      let modified = attributes[.modificationDate] as? Date
    else { return nil }
    return cache.first {
      $0.localPath == path && $0.fileSize == size
        && abs($0.modificationDate.timeIntervalSince(modified)) < 1
    }?.sha256
  }
}

/// Small streaming SHA-256 implementation keeps hashing in the Shared Core
/// without a platform-only crypto dependency.
private struct SHA256Hasher {
  private static let constants: [UInt32] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4,
    0xab1c_5ed5,
    0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7,
    0xc19b_f174,
    0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc,
    0x76f9_88da,
    0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351,
    0x1429_2967,
    0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e,
    0x9272_2c85,
    0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585,
    0x106a_a070,
    0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f,
    0x682e_6ff3,
    0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7,
    0xc671_78f2,
  ]
  private var state: [UInt32] = [
    0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab,
    0x5be0_cd19,
  ]
  private var buffer = Data()
  private var byteCount: UInt64 = 0

  mutating func update(_ data: Data) {
    byteCount &+= UInt64(data.count)
    buffer.append(data)
    while buffer.count >= 64 {
      process(buffer.prefix(64))
      buffer.removeFirst(64)
    }
  }

  mutating func finalize() -> String {
    let bitLength = byteCount &* 8
    buffer.append(0x80)
    while buffer.count % 64 != 56 { buffer.append(0) }
    var bigEndianLength = bitLength.bigEndian
    withUnsafeBytes(of: &bigEndianLength) { buffer.append(contentsOf: $0) }
    while buffer.count >= 64 {
      process(buffer.prefix(64))
      buffer.removeFirst(64)
    }
    return state.map { String(format: "%08x", $0) }.joined()
  }

  private mutating func process(_ block: Data.SubSequence) {
    var words = Array(repeating: UInt32(0), count: 64)
    for index in 0..<16 {
      let offset = block.startIndex + index * 4
      words[index] =
        (UInt32(block[offset]) << 24) | (UInt32(block[offset + 1]) << 16)
        | (UInt32(block[offset + 2]) << 8) | UInt32(block[offset + 3])
    }
    for index in 16..<64 {
      let a =
        rotate(words[index - 15], 7) ^ rotate(words[index - 15], 18) ^ (words[index - 15] >> 3)
      let b = rotate(words[index - 2], 17) ^ rotate(words[index - 2], 19) ^ (words[index - 2] >> 10)
      words[index] = words[index - 16] &+ a &+ words[index - 7] &+ b
    }
    var a = state[0]
    var b = state[1]
    var c = state[2]
    var d = state[3]
    var e = state[4]
    var f = state[5]
    var g = state[6]
    var h = state[7]
    for index in 0..<64 {
      let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
      let choice = (e & f) ^ ((~e) & g)
      let temp1 = h &+ s1 &+ choice &+ Self.constants[index] &+ words[index]
      let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temp2 = s0 &+ majority
      h = g
      g = f
      f = e
      e = d &+ temp1
      d = c
      c = b
      b = a
      a = temp1 &+ temp2
    }
    state[0] &+= a
    state[1] &+= b
    state[2] &+= c
    state[3] &+= d
    state[4] &+= e
    state[5] &+= f
    state[6] &+= g
    state[7] &+= h
  }

  private func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
  }
}

// MARK: - Contact sheet plan

struct ContactSheetItem: Identifiable, Codable, Hashable {
  var index: Int
  var title: String
  var provider: String
  var rightsStatus: String
  var thumbnailURL: URL?
  var localPath: String?
  var duration: Double?
  var id: String { "\(index)-\(title)" }
}

struct ContactSheetPlan: Codable, Hashable {
  var projectName: String
  var columns: Int
  var includeRights: Bool
  var items: [ContactSheetItem]
}

enum ContactSheetPlanner {
  static func plan(
    project: ProjectRecord, items: [ProjectAssetItem], columns: Int = 4, includeRights: Bool = true
  ) -> ContactSheetPlan {
    ContactSheetPlan(
      projectName: project.name, columns: min(5, max(3, columns)), includeRights: includeRights,
      items: items.enumerated().map { index, item in
        ContactSheetItem(
          index: index + 1, title: item.title, provider: item.providerName,
          rightsStatus: AttributionExporter.rightsStatus(item), thumbnailURL: item.thumbnailURL,
          localPath: item.localPath, duration: item.duration)
      })
  }
}
