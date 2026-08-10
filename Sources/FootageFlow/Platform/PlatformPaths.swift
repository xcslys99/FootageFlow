import Foundation

enum PlatformPaths {
    static var applicationData: URL {
        #if os(Windows)
        let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FootageFlow", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FootageFlow", isDirectory: true)
        #endif
    }

    static var cache: URL {
        #if os(Windows)
        return applicationData.appendingPathComponent("Cache", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FootageFlow", isDirectory: true)
        #endif
    }

    static var defaultDownloadRoot: URL {
        #if os(Windows)
        let profile = ProcessInfo.processInfo.environment["USERPROFILE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return profile.appendingPathComponent("Videos/FootageFlow", isDirectory: true)
        #else
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return movies.appendingPathComponent("FootageFlow", isDirectory: true)
        #endif
    }
}
