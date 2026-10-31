// swift-tools-version:6.2
import PackageDescription

// ProtlyCore: platform-free keyboard logic (no UIKit). Builds and tests on Linux.
let package = Package(
    name: "ProtlyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProtlyCore", targets: ["ProtlyCore"]),
    ],
    targets: [
        .target(
            name: "ProtlyCore",
            resources: [
                .copy("Resources/en_50k.txt"), .copy("Resources/ko_50k.txt"),
                .copy("Resources/keyboard-prompt.txt"),  // synced from ios/ by scripts/sync-ios-app.mjs
            ]
        ),
        .executableTarget(name: "protly-eval", dependencies: ["ProtlyCore"]),
        .testTarget(name: "ProtlyCoreTests", dependencies: ["ProtlyCore"]),
    ]
)
