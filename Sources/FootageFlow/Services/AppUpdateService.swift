import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct AppRelease: Codable, Equatable, Identifiable, Sendable {
  let version: String
  let title: String
  let notes: String
  let pageURL: URL
  let publishedAt: Date?

  var id: String { version }
}

enum AppUpdateCheckOutcome: Equatable, Sendable {
  case updateAvailable(AppRelease)
  case upToDate(latestVersion: String)
}

enum AppUpdateCheckError: Error, Equatable, Sendable {
  case noNetwork
  case timedOut
  case rateLimited
  case serverUnavailable
  case invalidResponse

  var code: String {
    switch self {
    case .noNetwork: "noNetwork"
    case .timedOut: "timeout"
    case .rateLimited: "rateLimited"
    case .serverUnavailable: "serverUnavailable"
    case .invalidResponse: "invalidResponse"
    }
  }
}

struct SemanticAppVersion: Comparable, Equatable, Sendable {
  private let numbers: [Int]
  private let prerelease: [String]

  init?(_ rawValue: String) {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("v") { value.removeFirst() }
    value = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
    let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let rawNumbers = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
    guard !rawNumbers.isEmpty, rawNumbers.count <= 4 else { return nil }
    let numbers = rawNumbers.compactMap { Int($0) }
    guard numbers.count == rawNumbers.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
    let prerelease =
      pieces.count == 2
      ? pieces[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
    guard prerelease.allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isIdentifierCharacter) })
    else { return nil }
    self.numbers = numbers
    self.prerelease = prerelease
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    let count = max(lhs.numbers.count, rhs.numbers.count, 3)
    for index in 0..<count {
      let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
      let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
      if left != right { return left < right }
    }
    if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
    for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
      guard index < lhs.prerelease.count else { return true }
      guard index < rhs.prerelease.count else { return false }
      let left = lhs.prerelease[index]
      let right = rhs.prerelease[index]
      if left == right { continue }
      if let leftNumber = Int(left), let rightNumber = Int(right) {
        return leftNumber < rightNumber
      }
      if Int(left) != nil { return true }
      if Int(right) != nil { return false }
      return left < right
    }
    return false
  }

  private static func isIdentifierCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "-"
  }
}

enum ReleaseNotesFormatter {
  static func plainText(_ markdown: String?, limit: Int = 20_000) -> String {
    guard let markdown else { return "" }
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var output: [String] = []
    var previousWasBlank = false

    for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = String(rawLine).trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("```") { continue }
      while line.hasPrefix("#") { line.removeFirst() }
      line = line.trimmingCharacters(in: .whitespaces)
      if line == "---" || line == "***" || line == "___" { line = "" }
      if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
        line = "• " + line.dropFirst(2)
      }
      line = line.replacingOccurrences(
        of: #"!?\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
      for marker in ["**", "__", "`"] {
        line = line.replacingOccurrences(of: marker, with: "")
      }
      // Both platform shells render this output as inert plain text. Escaping angle brackets
      // also keeps embedded HTML or scripts inert if a future text control supports markup.
      line = line.replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")

      let isBlank = line.isEmpty
      if isBlank && previousWasBlank { continue }
      output.append(line)
      previousWasBlank = isBlank
    }

    return String(
      output.joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(limit))
  }
}

