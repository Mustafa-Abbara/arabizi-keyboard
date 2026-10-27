// swift-tools-version: 6.0
// Pure Swift logic for the keyboard: no AppKit, no InputMethodKit, so it is unit-tested with `swift test`.
import PackageDescription

let package = Package(
    name: "ArabiziCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArabiziCore", targets: ["ArabiziCore"]),
        .executable(name: "arabizi-suggestions-report", targets: ["arabizi-suggestions-report"]),
    ],
    targets: [
        .target(name: "ArabiziCore"),
        .executableTarget(name: "arabizi-suggestions-report", dependencies: ["ArabiziCore"]),
        // Fixtures are read from the source tree (like data/rules), not bundled.
        .testTarget(name: "ArabiziCoreTests", dependencies: ["ArabiziCore"], exclude: ["Fixtures"]),
    ]
)
