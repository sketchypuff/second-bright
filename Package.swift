// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SecondBright",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SecondBrightCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SecondBright",
            dependencies: ["SecondBrightCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Deliberately an executable rather than a .testTarget: SwiftPM's macOS
        // test bundles need full Xcode for test discovery, and this machine has
        // only Command Line Tools, where `swift test` silently finds nothing.
        // As an executable the same checks actually run. Run with `make test`.
        .executableTarget(
            name: "SecondBrightChecks",
            dependencies: ["SecondBrightCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
