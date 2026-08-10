import Foundation

enum LinkDownloadQuality: String, Codable, CaseIterable, Identifiable, Sendable {
  case best, p1080, p720, p480, audioOnly
  var id: String { rawValue }
  var label: String { tr("link.quality.\(rawValue)") }
  var maximumHeight: Int? {
    switch self {
    case .best, .audioOnly: nil
    case .p1080: 1080
    case .p720: 720
    case .p480: 480
    }
  }

  var formatSelector: String {
    switch self {
    case .best: "best[acodec!=none][vcodec!=none]/best"
    case .p1080: "best[height<=1080][acodec!=none][vcodec!=none]/best[height<=1080]"
    case .p720: "best[height<=720][acodec!=none][vcodec!=none]/best[height<=720]"
    case .p480: "best[height<=480][acodec!=none][vcodec!=none]/best[height<=480]"
    case .audioOnly: "bestaudio[acodec!=none]/best"
    }
  }
}

struct LinkMediaFormat: Identifiable, Codable, Hashable, Sendable {
  let formatID: String
  let fileExtension: String?
  let width: Int?
  let height: Int?
  let fps: Double?
  let fileSize: Int64?
  let hasVideo: Bool
  let hasAudio: Bool

  var id: String { formatID }
  var resolutionText: String {
    if let width, let height { return "\(width)×\(height)" }
    if hasAudio && !hasVideo { return tr("link.audioOnly") }
    return tr("common.unknown")
  }
}

struct LinkMediaAnalysis: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let originalURL: URL
  let sourceName: String
  let title: String
  let creator: String?
  let thumbnailURL: URL?
  let duration: Double?
  let formats: [LinkMediaFormat]
  let subtitleLanguages: [String]

  var availableQualities: [LinkDownloadQuality] {
    var values: [LinkDownloadQuality] = [.best]
    let progressiveHeights = formats.filter { $0.hasVideo && $0.hasAudio }.compactMap(\.height)
    if progressiveHeights.contains(where: { $0 >= 1080 }) { values.append(.p1080) }
    if progressiveHeights.contains(where: { $0 >= 720 }) { values.append(.p720) }
    if progressiveHeights.contains(where: { $0 >= 480 }) { values.append(.p480) }
    if formats.contains(where: { $0.hasAudio }) { values.append(.audioOnly) }
    return values
  }

  func mediaAsset(
    quality: LinkDownloadQuality, downloadSubtitles: Bool, subtitleLanguage: String?
  ) -> MediaAsset {
    let subtitleIdentity =
      downloadSubtitles ? ":subs:\(subtitleLanguage?.nilIfEmpty ?? "all")" : ""
    var metadata = [
      "sourceName": sourceName,
      "linkFormatSelector": quality.formatSelector,
      "linkQuality": quality.rawValue,
      "linkDownloadSubtitles": downloadSubtitles ? "true" : "false",
      "linkSubtitleLanguages": subtitleLanguage ?? "",
      "linkAudioOnly": quality == .audioOnly ? "true" : "false",
    ]
    metadata["linkDownloader"] = "true"
    return MediaAsset(
      id: "\(id):\(quality.rawValue)\(subtitleIdentity)", provider: .linkDownloader, title: title,
      description: nil,
      thumbnailURL: thumbnailURL, previewURL: nil, downloadURL: originalURL,
      sourcePageURL: originalURL, creator: creator, license: nil, licenseURL: nil,
      licenseStatus: .unknown, width: nil, height: quality.maximumHeight, duration: duration,
      fileType: quality == .audioOnly ? "audio" : "video",
      mediaType: quality == .audioOnly ? .audio : .video,
      publishedDate: nil, downloadable: true, originalMetadata: metadata,
      searchKeyword: originalURL.absoluteString, relevanceScore: 1, downloadStrategy: .ytDLP,
      rightsInfo: RightsInfo(statement: nil, source: sourceName, known: false),
      downloadAvailability: .conditional)
  }
}

struct YTDLPDownloadOptions: Sendable, Equatable {
  var formatSelector: String
  var downloadSubtitles: Bool
  var subtitleLanguages: String?

  static let `default` = YTDLPDownloadOptions(
    formatSelector: LinkDownloadQuality.p720.formatSelector,
    downloadSubtitles: false, subtitleLanguages: nil)

  init(formatSelector: String, downloadSubtitles: Bool, subtitleLanguages: String?) {
    self.formatSelector = formatSelector
    self.downloadSubtitles = downloadSubtitles
    self.subtitleLanguages = subtitleLanguages
  }

  init(asset: MediaAsset) {
    formatSelector =
      asset.originalMetadata["linkFormatSelector"]
      ?? LinkDownloadQuality.p720.formatSelector
    downloadSubtitles = asset.originalMetadata["linkDownloadSubtitles"] == "true"
    subtitleLanguages = asset.originalMetadata["linkSubtitleLanguages"]?.nilIfEmpty
  }
}

struct YTDLPDownloadUpdate: Sendable {
  let fraction: Double
  let bytesPerSecond: Double
}

enum LinkURLParser {
  static func urls(from text: String) -> [URL] {
    var seen = Set<String>()
    return text.split(whereSeparator: \.isNewline).compactMap { line in
      let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let components = URLComponents(string: clean), LinkURLSecurity.isSafe(components),
        let url = components.url, seen.insert(url.absoluteString).inserted
      else { return nil }
      return url
    }
  }
}

enum LinkURLSecurity {
  private static let sensitiveQueryNames: Set<String> = [
    "authorization", "cookie", "password", "token", "accesstoken", "apikey", "secret",
    "clientsecret", "session", "sessionid",
  ]

  static func isSafe(_ components: URLComponents) -> Bool {
    guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.user == nil, components.password == nil, let host = components.host?.lowercased(),
      !host.isEmpty, !isLocalOrPrivateHost(host),
      !(components.queryItems ?? []).contains(where: { isSensitiveName($0.name) })
    else { return false }
    return true
  }

  static func isSafe(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return false
    }
    return isSafe(components)
  }

  static func redactedString(_ url: URL?) -> String? {
    guard let url,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url?.absoluteString }
    components.user = components.user == nil ? nil : "[REDACTED]"
    components.password = components.password == nil ? nil : "[REDACTED]"
    components.queryItems = components.queryItems?.map { item in
      URLQueryItem(
        name: item.name, value: isSensitiveName(item.name) ? "[REDACTED]" : item.value)
    }
    return components.string ?? url.absoluteString
  }

  private static func isSensitiveName(_ value: String) -> Bool {
    let normalized = value.lowercased().filter(\.isLetter)
    return sensitiveQueryNames.contains(normalized)
  }

  private static func isLocalOrPrivateHost(_ value: String) -> Bool {
    let host = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
      || host == "::1" || host == "0:0:0:0:0:0:0:1" || host == "0.0.0.0"
    {
      return true
    }
    if host.contains(":") {
      let prefix = host.lowercased()
      return prefix.hasPrefix("fc") || prefix.hasPrefix("fd") || prefix.hasPrefix("fe8")
        || prefix.hasPrefix("fe9") || prefix.hasPrefix("fea") || prefix.hasPrefix("feb")
    }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
    switch (parts[0], parts[1]) {
    case (0, _), (10, _), (127, _), (169, 254), (192, 168): return true
    case (100, 64...127), (172, 16...31): return true
    case (224...255, _): return true
    default: return false
    }
  }
}
