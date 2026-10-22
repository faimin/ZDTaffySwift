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
