// swift-tools-version: 6.0
import PackageDescription

// xtool app package: the container app and the keyboard extension. Logic lives in ProtlyCore.
let package = Package(
    name: "Protly",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Protly", targets: ["Protly"]),
        .library(name: "ProtlyKeyboard", targets: ["ProtlyKeyboard"]),
    ],
    dependencies: [
        .package(path: "ProtlyCore"),
    ],
    targets: [
        .target(name: "Protly"),
        .target(
            name: "ProtlyKeyboard",
            dependencies: [.product(name: "ProtlyCore", package: "ProtlyCore")],
            // xtool issues #313/#379: keep the principal class from being dead-stripped.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_OBJC_CLASS_$_KeyboardViewController"])]
        ),
    ]
)
