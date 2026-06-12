// swift-tools-version:5.9
// Wraps the official prebuilt llama.xcframework from
// https://github.com/ggml-org/llama.cpp/releases/tag/b5200
// (llama-b5200-xcframework.zip). Upstream dropped SwiftPM source builds
// in favor of this XCFramework, so we vendor it behind the same
// `llama` product name the app has always linked.

import PackageDescription

let package = Package(
    name: "LlamaCPP",
    products: [
        .library(name: "llama", targets: ["llama"])
    ],
    targets: [
        .binaryTarget(name: "llama", path: "llama.xcframework")
    ]
)
