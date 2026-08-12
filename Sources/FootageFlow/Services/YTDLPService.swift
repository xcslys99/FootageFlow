import Foundation

struct YTDLPService: Sendable {
  let runner: any ExternalToolRunning
  let executableURL: URL?
  let ffmpegURL: URL?
  let ffprobeURL: URL?

  init(
    runner: any ExternalToolRunning = ProcessExternalToolRunner(),
    executableURL: URL? = YTDLPBinaryLocator.executableURL,
    ffmpegURL: URL? = FFmpegToolLocator.ffmpegURL,
    ffprobeURL: URL? = FFmpegToolLocator.ffprobeURL
  ) {
    self.runner = runner
    self.executableURL = executableURL
    self.ffmpegURL = ffmpegURL
    self.ffprobeURL = ffprobeURL
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
    if options.requiresFFmpeg && (ffmpegURL == nil || ffprobeURL == nil) {
      throw ProviderError.externalToolUnavailable
    }
    var arguments =
      safeArguments + [
        "--no-playlist", "--no-overwrites", "--socket-timeout", "15", "--retries", "1",
        "--fragment-retries", "1", "--newline", "--progress-template",
        "download:FFPROGRESS:%(progress._percent_str)s|%(progress.speed)s", "--format",
        options.effectiveFormatSelector, "--paths", directory.path, "--output",
        "\(fileStem).%(ext)s",
        "--print", "after_move:FFFILE:%(filepath)s",
      ]
    if let ffmpegURL {
      arguments += ["--ffmpeg-location", ffmpegURL.deletingLastPathComponent().path]
    }
    if let clipRange = options.clipRange {
      arguments += ["--download-sections", clipRange.sectionArgument, "--force-keyframes-at-cuts"]
    }
    if options.outputPreset != .audioOnly,
      options.clipRange != nil || options.outputPreset == .editingCompatibleMP4
    {
      arguments += ["--merge-output-format", "mp4"]
    }
    if options.outputPreset == .audioOnly {
      arguments += ["--extract-audio", "--audio-format", "m4a", "--audio-quality", "0"]
    }
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
        let scale = options.outputPreset == .editingCompatibleMP4 ? 0.75 : 1
        progress?(
          YTDLPDownloadUpdate(
            fraction: update.fraction * scale, bytesPerSecond: update.bytesPerSecond))
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
    if options.outputPreset == .editingCompatibleMP4 {
      do {
        return try await transcodeEditingCompatible(
          input: fileURL, directory: directory, fileStem: fileStem,
          duration: options.clipRange?.duration ?? options.mediaDuration, progress: progress)
      } catch {
        try? FileManager.default.removeItem(at: fileURL)
        throw error
      }
    }
    return fileURL
  }

  private func transcodeEditingCompatible(
    input: URL, directory: URL, fileStem: String, duration: Double?,
    progress: (@Sendable (YTDLPDownloadUpdate) -> Void)?
  ) async throws -> URL {
    guard let ffmpegURL, let ffprobeURL else { throw ProviderError.externalToolUnavailable }
    let canStreamCopy = await isEditingCompatibleSource(input, ffprobeURL: ffprobeURL)
    let temporary = directory.appendingPathComponent(
      ".\(fileStem).\(UUID().uuidString).footageflow.mp4")
    defer { try? FileManager.default.removeItem(at: temporary) }
    var arguments = ["-hide_banner", "-nostdin", "-y", "-i", input.path]
    arguments += ["-map", "0:v:0", "-map", "0:a:0?"]
    if canStreamCopy {
      arguments += ["-c", "copy"]
    } else {
      arguments += [
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
      ]
    }
    arguments += [
      "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", temporary.path,
    ]
    let result = try await runner.run(
      executable: ffmpegURL, arguments: arguments, timeout: 60 * 60,
      onOutputLine: { line in
        guard let duration, duration > 0,
          let seconds = Self.ffmpegProgressSeconds(from: line)
        else { return }
        progress?(
          YTDLPDownloadUpdate(
            fraction: min(0.75 + seconds / duration * 0.25, 0.99), bytesPerSecond: 0))
      })
    guard result.exitCode == 0, FileManager.default.fileExists(atPath: temporary.path) else {
      throw ProviderError.message(tr("link.outputConversionFailed"))
    }
    try await verifyEditingCompatible(temporary, ffprobeURL: ffprobeURL)
    let final = directory.appendingPathComponent("\(fileStem).mp4")
    if final.standardizedFileURL == input.standardizedFileURL {
      try FileManager.default.removeItem(at: input)
    } else if FileManager.default.fileExists(atPath: final.path) {
      throw ProviderError.message(tr("download.duplicate"))
    }
    try FileManager.default.moveItem(at: temporary, to: final)
    if input.standardizedFileURL != final.standardizedFileURL {
      try? FileManager.default.removeItem(at: input)
    }
    progress?(YTDLPDownloadUpdate(fraction: 1, bytesPerSecond: 0))
    return final
  }

