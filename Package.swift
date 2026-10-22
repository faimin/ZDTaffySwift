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
