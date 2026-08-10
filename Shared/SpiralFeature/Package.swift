// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpiralFeature",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SpiralFeature", targets: ["SpiralFeature"])
    ],
    dependencies: [
        .package(path: "../SpiralCore")
    ],
    targets: [
        .target(
            name: "SpiralFeature",
            dependencies: ["SpiralCore"]
        ),
        .testTarget(
            name: "SpiralFeatureTests",
            dependencies: ["SpiralFeature", "SpiralCore"]
        )
    ]
)
