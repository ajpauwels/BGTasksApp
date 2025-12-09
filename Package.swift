// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BGTasks",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "BGTasks",
            targets: ["BGTasks"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/rwbutler/Connectivity", from: "8.0.1")
    ],
    targets: [
        .target(
            name: "BGTasks",
            dependencies: [
                "Connectivity"
            ]
        )
    ]
)
