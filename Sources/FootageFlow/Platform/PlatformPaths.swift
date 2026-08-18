import Foundation

enum PlatformPaths {
  static var applicationData: URL {
    // The normal application never sets this. It provides an isolated data
    // root for automated acceptance tests and lets both desktop platforms
    // verify import/export flows without touching a creator's real projects.
    if let override = Bundle.main.object(forInfoDictionaryKey: "FootageFlowApplicationDataRoot")
      as? String,
      !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return URL(fileURLWithPath: override, isDirectory: true)
    }
    if let argumentIndex = CommandLine.arguments.firstIndex(of: "--application-data-root"),
      CommandLine.arguments.indices.contains(argumentIndex + 1)
    {
      return URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1], isDirectory: true)
    }
    if let override = ProcessInfo.processInfo.environment["FOOTAGEFLOW_APPLICATION_DATA"],
      !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return URL(fileURLWithPath: override, isDirectory: true)
    }
    #if os(Windows)
      let base =
        ProcessInfo.processInfo.environment["LOCALAPPDATA"].map {
          URL(fileURLWithPath: $0, isDirectory: true)
        }
        ?? FileManager.default.temporaryDirectory
      return base.appendingPathComponent("FootageFlow", isDirectory: true)
    #else
      let base =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      return base.appendingPathComponent("FootageFlow", isDirectory: true)
    #endif
  }

  static var cache: URL {
    #if os(Windows)
      return applicationData.appendingPathComponent("Cache", isDirectory: true)
    #else
      let base =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      return base.appendingPathComponent("FootageFlow", isDirectory: true)
    #endif
  }

  static var defaultDownloadRoot: URL {
    #if os(Windows)
      let profile =
        ProcessInfo.processInfo.environment["USERPROFILE"].map {
          URL(fileURLWithPath: $0, isDirectory: true)
        }
        ?? FileManager.default.temporaryDirectory
      return profile.appendingPathComponent("Videos/FootageFlow", isDirectory: true)
    #else
      let movies =
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      return movies.appendingPathComponent("FootageFlow", isDirectory: true)
    #endif
  }
}
