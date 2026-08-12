// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
  let commandLineToolsTestLibraries =
    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
  let localTestingLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
      "-L", commandLineToolsTestLibraries,
      "-Xlinker", "-rpath", "-Xlinker", commandLineToolsTestLibraries,
    ])
  ]
#else
  let localTestingLinkerSettings: [LinkerSetting] = []
#endif

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
  dependencies: [
    // macOS 15 GitHub runners currently ship Swift 6.1.2. Pin the matching
    // official runtime so tests execute consistently on Swift 6.1 through 6.3.
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.1.2")
  ],
  targets: [
    .executableTarget(
      name: "FootageFlow",
      path: "Sources/FootageFlow",
      exclude: platformExcludedSources
    ),
    .testTarget(
      name: "FootageFlowTests",
      dependencies: [
        "FootageFlow",
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/FootageFlowTests",
      resources: [.process("Fixtures")],
      linkerSettings: localTestingLinkerSettings
    ),
  ],
  swiftLanguageModes: [.v5]
)
