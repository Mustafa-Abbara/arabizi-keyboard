// swift-tools-version: 6.0
// Pure Swift logic for the keyboard: no AppKit, no InputMethodKit, so it is unit-tested with `swift test`.
import PackageDescription

let package = Package(
    name: "ArabiziCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziCore", targets: ["ArabiziCore"]),
    ],
    targets: [
        .target(name: "ArabiziCore"),
        .testTarget(name: "ArabiziCoreTests", dependencies: ["ArabiziCore"]),
    ]
)
