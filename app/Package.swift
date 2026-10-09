// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Paint",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Paint",
            path: "Sources/Paint",
            resources: [.process("Resources")],
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))]
        )
    ],
    swiftLanguageVersions: [.v5]
)
