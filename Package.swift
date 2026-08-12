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
    // Pin the official runtime to the compiler version so tests also execute
    // on machines that have Command Line Tools without a full Xcode install.
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.3.2")
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
