// swift-tools-version: 6.0
/*Copyright (c) 2026 Gareth Simpson and Zachary Schneirov. All rights reserved.
    This file is part of Spiral, a fork of Notational Velocity.

    Spiral is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Spiral is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Spiral.  If not, see <http://www.gnu.org/licenses/>. */

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
        .target(
            name: "SpiralCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "SpiralCoreTests",
            dependencies: ["SpiralCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
