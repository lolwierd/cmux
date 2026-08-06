// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSSHServers",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSSHServers",
            targets: ["CmuxSSHServers"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxSSHConfig"),
    ],
    targets: [
        .target(
            name: "CmuxSSHServers",
            dependencies: [
                .product(name: "CmuxSSHConfig", package: "CmuxSSHConfig"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxSSHServersTests",
            dependencies: ["CmuxSSHServers"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
