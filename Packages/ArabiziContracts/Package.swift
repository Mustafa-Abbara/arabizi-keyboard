// swift-tools-version: 6.0
// The messages between the keyboard, the engine and arabizi-cli (roadmap P5 step 1, docs/API_CONTRACTS.md).
// Mirrored as JSON Schemas in docs/schemas/; the tests check the examples there against these types.
import PackageDescription

let package = Package(
    name: "ArabiziContracts",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziContracts", targets: ["ArabiziContracts"]),
    ],
    targets: [
        .target(name: "ArabiziContracts"),
        .testTarget(name: "ArabiziContractsTests", dependencies: ["ArabiziContracts"]),
    ]
)
