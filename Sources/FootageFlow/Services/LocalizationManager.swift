import Foundation

#if canImport(Combine)
  import Combine
#endif

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"
  case spanish = "es"
  case brazilianPortuguese = "pt-BR"
  case japanese = "ja"
  case korean = "ko"
  case german = "de"
  case french = "fr"
  case russian = "ru"

  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .english: "English"
    case .simplifiedChinese: "简体中文"
    case .traditionalChinese: "繁體中文"
    case .spanish: "Español"
    case .brazilianPortuguese: "Português (Brasil)"
    case .japanese: "日本語"
    case .korean: "한국어"
    case .german: "Deutsch"
    case .french: "Français"
    case .russian: "Русский"
    }
  }
  var locale: Locale { Locale(identifier: rawValue) }
}

struct LocalizationCatalog: Sendable {
  /// Loading a `.lproj` directory as a Bundle lets Foundation choose the
  /// system-preferred language again, even when the user selected a different
  /// FootageFlow language. Keep a parsed table for each explicit locale so the
  /// in-app switcher changes every `tr(...)` string immediately.
  private let languageTables: [AppLanguage: [String: String]]

  init() {
    var tables: [AppLanguage: [String: String]] = [:]
    for language in AppLanguage.allCases {
      search: for root in Self.resourceRoots() {
        for name in [language.rawValue, language.rawValue.lowercased()] {
          let directory = root.appendingPathComponent("\(name).lproj", isDirectory: true)
          if let table = Self.readStrings(in: directory), !table.isEmpty {
            tables[language] = table
            break search
          }
        }
      }
    }
    languageTables = tables
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
    languageTables[language]?[key]
  }

  private static func readStrings(in directory: URL) -> [String: String]? {
    let file = directory.appendingPathComponent("Localizable.strings")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    let pattern = #"^\s*\"((?:\\.|[^\"])*)\"\s*=\s*\"((?:\\.|[^\"])*)\"\s*;"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    return expression.matches(in: text, range: range).reduce(into: [:]) { result, match in
      guard let keyRange = Range(match.range(at: 1), in: text),
        let valueRange = Range(match.range(at: 2), in: text)
      else { return }
      result[decode(String(text[keyRange]))] = decode(String(text[valueRange]))
    }
  }

  private static func decode(_ value: String) -> String {
    value
      .replacingOccurrences(of: #"\n"#, with: "\n")
      .replacingOccurrences(of: #"\""#, with: "\"")
      .replacingOccurrences(of: #"\\"#, with: "\\")
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
