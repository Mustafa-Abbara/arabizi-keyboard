// swift-tools-version: 6.0
// The sandboxed engine service (roadmap P5 step 5, ADR 0020). scripts/build_ime.sh wraps the executable into
// ArabiziIME.app/Contents/XPCServices/ArabiziEngineXPC.xpc with llama.framework, the model and the config files.
import PackageDescription

let package = Package(
    name: "ArabiziEngineXPC",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/ArabiziContracts"),
        .package(path: "../../Packages/ArabiziCore"),
        .package(path: "../../Packages/ArabiziEngine"),
    ],
    targets: [
        .executableTarget(
            name: "ArabiziEngineXPC",
            dependencies: [
                .product(name: "ArabiziContracts", package: "ArabiziContracts"),
                .product(name: "ArabiziCore", package: "ArabiziCore"),
                .product(name: "ArabiziEngine", package: "ArabiziEngine"),
            ],
            // llama.framework sits in the service bundle's Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
