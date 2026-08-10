import Foundation

enum AppSettings {
  static let enabledProvidersKey = "enabledProviders"
  static let downloadRootKey = "downloadRoot"
  private static let migrationKey = "didMigrateFootageFinderSettings"
  private static let providerCatalogV3Key = "didEnableDiscoveryProvidersV3"
  private static let providerCatalogV5Key = "didEnableSearchExpansionProvidersV5"

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
      else { return Set(ProviderID.searchCases) }
      var result = Set(values.compactMap(ProviderID.init(rawValue:)))
      if !UserDefaults.standard.bool(forKey: providerCatalogV3Key) {
        result.formUnion([.nasa, .libraryOfCongress, .nationalArchives, .europeana])
        UserDefaults.standard.set(result.map(\.rawValue), forKey: enabledProvidersKey)
        UserDefaults.standard.set(true, forKey: providerCatalogV3Key)
      }
      if !UserDefaults.standard.bool(forKey: providerCatalogV5Key) {
        result.formUnion([.peertube, .videvo, .videezy, .mixkit, .coverr, .vimeo])
        UserDefaults.standard.set(result.map(\.rawValue), forKey: enabledProvidersKey)
        UserDefaults.standard.set(true, forKey: providerCatalogV5Key)
      }
      return result
    }
    set {
      UserDefaults.standard.set(newValue.map(\.rawValue), forKey: enabledProvidersKey)
      UserDefaults.standard.set(true, forKey: providerCatalogV3Key)
      UserDefaults.standard.set(true, forKey: providerCatalogV5Key)
    }
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
