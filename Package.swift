// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SBBender",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SBBender",
            targets: ["SBBender"]
        ),
        .executable(
            name: "SwarmDemo",
            targets: ["SwarmDemo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/apple/containerization.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "SBBender",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Containerization", package: "containerization", condition: .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Translation"),
                .linkedFramework("EventKit"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(
            name: "SwarmDemo",
            dependencies: ["SBBender"]
        ),
        .executableTarget(
            name: "SBBenderApp",
            dependencies: [
                "SBBender",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/SBBenderApp"
        ),
        .executableTarget(
            name: "RealIntegrationTests",
            dependencies: ["SBBender"],
            path: "Sources/RealIntegrationTests"
        ),
        .testTarget(
            name: "SBBenderTests",
            dependencies: ["SBBender"]
        ),
    ]
)
