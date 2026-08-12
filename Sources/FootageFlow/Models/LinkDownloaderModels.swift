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
    case .best: "bestvideo+bestaudio/best"
    case .p1080: "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    case .p720: "bestvideo[height<=720]+bestaudio/best[height<=720]"
    case .p480: "bestvideo[height<=480]+bestaudio/best[height<=480]"
    case .audioOnly: "bestaudio[acodec!=none]/best"
    }
  }
}

enum LinkDownloadScope: String, Codable, CaseIterable, Identifiable, Sendable {
  case full, clip
  var id: String { rawValue }
  var label: String { tr("link.scope.\(rawValue)") }
}

enum EditingOutputPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case original
  case editingCompatibleMP4
  case audioOnly

  var id: String { rawValue }
  var label: String { tr("link.output.\(rawValue)") }
  var requiresFFmpeg: Bool { self != .original }
}

enum ClipRangeError: Error, Equatable, Sendable {
  case invalidFormat
  case invalidRange
  case beyondDuration
  case unknownDuration

  var localizationKey: String {
    switch self {
    case .invalidFormat: "link.clip.invalidFormat"
    case .invalidRange: "link.clip.invalidRange"
    case .beyondDuration: "link.clip.beyondDuration"
    case .unknownDuration: "link.clip.unknownDuration"
    }
  }
}

struct ClipTimeRange: Codable, Hashable, Sendable {
  let start: Double
  let end: Double

  var duration: Double { end - start }

  init(start: Double, end: Double, mediaDuration: Double?) throws {
    guard start.isFinite, end.isFinite, start >= 0, end > start, end - start >= 0.5 else {
      throw ClipRangeError.invalidRange
    }
    guard let mediaDuration, mediaDuration.isFinite, mediaDuration > 0 else {
      throw ClipRangeError.unknownDuration
    }
    guard end <= mediaDuration + 0.05 else { throw ClipRangeError.beyondDuration }
    self.start = start
    self.end = end
  }

  static func parse(start: String, end: String, mediaDuration: Double?) throws -> ClipTimeRange {
    guard let startValue = TimecodeParser.seconds(start), let endValue = TimecodeParser.seconds(end)
    else { throw ClipRangeError.invalidFormat }
    return try ClipTimeRange(start: startValue, end: endValue, mediaDuration: mediaDuration)
  }

  var sectionArgument: String {
    "*\(TimecodeParser.decimalSeconds(start))-\(TimecodeParser.decimalSeconds(end))"
  }
}

