import Foundation

enum AppSettings {
  static let enabledProvidersKey = "enabledProviders"
  static let downloadRootKey = "downloadRoot"
  static let smartExpansionKey = "smartSearchExpansionEnabled"
  static let clipboardDetectionKey = "clipboardMediaLinkDetectionEnabled"
  private static let migrationKey = "didMigrateFootageFinderSettings"
  private static let providerCatalogV3Key = "didEnableDiscoveryProvidersV3"
  private static let providerCatalogV5Key = "didEnableSearchExpansionProvidersV5"
  private static let providerCatalogV6Key = "didEnableCreatorWorkflowProvidersV6"

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
      if !UserDefaults.standard.bool(forKey: providerCatalogV6Key) {
        result.formUnion([.openverse, .dailymotion])
        UserDefaults.standard.set(result.map(\.rawValue), forKey: enabledProvidersKey)
        UserDefaults.standard.set(true, forKey: providerCatalogV6Key)
      }
      return result
    }
    set {
      UserDefaults.standard.set(newValue.map(\.rawValue), forKey: enabledProvidersKey)
      UserDefaults.standard.set(true, forKey: providerCatalogV3Key)
      UserDefaults.standard.set(true, forKey: providerCatalogV5Key)
      UserDefaults.standard.set(true, forKey: providerCatalogV6Key)
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

  static var smartExpansionEnabled: Bool {
    get {
      UserDefaults.standard.object(forKey: smartExpansionKey) as? Bool ?? true
    }
    set { UserDefaults.standard.set(newValue, forKey: smartExpansionKey) }
  }

  static var clipboardDetectionEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: clipboardDetectionKey) }
    set { UserDefaults.standard.set(newValue, forKey: clipboardDetectionKey) }
  }
}
