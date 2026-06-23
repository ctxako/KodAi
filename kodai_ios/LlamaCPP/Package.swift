// swift-tools-version:5.9
// Wraps the official prebuilt llama.xcframework from
// https://github.com/ggml-org/llama.cpp/releases/tag/b9775
// (llama-b9775-xcframework.zip). Bumped from b5200 to gain `lfm2`
// architecture support for the LFM2.5 production model.
// Upstream dropped SwiftPM source builds
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
