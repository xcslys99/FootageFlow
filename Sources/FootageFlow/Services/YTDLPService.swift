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

  func search(query: String, limit: Int) async throws -> [YTDLPSearchItem] {
    guard let executableURL, isAvailable else { throw ProviderError.externalToolUnavailable }
    let count = max(1, min(limit, 12))
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

  func download(sourceURL: URL, directory: URL, fileStem: String) async throws -> URL {
    guard let executableURL, isAvailable else { throw ProviderError.externalToolUnavailable }
    let result = try await runner.run(
      executable: executableURL,
      arguments: commonArguments + [
        "--no-playlist", "--no-overwrites", "--socket-timeout", "15", "--retries", "1",
        "--fragment-retries", "1", "--format",
        "best[ext=mp4][acodec!=none][vcodec!=none][height<=720]/best[acodec!=none][vcodec!=none][height<=720]",
        "--paths", directory.path, "--output", "\(fileStem).%(ext)s", "--print",
        "after_move:filepath", sourceURL.absoluteString,
      ], timeout: 60 * 60)
    guard result.exitCode == 0 else { throw Self.mapFailure(result.errorText) }
    let lines = result.outputText.split(whereSeparator: \.isNewline).map(String.init)
    guard let path = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
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
    return .message(tr("error.ytDLPFailed"))
  }

  var commonArguments: [String] {
    ["--ignore-config", "--no-progress", "--no-warnings"]
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
