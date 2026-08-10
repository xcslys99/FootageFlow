import Combine
import Foundation

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

final class LocalizationManager: ObservableObject, @unchecked Sendable {
    static let shared = LocalizationManager()
    static let preferenceKey = "appLanguage"

    @Published private(set) var language: AppLanguage
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
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
        let current = localizedValue(key, language: language)
        let fallback = current ?? localizedValue(key, language: .english) ?? localizedValue("common.unavailable", language: .english) ?? "Unavailable"
        guard !arguments.isEmpty else { return fallback }
        return String(format: fallback, locale: language.locale, arguments: arguments)
    }

    private func localizedValue(_ key: String, language: AppLanguage) -> String? {
        let names = [language.rawValue, language.rawValue.lowercased()]
        let bundle = names.lazy.compactMap { name -> Bundle? in
            if let path = Bundle.module.path(forResource: name, ofType: "lproj"), let bundle = Bundle(path: path) { return bundle }
            return Bundle(url: Bundle.module.bundleURL.appendingPathComponent("\(name).lproj", isDirectory: true))
        }.first
        guard let bundle else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}

func tr(_ key: String, _ arguments: CVarArg...) -> String {
    LocalizationManager.shared.text(key, arguments: arguments)
}
