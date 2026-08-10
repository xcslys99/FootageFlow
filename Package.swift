// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FootageFinder",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FootageFinder", targets: ["FootageFinder"])
    ],
    targets: [
        .executableTarget(
            name: "FootageFinder",
            path: "Sources/FootageFinder"
        ),
        .testTarget(
            name: "FootageFinderTests",
            dependencies: ["FootageFinder"],
            path: "Tests/FootageFinderTests",
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)
