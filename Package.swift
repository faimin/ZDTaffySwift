// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZDTaffy",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ZDTaffy", targets: ["ZDTaffy"]),
        .library(name: "ZDLayoutCore", targets: ["ZDLayoutCore"]),
        .library(name: "ZDLayout", targets: ["ZDLayout"]),
        .library(name: "ZDLayoutSwiftUI", targets: ["ZDLayoutSwiftUI"]),
        .library(name: "ZDLayoutAppKit", targets: ["ZDLayoutAppKit"]),
    ],
    targets: [
        // Produced by scripts/build-xcframework.sh.
        .binaryTarget(name: "ZDTaffyFFIBinary", path: "Artifacts/ZDTaffy.xcframework"),
        .target(
            name: "ZDTaffyFFI",
            dependencies: ["ZDTaffyFFIBinary"],
            path: "Sources/ZDTaffyFFI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ZDTaffy",
            dependencies: ["ZDTaffyFFI"],
            path: "Sources/ZDTaffy",
            // BoltFFI's generated code keeps its callback vtables in global `var`s, which Swift 6 rejects.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Platform-agnostic layout model and solver; deliberately free of UIKit.
        .target(
            name: "ZDLayoutCore",
            dependencies: ["ZDTaffy"],
            path: "Sources/ZDLayoutCore"
        ),
        // UIKit container, DSL adapters and cell configuration. Empty on platforms without UIKit.
        .target(
            name: "ZDLayout",
            dependencies: ["ZDLayoutCore"],
            path: "Sources/ZDLayout"
        ),
        // SwiftUI `Layout` adapter (iOS 16 / macOS 13+ APIs, guarded inside).
        .target(
            name: "ZDLayoutSwiftUI",
            dependencies: ["ZDLayoutCore"],
            path: "Sources/ZDLayoutSwiftUI"
        ),
        // AppKit container and NSView adapters. Empty on platforms without AppKit.
        .target(
            name: "ZDLayoutAppKit",
            dependencies: ["ZDLayoutCore"],
            path: "Sources/ZDLayoutAppKit"
        ),
        .testTarget(
            name: "ZDLayoutAppKitTests",
            dependencies: ["ZDLayoutAppKit"]
        ),
        .testTarget(
            name: "ZDLayoutSwiftUITests",
            dependencies: ["ZDLayoutSwiftUI"]
        ),
        .testTarget(
            name: "ZDLayoutTests",
            dependencies: ["ZDLayout"]
        ),
        .testTarget(
            name: "ZDLayoutCoreTests",
            dependencies: ["ZDLayoutCore"]
        ),
        .testTarget(
            name: "ZDTaffyTests",
            dependencies: ["ZDTaffy"]
        ),
    ]
)
