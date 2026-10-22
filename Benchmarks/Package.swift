// swift-tools-version:6.0
// A separate package so the benchmark is never built as part of ZDTaffy for iOS.
// Run: cd Benchmarks && swift run -c release ZDLayoutBench
import PackageDescription

let package = Package(
    name: "ZDLayoutBench",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(
            name: "ZDLayoutBench",
            dependencies: [
                .product(name: "ZDLayoutCore", package: "ZDTaffySwift"),
                .product(name: "ZDTaffy", package: "ZDTaffySwift"),
            ],
            path: "ZDLayoutBench"
        ),
    ]
)
