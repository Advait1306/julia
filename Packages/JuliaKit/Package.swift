// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JuliaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JuliaKit", targets: ["JuliaKit"]),
        .executable(name: "julia-smoke", targets: ["JuliaSmoke"])
    ],
    targets: [
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11026/llama-b11026-xcframework.zip",
            checksum: "264fbf2acd7ad1d7bf565cf4bf5b04ffad18172832304de7360516714cec375c"
        ),
        .target(name: "JuliaKit", dependencies: ["LlamaFramework"], linkerSettings: [
            .linkedFramework("EventKit"), .linkedFramework("Contacts"),
            .linkedFramework("PDFKit"), .linkedFramework("Vision")
        ]),
        .executableTarget(name: "JuliaSmoke", dependencies: ["JuliaKit"]),
        .testTarget(name: "JuliaKitTests", dependencies: ["JuliaKit"], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])
        ])
    ]
)
