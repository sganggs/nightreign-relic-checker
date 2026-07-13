// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NightreignRelicChecker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "RelicCore", targets: ["RelicCore"]),
        .executable(name: "NightreignRelicChecker", targets: ["NightreignRelicChecker"])
    ],
    targets: [
        .target(name: "RelicCore"),
        .executableTarget(
            name: "NightreignRelicChecker",
            dependencies: ["RelicCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "RelicCoreChecks",
            dependencies: ["RelicCore"]
        )
    ]
)
