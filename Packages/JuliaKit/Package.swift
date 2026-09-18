// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JuliaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JuliaKit", targets: ["JuliaKit"]),
        .executable(name: "julia-smoke", targets: ["JuliaSmoke"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.0")
    ],
    targets: [
        .target(name: "JuliaKit", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers")
        ], linkerSettings: [
            .linkedFramework("EventKit"), .linkedFramework("Contacts"),
            .linkedFramework("PDFKit"), .linkedFramework("Vision")
        ]),
        .executableTarget(name: "JuliaSmoke", dependencies: ["JuliaKit"]),
        .testTarget(name: "JuliaKitTests", dependencies: ["JuliaKit"])
    ]
)
