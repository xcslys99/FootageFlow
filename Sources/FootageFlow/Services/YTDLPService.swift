import Foundation

struct YTDLPService: Sendable {
  let runner: any ExternalToolRunning
  let executableURL: URL?

  init(
    runner: any ExternalToolRunning = ProcessExternalToolRunner(),
    executableURL: URL? = YTDLPBinaryLocator.executableURL
  ) {
    self.runner = runner
    self.executableURL = executableURL
  }

  var isAvailable: Bool {
    guard let executableURL else { return false }
    #if os(Windows)
      return FileManager.default.fileExists(atPath: executableURL.path)
    #else
      return FileManager.default.isExecutableFile(atPath: executableURL.path)
    #endif
  }

  func analyze(sourceURL: URL) async throws -> LinkMediaAnalysis {
    guard let executableURL, isAvailable else { throw ProviderError.externalToolUnavailable }
    guard let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
      LinkURLSecurity.isSafe(components)
    else { throw ProviderError.unsupported }
    let result = try await runner.run(
      executable: executableURL,
      arguments: commonArguments + [
        "--no-playlist", "--skip-download", "--dump-single-json", "--socket-timeout", "15",
        sourceURL.absoluteString,
      ], timeout: 150)
    guard result.exitCode == 0 else { throw Self.mapFailure(result.errorText) }
    do {
      let response = try JSONDecoder().decode(
        YTDLPAnalysisResponse.self, from: result.standardOutput)
      return try Self.linkAnalysis(response, fallbackURL: sourceURL)
    } catch let error as ProviderError {
      throw error
    } catch {
      throw ProviderError.invalidResponse
    }
  }

  func search(query: String, limit: Int) async throws -> [YTDLPSearchItem] {
    guard let executableURL, isAvailable else { throw ProviderError.externalToolUnavailable }
    let count = max(1, min(limit, 60))
    let result = try await runner.run(
      executable: executableURL,
      arguments: commonArguments + [
        "--flat-playlist", "--dump-single-json", "--playlist-end", String(count),
        "ytsearch\(count):\(query)",
      ], timeout: 75)
    guard result.exitCode == 0 else { throw Self.mapFailure(result.errorText) }
    do {
      let response = try JSONDecoder().decode(YTDLPSearchResponse.self, from: result.standardOutput)
      return response.entries
    } catch {
      throw ProviderError.invalidResponse
    }
  }

  func download(
    sourceURL: URL, directory: URL, fileStem: String,
    options: YTDLPDownloadOptions = .default,
    progress: (@Sendable (YTDLPDownloadUpdate) -> Void)? = nil
  ) async throws -> URL {
    guard let executableURL, isAvailable else { throw ProviderError.externalToolUnavailable }
    var arguments =
      safeArguments + [
        "--no-playlist", "--no-overwrites", "--socket-timeout", "15", "--retries", "1",
        "--fragment-retries", "1", "--newline", "--progress-template",
        "download:FFPROGRESS:%(progress._percent_str)s|%(progress.speed)s", "--format",
        options.formatSelector, "--paths", directory.path, "--output", "\(fileStem).%(ext)s",
        "--print", "after_move:FFFILE:%(filepath)s",
      ]
    if options.downloadSubtitles {
      arguments.append("--write-subs")
      if let languages = options.subtitleLanguages?.nilIfEmpty {
        arguments += ["--sub-langs", languages]
      }
    }
    arguments.append(sourceURL.absoluteString)
    let result = try await runner.run(
      executable: executableURL,
      arguments: arguments, timeout: 60 * 60,
      onOutputLine: { line in
        guard let update = Self.progressUpdate(from: line) else { return }
        progress?(update)
      })
    guard result.exitCode == 0 else { throw Self.mapFailure(result.errorText) }
    let lines = result.outputText.split(whereSeparator: \.isNewline).map(String.init)
    let printedPath = lines.last(where: { $0.hasPrefix("FFFILE:") }).map {
      String($0.dropFirst("FFFILE:".count))
    }
    let fallbackPath = lines.last(where: { !$0.hasPrefix("FFPROGRESS:") })
    guard let path = (printedPath ?? fallbackPath)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !path.isEmpty
    else { throw ProviderError.invalidResponse }
    let fileURL = URL(fileURLWithPath: path)
    guard DownloadPathSafety.isContained(fileURL, in: directory),
      FileManager.default.fileExists(atPath: fileURL.path)
    else { throw ProviderError.invalidResponse }
    return fileURL
  }

