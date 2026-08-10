import Foundation

enum AppSettings {
    static let enabledProvidersKey = "enabledProviders"
    static let downloadRootKey = "downloadRoot"

    static var enabledProviders: Set<ProviderID> {
        get {
            guard let values = UserDefaults.standard.array(forKey: enabledProvidersKey) as? [String] else { return Set(ProviderID.allCases) }
            return Set(values.compactMap(ProviderID.init(rawValue:)))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: enabledProvidersKey) }
    }

    static var downloadRootURL: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: downloadRootKey), !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
            let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            return movies.appendingPathComponent("FootageFinder", isDirectory: true)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: downloadRootKey) }
    }
}
