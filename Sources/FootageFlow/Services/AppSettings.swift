import Foundation

enum AppSettings {
  static let enabledProvidersKey = "enabledProviders"
  static let downloadRootKey = "downloadRoot"
  private static let migrationKey = "didMigrateFootageFinderSettings"

  static func migrateLegacySettingsIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
    if let legacy = UserDefaults(suiteName: "com.footagefinder.macos") {
      for key in [enabledProvidersKey, downloadRootKey, "didFinishWelcome"]
      where UserDefaults.standard.object(forKey: key) == nil {
        if let value = legacy.object(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
      }
    }
    UserDefaults.standard.set(true, forKey: migrationKey)
  }

  static var enabledProviders: Set<ProviderID> {
    get {
      guard let values = UserDefaults.standard.array(forKey: enabledProvidersKey) as? [String]
      else { return Set(ProviderID.allCases) }
      return Set(values.compactMap(ProviderID.init(rawValue:)))
    }
    set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: enabledProvidersKey) }
  }

  static var downloadRootURL: URL {
    get {
      if let path = UserDefaults.standard.string(forKey: downloadRootKey), !path.isEmpty {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
      return PlatformPaths.defaultDownloadRoot
    }
    set { UserDefaults.standard.set(newValue.path, forKey: downloadRootKey) }
  }
}
