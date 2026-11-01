// swift-tools-version: 6.0
// The input method executable. scripts/build_ime.sh wraps it into ArabiziIME.app (ADR 0013).
import PackageDescription

let package = Package(
    name: "ArabiziIME",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/ArabiziCore"),
        .package(path: "../../Packages/ArabiziContracts"),
    ],
    targets: [
        .executableTarget(
            name: "ArabiziIME",
            dependencies: [
                .product(name: "ArabiziCore", package: "ArabiziCore"),
                .product(name: "ArabiziContracts", package: "ArabiziContracts"),
            ],
            linkerSettings: [.linkedFramework("InputMethodKit")]
        ),
        // Registers the installed app with macOS (scripts/install_ime.sh, scripts/install_harfi.sh).
        .executableTarget(name: "harfi-register", linkerSettings: [.linkedFramework("Carbon")]),
        // Diagnostic: reaches the engine service like the keyboard does (it must sit in the app's Contents/MacOS).
        .executableTarget(
            name: "arabizi-engine-check",
            dependencies: [.product(name: "ArabiziContracts", package: "ArabiziContracts")]
        ),
    ]
)