  static func mapFailure(_ rawMessage: String) -> ProviderError {
    let message = rawMessage.lowercased()
    if message.contains("429") || message.contains("too many requests") {
      return .rateLimited(retryAfter: nil)
    }
    if message.contains("video unavailable") || message.contains("has been removed") {
      return .videoUnavailable
    }
    if message.contains("not available in your country")
      || message.contains("not available in your region") || message.contains("geo-restricted")
    {
      return .regionalRestriction
    }
    if message.contains("sign in") || message.contains("login") || message.contains("private video")
      || message.contains("members-only") || message.contains("age-restricted")
    {
      return .temporarilyBlocked(.youtube)
    }
    if message.contains("unsupported url") || message.contains("no suitable extractor") {
      return .unsupported
    }
    return .message(tr("error.ytDLPFailed"))
  }

  var commonArguments: [String] {
    safeArguments + ["--no-progress"]
  }

  var safeArguments: [String] { ["--ignore-config", "--no-warnings"] }

  static func progressUpdate(from line: String) -> YTDLPDownloadUpdate? {
    guard let range = line.range(of: "FFPROGRESS:") else { return nil }
    let fields = line[range.upperBound...].split(separator: "|", maxSplits: 1).map(String.init)
    guard
      let percentText = fields.first?.replacingOccurrences(of: "%", with: "")
        .trimmingCharacters(in: .whitespaces), let percent = Double(percentText)
    else { return nil }
    let speedText = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
    let speed = Double(speedText) ?? 0
    return YTDLPDownloadUpdate(fraction: min(max(percent / 100, 0), 1), bytesPerSecond: speed)
  }

  static func linkAnalysis(_ value: YTDLPAnalysisResponse, fallbackURL: URL) throws
    -> LinkMediaAnalysis
  {
    let candidateURL = URLValidator.remote(value.webpageURL)
    let sourceURL = candidateURL.flatMap { LinkURLSecurity.isSafe($0) ? $0 : nil } ?? fallbackURL
    let source = sourceDisplayName(value.extractorKey ?? value.extractor, host: sourceURL.host)
    let thumbnails = value.thumbnails ?? []
    let thumbnail =
      value.thumbnail.flatMap(URLValidator.remote)
      ?? thumbnails.max {
        ($0.width ?? 0) * ($0.height ?? 0) < ($1.width ?? 0) * ($1.height ?? 0)
      }.flatMap { URLValidator.remote($0.url) }
    let decodedFormats: [YTDLPFormat] = value.formats ?? []
    let formats: [LinkMediaFormat] = decodedFormats.compactMap { item in
      guard item.hasDRM != true else { return nil }
      let hasVideo = item.videoCodec.map { $0.lowercased() != "none" } ?? false
      let hasAudio = item.audioCodec.map { $0.lowercased() != "none" } ?? false
      return LinkMediaFormat(
        formatID: item.formatID, fileExtension: item.ext, width: item.width, height: item.height,
        fps: item.fps, fileSize: item.fileSize ?? item.approximateFileSize,
        hasVideo: hasVideo, hasAudio: hasAudio)
    }
    let languages = Set((value.subtitles ?? [:]).keys).union((value.automaticCaptions ?? [:]).keys)
    guard !value.id.isEmpty else { throw ProviderError.invalidResponse }
    return LinkMediaAnalysis(
      id: "\(source.lowercased()):\(value.id)", originalURL: sourceURL, sourceName: source,
      title: value.title?.nilIfEmpty ?? value.id,
      creator: value.channel?.nilIfEmpty ?? value.uploader?.nilIfEmpty,
      thumbnailURL: thumbnail, duration: value.duration, formats: formats,
      subtitleLanguages: languages.sorted())
  }

  static func sourceDisplayName(_ extractor: String?, host: String?) -> String {
    let value = (extractor ?? host ?? tr("common.unknown")).lowercased()
    if value.contains("youtube") { return "YouTube" }
    if value.contains("twitter") || value == "x" || value.contains("x.com") {
      return "X / Twitter"
    }
    if value.contains("vimeo") { return "Vimeo" }
    return extractor?.nilIfEmpty ?? host?.nilIfEmpty ?? tr("common.unknown")
  }
}

