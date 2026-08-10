import Foundation

#if canImport(Combine)
  import Combine
#endif

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
  case english = "en"
  case simplifiedChinese = "zh-Hans"

  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .english: "English"
    case .simplifiedChinese: "简体中文"
    }
  }
  var locale: Locale { Locale(identifier: rawValue) }
}

struct LocalizationCatalog: Sendable {
  private let languageBundles: [AppLanguage: Bundle]

  init() {
    var bundles: [AppLanguage: Bundle] = [:]
    for language in AppLanguage.allCases {
      search: for root in Self.resourceRoots() {
        for name in [language.rawValue, language.rawValue.lowercased()] {
          let directory = root.appendingPathComponent("\(name).lproj", isDirectory: true)
          if let bundle = Bundle(url: directory) {
            bundles[language] = bundle
            break search
          }
        }
      }
    }
    languageBundles = bundles
  }

  func text(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
    let current = localizedValue(key, language: language)
    let fallback =
      current ?? localizedValue(key, language: .english)
      ?? localizedValue("common.unavailable", language: .english) ?? "Unavailable"
    guard !arguments.isEmpty else { return fallback }
    return String(format: fallback, locale: language.locale, arguments: arguments)
  }

  private func localizedValue(_ key: String, language: AppLanguage) -> String? {
    guard let bundle = languageBundles[language] else { return nil }
    let value = bundle.localizedString(forKey: key, value: nil, table: nil)
    return value == key ? nil : value
  }

  private static func resourceRoots() -> [URL] {
    var roots: [URL] = []
    if let packaged = Bundle.main.resourceURL, !roots.contains(packaged) {
      roots.append(packaged)
    }
    if let configured = ProcessInfo.processInfo.environment["FOOTAGEFLOW_RESOURCE_DIR"] {
      roots.append(URL(fileURLWithPath: configured, isDirectory: true))
    }
    let development = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true
    ).appendingPathComponent("Sources/FootageFlow/Resources", isDirectory: true)
    if !roots.contains(development) { roots.append(development) }
    return roots
  }
}

#if canImport(Combine)
  final class LocalizationManager: ObservableObject, @unchecked Sendable {
    static let shared = LocalizationManager()
    static let preferenceKey = "appLanguage"

    @Published private(set) var language: AppLanguage
    private let defaults: UserDefaults
    private let catalog: LocalizationCatalog

    init(defaults: UserDefaults = .standard) {
      self.defaults = defaults
      catalog = LocalizationCatalog()
      language =
        defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    var locale: Locale { language.locale }

    func setLanguage(_ value: AppLanguage) {
      guard language != value else { return }
      language = value
      defaults.set(value.rawValue, forKey: Self.preferenceKey)
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
      text(key, arguments: arguments)
    }

    fileprivate func text(_ key: String, arguments: [CVarArg]) -> String {
      catalog.text(key, language: language, arguments: arguments)
    }
  }

  func tr(_ key: String, _ arguments: CVarArg...) -> String {
    LocalizationManager.shared.text(key, arguments: arguments)
  }
#else
  enum CoreLocalization {
    private static let catalog = LocalizationCatalog()
    nonisolated(unsafe) static var language: AppLanguage = .english

    static func text(_ key: String, arguments: [CVarArg]) -> String {
      catalog.text(key, language: language, arguments: arguments)
    }
  }

  func tr(_ key: String, _ arguments: CVarArg...) -> String {
    CoreLocalization.text(key, arguments: arguments)
  }
#endif