actor AppUpdateService {
  static let shared = AppUpdateService()
  static let releasesPageURL = URL(string: "https://github.com/xcslys99/FootageFlow/releases")!
  static let latestReleasePageURL = releasesPageURL.appendingPathComponent("latest")
  static let latestReleaseAPI = URL(
    string: "https://api.github.com/repos/xcslys99/FootageFlow/releases/latest")!

  private let session: URLSession
  private let endpoint: URL

  init(session: URLSession? = nil, endpoint: URL = AppUpdateService.latestReleaseAPI) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 10
      configuration.timeoutIntervalForResource = 15
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      self.session = URLSession(configuration: configuration)
    }
    self.endpoint = endpoint
  }

  func check(currentVersion: String = FootageFlowVersion.current) async throws
    -> AppUpdateCheckOutcome
  {
    var request = URLRequest(url: endpoint)
    request.timeoutInterval = 10
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue(
      "FootageFlow/\(currentVersion) (cross-platform update checker)",
      forHTTPHeaderField: "User-Agent")
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw AppUpdateCheckError.invalidResponse
      }
      switch http.statusCode {
      case 200:
        return try Self.evaluate(data: data, currentVersion: currentVersion)
      case 403, 429:
        throw AppUpdateCheckError.rateLimited
      case 500...599:
        throw AppUpdateCheckError.serverUnavailable
      default:
        throw AppUpdateCheckError.invalidResponse
      }
    } catch let error as AppUpdateCheckError {
      throw error
    } catch let error as URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed,
        .cannotConnectToHost:
        throw AppUpdateCheckError.noNetwork
      case .timedOut: throw AppUpdateCheckError.timedOut
      default: throw AppUpdateCheckError.invalidResponse
      }
    } catch {
      throw AppUpdateCheckError.invalidResponse
    }
  }

  static func evaluate(data: Data, currentVersion: String) throws -> AppUpdateCheckOutcome {
    let payload: GitHubReleasePayload
    do {
      payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
    } catch {
      throw AppUpdateCheckError.invalidResponse
    }
    guard !payload.draft, !payload.prerelease,
      let latest = SemanticAppVersion(payload.tagName),
      let current = SemanticAppVersion(currentVersion)
    else { throw AppUpdateCheckError.invalidResponse }
    let version = normalizedVersion(payload.tagName)
    guard current < latest else { return .upToDate(latestVersion: version) }
    return .updateAvailable(
      AppRelease(
        version: version,
        title: cleaned(payload.name, limit: 240) ?? "FootageFlow v\(version)",
        notes: ReleaseNotesFormatter.plainText(payload.body),
        pageURL: trustedReleaseURL(payload.htmlURL),
        publishedAt: parseDate(payload.publishedAt)))
  }

  private static func normalizedVersion(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.lowercased().hasPrefix("v") { result.removeFirst() }
    return result
  }

  private static func cleaned(_ value: String?, limit: Int) -> String? {
    guard let value else { return nil }
    let clean = value.replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return String(clean.prefix(limit))
  }

  static func isTrustedReleaseURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com"
      && url.user == nil && url.password == nil && url.port == nil
      && url.path.hasPrefix("/xcslys99/FootageFlow/releases/")
  }

  private static func trustedReleaseURL(_ value: String?) -> URL {
    guard let value, let url = URL(string: value), isTrustedReleaseURL(url)
    else { return latestReleasePageURL }
    return url
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

private struct GitHubReleasePayload: Decodable {
  let tagName: String
  let name: String?
  let body: String?
  let htmlURL: String?
  let publishedAt: String?
  let draft: Bool
  let prerelease: Bool

  enum CodingKeys: String, CodingKey {
    case name, body, draft, prerelease
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case publishedAt = "published_at"
  }
}

#if os(macOS)
  import Combine

  @MainActor
  final class AppUpdateController: ObservableObject {
    typealias CheckAction = @Sendable () async throws -> AppUpdateCheckOutcome

    enum ManualState: Equatable {
      case idle
      case checking
      case upToDate
      case failed(AppUpdateCheckError)
    }

    @Published var availableRelease: AppRelease?
    @Published private(set) var manualState: ManualState = .idle
    private let checkAction: CheckAction
    private var checkedAtLaunch = false
    private var presentedAutomaticUpdate = false

    init(
      checkAction: @escaping CheckAction = { try await AppUpdateService.shared.check() }
    ) {
      self.checkAction = checkAction
    }

    func checkAtLaunch() async {
      guard !checkedAtLaunch else { return }
      checkedAtLaunch = true
      await performCheck(manual: false)
    }

    func checkManually() async {
      await performCheck(manual: true)
    }

    func notNow() { availableRelease = nil }

    func viewUpdate() {
      guard let release = availableRelease,
        AppUpdateService.isTrustedReleaseURL(release.pageURL)
      else { return }
      availableRelease = nil
      DesktopPlatform.shared.open(release.pageURL)
    }

    private func performCheck(manual: Bool) async {
      if manual { manualState = .checking }
      do {
        switch try await checkAction() {
        case .upToDate:
          if manual { manualState = .upToDate }
        case .updateAvailable(let release):
          if manual || !presentedAutomaticUpdate {
            if !manual { presentedAutomaticUpdate = true }
            availableRelease = release
          }
          if manual { manualState = .idle }
        }
      } catch let error as AppUpdateCheckError {
        if manual { manualState = .failed(error) }
        await AppLogger.shared.write(
          provider: nil, requestType: "updateCheck", error: error, detail: error.code)
      } catch {
        if manual { manualState = .failed(.invalidResponse) }
        await AppLogger.shared.write(
          provider: nil, requestType: "updateCheck", error: error, detail: "invalidResponse")
      }
    }
  }
#endif
