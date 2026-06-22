// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenCodeConnect",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenCodeConnectCore", targets: ["OpenCodeConnectCore"]),
        .executable(name: "OpenCodeConnect", targets: ["OpenCodeConnect"]),
    ],
    targets: [
        .target(name: "OpenCodeConnectCore"),
        .executableTarget(
            name: "OpenCodeConnect",
            dependencies: ["OpenCodeConnectCore"]
        ),
        .testTarget(
            name: "OpenCodeConnectCoreTests",
            dependencies: ["OpenCodeConnectCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "OpenCodeConnectSmokeTests",
            dependencies: ["OpenCodeConnect", "OpenCodeConnectCore"]
        ),
    ]
)