enum TimecodeParser {
  static func seconds(_ raw: String) -> Double? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    let fields = value.split(separator: ":", omittingEmptySubsequences: false)
    guard (1...3).contains(fields.count), fields.allSatisfy({ Double($0) != nil }) else {
      return nil
    }
    let values = fields.compactMap { Double($0) }
    guard values.count == fields.count, values.allSatisfy({ $0 >= 0 && $0.isFinite }) else {
      return nil
    }
    if fields.count > 1, values.dropFirst().contains(where: { $0 >= 60 }) { return nil }
    return switch values.count {
    case 1: values[0]
    case 2: values[0] * 60 + values[1]
    case 3: values[0] * 3_600 + values[1] * 60 + values[2]
    default: nil
    }
  }

  static func string(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
  }

  static func fileNameString(_ seconds: Double) -> String {
    string(seconds).replacingOccurrences(of: ":", with: "-")
  }

  static func decimalSeconds(_ seconds: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
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
    let videoHeights = formats.filter(\.hasVideo).compactMap(\.height)
    if videoHeights.contains(where: { $0 >= 1080 }) { values.append(.p1080) }
    if videoHeights.contains(where: { $0 >= 720 }) { values.append(.p720) }
    if videoHeights.contains(where: { $0 >= 480 }) { values.append(.p480) }
    if formats.contains(where: { $0.hasAudio }) { values.append(.audioOnly) }
    return values
  }

  func mediaAsset(
    quality: LinkDownloadQuality, downloadSubtitles: Bool, subtitleLanguage: String?,
    outputPreset: EditingOutputPreset = .original, clipRange: ClipTimeRange? = nil
  ) -> MediaAsset {
    let subtitleIdentity =
      downloadSubtitles ? ":subs:\(subtitleLanguage?.nilIfEmpty ?? "all")" : ""
    let audioOnly = outputPreset == .audioOnly || quality == .audioOnly
    var metadata = [
      "sourceName": sourceName,
      "linkFormatSelector": audioOnly
        ? LinkDownloadQuality.audioOnly.formatSelector : quality.formatSelector,
      "linkQuality": quality.rawValue,
      "linkDownloadSubtitles": downloadSubtitles ? "true" : "false",
      "linkSubtitleLanguages": subtitleLanguage ?? "",
      "linkAudioOnly": quality == .audioOnly ? "true" : "false",
      "linkOutputPreset": outputPreset.rawValue,
      "linkMediaDuration": duration.map { String($0) } ?? "",
    ]
    if let clipRange {
      metadata["linkClipStart"] = String(clipRange.start)
      metadata["linkClipEnd"] = String(clipRange.end)
      metadata["linkClipDuration"] = String(clipRange.duration)
    }
    metadata["linkDownloader"] = "true"
    let clipIdentity = clipRange.map { ":clip:\($0.start)-\($0.end)" } ?? ""
    return MediaAsset(
      id: "\(id):\(quality.rawValue):\(outputPreset.rawValue)\(clipIdentity)\(subtitleIdentity)",
      provider: .linkDownloader, title: title,
      description: nil,
      thumbnailURL: thumbnailURL, previewURL: nil, downloadURL: originalURL,
      sourcePageURL: originalURL, creator: creator, license: nil, licenseURL: nil,
      licenseStatus: .unknown, width: nil, height: quality.maximumHeight, duration: duration,
      fileType: audioOnly ? "m4a" : (outputPreset == .editingCompatibleMP4 ? "mp4" : "video"),
      mediaType: audioOnly ? .audio : .video,
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
  var outputPreset: EditingOutputPreset
  var clipRange: ClipTimeRange?
  var mediaDuration: Double?

  static let `default` = YTDLPDownloadOptions(
    formatSelector: LinkDownloadQuality.p720.formatSelector,
    downloadSubtitles: false, subtitleLanguages: nil, outputPreset: .original, clipRange: nil,
    mediaDuration: nil)

  init(
    formatSelector: String, downloadSubtitles: Bool, subtitleLanguages: String?,
    outputPreset: EditingOutputPreset = .original, clipRange: ClipTimeRange? = nil,
    mediaDuration: Double? = nil
  ) {
    self.formatSelector = formatSelector
    self.downloadSubtitles = downloadSubtitles
    self.subtitleLanguages = subtitleLanguages
    self.outputPreset = outputPreset
    self.clipRange = clipRange
    self.mediaDuration = mediaDuration
  }

  init(asset: MediaAsset) {
    formatSelector =
      asset.originalMetadata["linkFormatSelector"]
      ?? LinkDownloadQuality.p720.formatSelector
    downloadSubtitles = asset.originalMetadata["linkDownloadSubtitles"] == "true"
    subtitleLanguages = asset.originalMetadata["linkSubtitleLanguages"]?.nilIfEmpty
    mediaDuration = asset.originalMetadata["linkMediaDuration"].flatMap(Double.init)
    outputPreset =
      EditingOutputPreset(
        rawValue: asset.originalMetadata["linkOutputPreset"] ?? "")
      ?? (asset.originalMetadata["linkAudioOnly"] == "true" ? .audioOnly : .original)
    if let start = asset.originalMetadata["linkClipStart"].flatMap(Double.init),
      let end = asset.originalMetadata["linkClipEnd"].flatMap(Double.init), end > start
    {
      clipRange = try? ClipTimeRange(start: start, end: end, mediaDuration: end)
    } else {
      clipRange = nil
    }
  }

  var requiresFFmpeg: Bool {
    outputPreset.requiresFFmpeg || clipRange != nil || formatSelector.contains("+")
  }

  /// Precise clipping and editing-compatible output require FFmpeg to decode
  /// the selected source. Prefer AVC + M4A when those formats are available;
  /// the original selector remains the final fallback for other sites.
  var effectiveFormatSelector: String {
    guard outputPreset != .audioOnly,
      clipRange != nil || outputPreset == .editingCompatibleMP4
    else { return formatSelector }
    let height: String
    if formatSelector.contains("height<=1080") {
      height = "[height<=1080]"
    } else if formatSelector.contains("height<=720") {
      height = "[height<=720]"
    } else if formatSelector.contains("height<=480") {
      height = "[height<=480]"
    } else {
      height = ""
    }
    return
      "bestvideo[vcodec^=avc1]\(height)+bestaudio[ext=m4a]/best[ext=mp4][vcodec^=avc1]\(height)/\(formatSelector)"
  }
}

struct YTDLPDownloadUpdate: Sendable {
  let fraction: Double
  let bytesPerSecond: Double
}

extension MediaAsset {
  /// Adds a creator-workflow output choice to an existing yt-dlp search result
  /// while keeping it in the same download queue and provider pipeline.
  func withEditingOutput(_ preset: EditingOutputPreset) -> MediaAsset {
    var value = self
    value.originalMetadata["linkOutputPreset"] = preset.rawValue
    value.originalMetadata["workflowVariantID"] = preset.rawValue
    value.originalMetadata["linkMediaDuration"] = duration.map { String($0) } ?? ""
    value.originalMetadata["linkAudioOnly"] = preset == .audioOnly ? "true" : "false"
    if preset == .audioOnly {
      value.originalMetadata["linkFormatSelector"] = LinkDownloadQuality.audioOnly.formatSelector
      value.mediaType = .audio
      value.fileType = "m4a"
    } else if preset == .editingCompatibleMP4 {
      value.fileType = "mp4"
    }
    return value
  }
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

  static func mediaURLs(from text: String) -> [URL] {
    let recognizedHosts = [
      "youtube.com", "youtu.be", "x.com", "twitter.com", "vimeo.com", "dailymotion.com",
      "tiktok.com", "twitch.tv", "reddit.com", "soundcloud.com", "facebook.com",
      "instagram.com",
    ]
    let mediaExtensions = ["mp4", "mov", "m4v", "webm", "mp3", "m4a", "wav", "ogg"]
    return urls(from: text).filter { url in
      let host = url.host?.lowercased() ?? ""
      return recognizedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        || mediaExtensions.contains(url.pathExtension.lowercased())
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
