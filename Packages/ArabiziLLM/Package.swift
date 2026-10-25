// swift-tools-version: 6.0
// The model runner for the engine (roadmap P5 step 4, ADR 0017): llama.cpp's official XCFramework, pinned to
// release b11429 = commit d81235049, the same build as Homebrew's llama-server and train/export_gguf.sh.
// Upgrading llama.cpp means changing all three together.
import PackageDescription

let package = Package(
    name: "ArabiziLLM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziLLM", targets: ["ArabiziLLM"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11429/llama-b11429-xcframework.zip",
            checksum: "e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174"
        ),
        .target(name: "ArabiziLLM", dependencies: ["llama"]),
        .testTarget(name: "ArabiziLLMTests", dependencies: ["ArabiziLLM"]),
    ]
)
