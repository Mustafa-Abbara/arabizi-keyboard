// swift-tools-version: 6.0
// The input method executable. scripts/build_ime.sh wraps it into ArabiziIME.app (ADR 0013).
import PackageDescription

let package = Package(
    name: "ArabiziIME",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/ArabiziCore"),
    ],
    targets: [
        .executableTarget(
            name: "ArabiziIME",
            dependencies: ["ArabiziCore"],
            linkerSettings: [.linkedFramework("InputMethodKit")]
        ),
    ]
)
