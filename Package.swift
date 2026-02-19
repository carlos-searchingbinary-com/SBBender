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
        .library(
            name: "SBBenderCore",
            targets: ["SBBenderCore"]
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
        .package(url: "https://github.com/duckdb/duckdb-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        // MARK: - Core (lightweight, no heavy deps)
        .target(
            name: "SBBenderCore",
            linkerSettings: [
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Translation"),
                .linkedFramework("EventKit"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),

        // MARK: - Full runtime (re-exports Core)
        .target(
            name: "SBBender",
            dependencies: [
                "SBBenderCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Containerization", package: "containerization", condition: .when(platforms: [.macOS])),
                .product(name: "DuckDB", package: "duckdb-swift"),
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
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SBBenderApp",
            exclude: ["Info.plist", "SBBenderApp.entitlements"],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ]
        ),
        .executableTarget(
            name: "RealIntegrationTests",
            dependencies: ["SBBender"],
            path: "Sources/RealIntegrationTests"
        ),

        // MARK: - Tests
        .testTarget(
            name: "SBBenderCoreTests",
            dependencies: ["SBBenderCore"]
        ),
        .testTarget(
            name: "SBBenderTests",
            dependencies: [
                "SBBender",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
