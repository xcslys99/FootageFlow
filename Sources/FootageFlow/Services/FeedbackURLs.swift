import Foundation

enum FeedbackDestination: String, Codable, Sendable {
  case bug, feature, question, repository, releases
}

struct FeedbackContext: Sendable {
  let platform: String
  let osVersion: String
  let language: String

  static var current: FeedbackContext {
    #if os(Windows)
      let platform = "Windows"
    #else
      let platform = "macOS"
    #endif
    #if canImport(Combine)
      let language = LocalizationManager.shared.language.rawValue
    #else
      let language = CoreLocalization.language.rawValue
    #endif
    return FeedbackContext(
      platform: platform, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      language: language)
  }
}

enum FeedbackURLs {
  static let repository = URL(string: "https://github.com/xcslys99/FootageFlow")!

  static func url(for destination: FeedbackDestination, context: FeedbackContext = .current) -> URL
  {
    switch destination {
    case .repository: return repository
    case .releases: return repository.appendingPathComponent("releases")
    case .feature:
      return URL(string: "https://github.com/xcslys99/FootageFlow/discussions/new?category=ideas")!
    case .question:
      return URL(string: "https://github.com/xcslys99/FootageFlow/discussions/new?category=q-a")!
    case .bug:
      var components = URLComponents(
        string: "https://github.com/xcslys99/FootageFlow/issues/new")!
      components.queryItems = [
        URLQueryItem(name: "template", value: "bug_report.yml"),
        URLQueryItem(name: "version", value: FootageFlowVersion.current),
        URLQueryItem(name: "operating-system", value: "\(context.platform) \(context.osVersion)"),
        URLQueryItem(name: "application-language", value: context.language),
      ]
      return components.url!
    }
  }
}
