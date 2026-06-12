// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KodaiCore",
    platforms: [
        .macOS(.v26),
        .iOS(.v18)
    ],
    products: [
        .library(name: "KodaiCore", targets: ["KodaiCore"]),
        .library(name: "KodaiKernel", targets: ["KodaiKernel"]),
        .library(name: "KodaiPersistence", targets: ["KodaiPersistence"])
    ],
    targets: [
        // Foundation-only shared logic and value types.
        .target(name: "KodaiKernel"),
        // SwiftData-backed models and ledger write paths.
        .target(name: "KodaiPersistence", dependencies: ["KodaiKernel"]),
        // Compatibility umbrella re-exporting both targets.
        .target(name: "KodaiCore", dependencies: ["KodaiKernel", "KodaiPersistence"]),
        .testTarget(
            name: "KodaiCoreTests",
            dependencies: ["KodaiCore", "KodaiKernel", "KodaiPersistence"]
        )
    ]
)
