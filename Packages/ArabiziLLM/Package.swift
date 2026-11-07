// swift-tools-version: 6.0
// The model runner for the engine (roadmap P5 step 4, ADR 0017): llama.cpp's official XCFramework, pinned to
// release b11429 = commit d81235049, the same build as Homebrew's llama-server and train/export_gguf.sh.
// Upgrading llama.cpp means changing all three together.
//
// On Windows (ADR 0032) the release has DLLs only, no import libraries or headers, so llama.cpp is built from source
// at the same release (Apps/HarfiWindows/README.md) and linked through a module map over its headers. Its folder is
// LLAMA_CPP_DIR, by default build/llama.cpp in the repository.
import PackageDescription

#if os(Windows)
let llamaDir = Context.environment["LLAMA_CPP_DIR"] ?? "\(Context.packageDirectory)/../../build/llama.cpp"
let llama: Target = .systemLibrary(name: "llama", path: "Sources/llama-windows")
let runner: Target = .target(
    name: "ArabiziLLM", dependencies: ["llama"],
    swiftSettings: [.unsafeFlags(["-Xcc", "-I\(llamaDir)/include", "-Xcc", "-I\(llamaDir)/ggml/include"])],
    linkerSettings: [.unsafeFlags(["-L\(llamaDir)/build/src/Release", "-L\(llamaDir)/build/ggml/src/Release"])])
#else
let llama: Target = .binaryTarget(
    name: "llama",
    url: "https://github.com/ggml-org/llama.cpp/releases/download/b11429/llama-b11429-xcframework.zip",
    checksum: "e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174"
)
let runner: Target = .target(name: "ArabiziLLM", dependencies: ["llama"])
#endif

let package = Package(
    name: "ArabiziLLM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziLLM", targets: ["ArabiziLLM"]),
    ],
    targets: [
        llama,
        runner,
        .testTarget(name: "ArabiziLLMTests", dependencies: ["ArabiziLLM"]),
    ]
)
