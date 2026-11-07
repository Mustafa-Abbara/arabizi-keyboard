// swift-tools-version: 6.0
// Pure Swift logic for the keyboard: no AppKit, no InputMethodKit, so it is unit-tested with `swift test`.
import PackageDescription

let crypto: Target.Dependency = .product(name: "Crypto", package: "swift-crypto",
                                         condition: .when(platforms: [.windows, .linux]))

let package = Package(
    name: "ArabiziCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziCore", targets: ["ArabiziCore"]),
        .executable(name: "arabizi-suggestions-report", targets: ["arabizi-suggestions-report"]),
        // The user's learned words, until the Windows keyboard has a settings window (ADR 0033).
        .executable(name: "harfi-words", targets: ["harfi-words"]),
        // The core as a C library for the Windows keyboard (ADR 0032): HarfiCoreC.dll on Windows.
        .library(name: "HarfiCoreC", type: .dynamic, targets: ["HarfiCoreC"]),
    ],
    dependencies: [
        // CryptoKit's API for Windows and Linux (ADR 0032); Apple platforms keep CryptoKit and never link it.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "4.0.0"),
        // The engine's messages, for HarfiCoreC's link to harfi-engine on Windows.
        .package(path: "../ArabiziContracts"),
    ],
    targets: [
        .target(name: "ArabiziCore", dependencies: [crypto]),
        .executableTarget(name: "arabizi-suggestions-report", dependencies: ["ArabiziCore"]),
        .executableTarget(name: "harfi-words", dependencies: ["ArabiziCore"]),
        .target(name: "HarfiCoreC", dependencies: [
            "ArabiziCore", .product(name: "ArabiziContracts", package: "ArabiziContracts"),
        ]),
        .testTarget(name: "HarfiCoreCTests", dependencies: ["HarfiCoreC"]),
        // Fixtures are read from the source tree (like data/rules), not bundled.
        .testTarget(name: "ArabiziCoreTests", dependencies: ["ArabiziCore", crypto], exclude: ["Fixtures"]),
    ]
)
