// swift-tools-version: 6.0
import PackageDescription

#if os(Windows)
  let platformExcludedSources = [
    "App",
    "Persistence/DataStore.swift",
    "Services/DownloadManager.swift",
    "Services/PreviewWindowManager.swift",
    "Services/SearchCache.swift",
    "Utilities/AcceptanceRunner.swift",
    "Utilities/LiveSmokeRunner.swift",
    "Utilities/SelfTestRunner.swift",
    "ViewModels",
    "Views",
  ]
#else
  let platformExcludedSources: [String] = []
#endif

let package = Package(
  name: "FootageFlow",
  defaultLocalization: "en",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "FootageFlow", targets: ["FootageFlow"])
  ],
  targets: [
    .executableTarget(
      name: "FootageFlow",
      path: "Sources/FootageFlow",
      exclude: platformExcludedSources
    ),
    .testTarget(
      name: "FootageFlowTests",
      dependencies: ["FootageFlow"],
      path: "Tests/FootageFlowTests",
      resources: [.process("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v5]
)