struct YTDLPAnalysisResponse: Decodable, Sendable {
  let id: String
  let title, uploader, channel, thumbnail, extractor, extractorKey, webpageURL: String?
  let duration: Double?
  let thumbnails: [YTDLPThumbnail]?
  let formats: [YTDLPFormat]?
  let subtitles, automaticCaptions: [String: [YTDLPSubtitle]]?

  enum CodingKeys: String, CodingKey {
    case id, title, uploader, channel, thumbnail, extractor, duration, thumbnails, formats,
      subtitles
    case extractorKey = "extractor_key"
    case webpageURL = "webpage_url"
    case automaticCaptions = "automatic_captions"
  }
}

struct YTDLPFormat: Decodable, Sendable {
  let formatID: String
  let ext, videoCodec, audioCodec: String?
  let width, height: Int?
  let fps: Double?
  let fileSize, approximateFileSize: Int64?
  let hasDRM: Bool?
  enum CodingKeys: String, CodingKey {
    case formatID = "format_id"
    case ext, width, height, fps
    case videoCodec = "vcodec"
    case audioCodec = "acodec"
    case fileSize = "filesize"
    case approximateFileSize = "filesize_approx"
    case hasDRM = "has_drm"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    formatID = try container.decodeIfPresent(String.self, forKey: .formatID) ?? "unknown"
    ext = try container.decodeIfPresent(String.self, forKey: .ext)
    videoCodec = try container.decodeIfPresent(String.self, forKey: .videoCodec)
    audioCodec = try container.decodeIfPresent(String.self, forKey: .audioCodec)
    width = try container.decodeFlexibleInt(forKey: .width)
    height = try container.decodeFlexibleInt(forKey: .height)
    fps = try container.decodeFlexibleDouble(forKey: .fps)
    fileSize = try container.decodeFlexibleInt64(forKey: .fileSize)
    approximateFileSize = try container.decodeFlexibleInt64(forKey: .approximateFileSize)
    hasDRM = try container.decodeIfPresent(Bool.self, forKey: .hasDRM)
  }
}

struct YTDLPSubtitle: Decodable, Sendable {
  let url, ext: String?
}

extension KeyedDecodingContainer {
  fileprivate func decodeFlexibleInt(forKey key: Key) throws -> Int? {
    if let value = try decodeIfPresent(Int.self, forKey: key) { return value }
    if let value = try decodeIfPresent(Double.self, forKey: key) { return Int(value) }
    if let value = try decodeIfPresent(String.self, forKey: key) { return Int(value) }
    return nil
  }
  fileprivate func decodeFlexibleInt64(forKey key: Key) throws -> Int64? {
    if let value = try decodeIfPresent(Int64.self, forKey: key) { return value }
    if let value = try decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
    if let value = try decodeIfPresent(String.self, forKey: key) { return Int64(value) }
    return nil
  }
  fileprivate func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
    if let value = try decodeIfPresent(Double.self, forKey: key) { return value }
    if let value = try decodeIfPresent(String.self, forKey: key) { return Double(value) }
    return nil
  }
}

enum YTDLPBinaryLocator {
  static var executableURL: URL? {
    let fileManager = FileManager.default
    #if os(Windows)
      let bundledName = "yt-dlp.exe"
    #else
      let bundledName = "yt-dlp"
    #endif
    if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/\(bundledName)"),
      isExecutable(bundled, fileManager: fileManager)
    {
      return bundled
    }
    #if os(macOS)
      for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
      where fileManager.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
      }
    #endif
    return nil
  }

  private static func isExecutable(_ url: URL, fileManager: FileManager) -> Bool {
    #if os(Windows)
      fileManager.fileExists(atPath: url.path)
    #else
      fileManager.isExecutableFile(atPath: url.path)
    #endif
  }
}

struct YTDLPSearchResponse: Decodable, Sendable {
  let entries: [YTDLPSearchItem]
}

struct YTDLPSearchItem: Decodable, Sendable {
  let id: String
  let title: String?
  let url: String?
  let webpageURL: String?
  let duration: Double?
  let channel: String?
  let uploader: String?
  let thumbnails: [YTDLPThumbnail]?

  enum CodingKeys: String, CodingKey {
    case id, title, url, duration, channel, uploader, thumbnails
    case webpageURL = "webpage_url"
  }
}

struct YTDLPThumbnail: Decodable, Sendable {
  let url: String
  let width: Int?
  let height: Int?
}
