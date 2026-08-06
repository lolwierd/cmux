// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSSHConfig",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSSHConfig",
            targets: ["CmuxSSHConfig"]
        ),
    ],
    targets: [
        .target(
            name: "CmuxSSHConfig",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxSSHConfigTests",
            dependencies: ["CmuxSSHConfig"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
