// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpiralCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SpiralCore", targets: ["SpiralCore"])
    ],
    targets: [
        .target(name: "SpiralCore"),
        .testTarget(
            name: "SpiralCoreTests",
            dependencies: ["SpiralCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
