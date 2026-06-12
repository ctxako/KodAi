// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KodaiCore",
    platforms: [
        .macOS(.v26),
        .iOS(.v18)
    ],
    products: [
        .library(name: "KodaiCore", targets: ["KodaiCore"])
    ],
    targets: [
        .target(name: "KodaiCore"),
        .testTarget(
            name: "KodaiCoreTests",
            dependencies: ["KodaiCore"]
        )
    ]
)
