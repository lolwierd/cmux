// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSSHServersUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSSHServersUI",
            targets: ["CmuxSSHServersUI"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxSSHServers"),
    ],
    targets: [
        .target(
            name: "CmuxSSHServersUI",
            dependencies: [
                .product(name: "CmuxSSHServers", package: "CmuxSSHServers"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxSSHServersUITests",
            dependencies: ["CmuxSSHServersUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
