// swift-tools-version: 6.0
import PackageDescription

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
      path: "Sources/FootageFlow"
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
