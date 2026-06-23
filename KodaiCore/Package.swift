// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KodaiCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "KodaiCore", targets: ["KodaiCore"]),
        .library(name: "KodaiKernel", targets: ["KodaiKernel"]),
        .library(name: "KodaiPersistence", targets: ["KodaiPersistence"]),
        .library(name: "KodaiRuntime", targets: ["KodaiRuntime"]),
        .executable(name: "kodai-bench", targets: ["KodAiBench"])
    ],
    dependencies: [
        .package(path: "../kodai_ios/LlamaCPP")
    ],
    targets: [
        // Foundation-only shared logic and value types.
        .target(name: "KodaiKernel"),
        // llama.cpp-backed runtime actors for on-device inference.
        .target(name: "KodaiRuntime", dependencies: [
            "KodaiKernel",
            .product(name: "llama", package: "LlamaCPP")
        ]),
        // SwiftData-backed models and ledger write paths.
        .target(name: "KodaiPersistence", dependencies: ["KodaiKernel"]),
        // Compatibility umbrella re-exporting all targets.
        .target(name: "KodaiCore", dependencies: ["KodaiKernel", "KodaiPersistence", "KodaiRuntime"]),
        .executableTarget(
            name: "KodAiBench",
            dependencies: ["KodaiKernel", "KodaiRuntime"]
        ),
        .testTarget(
            name: "KodaiCoreTests",
            dependencies: ["KodaiCore", "KodaiKernel", "KodaiPersistence"]
        )
    ]
)
