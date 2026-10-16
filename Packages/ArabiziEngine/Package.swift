// swift-tools-version: 6.0
// The conversion engine (roadmap P5): protected spans, the fine-tuned model with a deadline, output checks and the
// rule fallback, behind the ADR 0018 contracts. `arabizi-cli` runs it over JSON lines for the evaluation harness;
// the sandboxed XPC service hosts the same library for the keyboard.
import PackageDescription

let package = Package(
    name: "ArabiziEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziEngine", targets: ["ArabiziEngine"]),
        .executable(name: "arabizi-cli", targets: ["arabizi-cli"]),
    ],
    dependencies: [
        .package(path: "../ArabiziContracts"),
        .package(path: "../ArabiziCore"),
        .package(path: "../ArabiziLLM"),
    ],
    targets: [
        .target(name: "ArabiziEngine", dependencies: [
            .product(name: "ArabiziContracts", package: "ArabiziContracts"),
            .product(name: "ArabiziCore", package: "ArabiziCore"),
            .product(name: "ArabiziLLM", package: "ArabiziLLM"),
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
)