  private func isEditingCompatibleSource(_ url: URL, ffprobeURL: URL) async -> Bool {
    guard url.pathExtension.lowercased() == "mp4" else { return false }
    let result = try? await runner.run(
      executable: ffprobeURL,
      arguments: [
        "-v", "error", "-show_entries", "stream=codec_type,codec_name,pix_fmt", "-of", "json",
        url.path,
      ], timeout: 60)
    guard let result, result.exitCode == 0,
      let value = try? JSONDecoder().decode(FFprobeResponse.self, from: result.standardOutput)
    else { return false }
    return value.streams.contains(where: {
      $0.codecType == "video" && $0.codecName == "h264" && $0.pixelFormat == "yuv420p"
    })
      && !value.streams.contains(where: {
        $0.codecType == "audio" && $0.codecName != "aac"
      })
  }

  private func verifyEditingCompatible(_ url: URL, ffprobeURL: URL) async throws {
    let result = try await runner.run(
      executable: ffprobeURL,
      arguments: [
        "-v", "error", "-show_entries", "stream=codec_type,codec_name,pix_fmt", "-of", "json",
        url.path,
      ], timeout: 60)
    guard result.exitCode == 0,
      let value = try? JSONDecoder().decode(FFprobeResponse.self, from: result.standardOutput),
      value.streams.contains(where: {
        $0.codecType == "video" && $0.codecName == "h264" && $0.pixelFormat == "yuv420p"
      }),
      !value.streams.contains(where: { $0.codecType == "audio" && $0.codecName != "aac" })
    else { throw ProviderError.message(tr("link.outputConversionFailed")) }
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
    if (message.contains("oauth")
      && (message.contains("401") || message.contains("unauthorized")))
      || message.contains("web client only works when logged-in")
    {
      return .temporarilyBlocked(.vimeo)
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

  static func ffmpegProgressSeconds(from line: String) -> Double? {
    guard line.hasPrefix("out_time_ms="), let microseconds = Double(line.dropFirst(12)) else {
      return nil
    }
    return microseconds / 1_000_000
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
    if value.contains("dailymotion") { return "Dailymotion" }
    return extractor?.nilIfEmpty ?? host?.nilIfEmpty ?? tr("common.unknown")
  }
}

private struct FFprobeResponse: Decodable {
  let streams: [FFprobeStream]
}

private struct FFprobeStream: Decodable {
  let codecType, codecName, pixelFormat: String?

  enum CodingKeys: String, CodingKey {
    case codecType = "codec_type"
    case codecName = "codec_name"
    case pixelFormat = "pix_fmt"
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

enum FFmpegToolLocator {
  static var ffmpegURL: URL? { executable(named: "ffmpeg") }
  static var ffprobeURL: URL? { executable(named: "ffprobe") }

  private static func executable(named name: String) -> URL? {
    let fileManager = FileManager.default
    #if os(Windows)
      let fileName = "\(name).exe"
    #else
      let fileName = name
    #endif
    if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/\(fileName)"),
      isExecutable(bundled, fileManager: fileManager)
    {
      return bundled
    }
    #if os(macOS)
      for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
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
