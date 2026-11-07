// swift-tools-version: 6.0
// The conversion engine (roadmap P5): protected spans, the fine-tuned model with a deadline, output checks and the
// rule fallback, behind the ADR 0018 contracts. `arabizi-cli` runs it over JSON lines for the evaluation harness;
// the sandboxed XPC service hosts the same library for the keyboard. On Windows, `harfi-engine` hosts it as its own
// process for the Windows keyboard, on a named pipe (ADR 0032).
import PackageDescription

// CryptoKit's API for Windows and Linux (ADR 0032); Apple platforms keep CryptoKit and never link it.
let crypto: Target.Dependency = .product(name: "Crypto", package: "swift-crypto",
                                         condition: .when(platforms: [.windows, .linux]))

var products: [Product] = [
    .library(name: "ArabiziEngine", targets: ["ArabiziEngine"]),
    .executable(name: "arabizi-cli", targets: ["arabizi-cli"]),
]
var targets: [Target] = [
    .target(name: "ArabiziEngine", dependencies: [
        .product(name: "ArabiziContracts", package: "ArabiziContracts"),
        .product(name: "ArabiziCore", package: "ArabiziCore"),
        .product(name: "ArabiziLLM", package: "ArabiziLLM"),
        crypto,
    ]),
    .executableTarget(name: "arabizi-cli", dependencies: [
        "ArabiziEngine",
        .product(name: "ArabiziContracts", package: "ArabiziContracts"),
        .product(name: "ArabiziCore", package: "ArabiziCore"),
    ]),
    .testTarget(name: "ArabiziEngineTests", dependencies: [
        "ArabiziEngine",
        .product(name: "ArabiziContracts", package: "ArabiziContracts"),
        .product(name: "ArabiziCore", package: "ArabiziCore"),
        .product(name: "ArabiziLLM", package: "ArabiziLLM"),
    ]),
]
#if os(Windows)
products.append(.executable(name: "harfi-engine", targets: ["harfi-engine"]))
targets.append(.executableTarget(name: "harfi-engine", dependencies: [
    "ArabiziEngine",
    .product(name: "ArabiziContracts", package: "ArabiziContracts"),
    .product(name: "ArabiziCore", package: "ArabiziCore"),
]))
#endif

let package = Package(
    name: "ArabiziEngine",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(path: "../ArabiziContracts"),
        .package(path: "../ArabiziCore"),
        .package(path: "../ArabiziLLM"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "4.0.0"),
    ],
    targets: targets
)
