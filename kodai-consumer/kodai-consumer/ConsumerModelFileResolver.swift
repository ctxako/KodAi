//
//  ConsumerModelFileResolver.swift
//  kodai-consumer
//
//  Resolves the on-device GGUF for the runtime: prefers a previously
//  downloaded copy in Application Support, falls back to a model bundled
//  in the app. Mirrors the resolver used by the educational iOS app.
//
//  Download-on-first-run is wired via `LocalModelConfiguration.downloadURL`
//  (LFM2.5-1.2B-Instruct-Q4_K_M from LiquidAI on HuggingFace); the runtime
//  calls `ModelDownloader.ensureDownloaded` before this resolver runs, so the
//  downloaded copy is found here on subsequent launches. Bundling the GGUF
//  remains a fallback if a model ships inside the app.
//

import Foundation
import KodaiKernel
import KodaiRuntime

nonisolated struct ConsumerModelFileResolver: ModelFileResolver, Sendable {
    private let log = KodaiLog(category: "ModelResolver")
    private let modelDownloader: ModelDownloader

    nonisolated init(modelDownloader: ModelDownloader = ModelDownloader()) {
        self.modelDownloader = modelDownloader
    }

    nonisolated func resolve(configuration: LocalModelConfiguration) throws -> URL {
        let localURL = try modelDownloader.localModelURL(fileName: configuration.expectedModelFileName)
        if FileManager.default.fileExists(atPath: localURL.path) {
            log.event("resolver selected downloaded model=\(configuration.expectedModelFileName)")
            return localURL
        }

        if let bundledURL = Bundle.main.url(
            forResource: configuration.modelResourceName,
            withExtension: configuration.modelResourceExtension
        ) {
            log.event("resolver selected bundled model=\(configuration.expectedModelFileName)")
            return bundledURL
        }

        log.event("model not found name=\(configuration.expectedModelFileName)")
        throw LocalModelRuntimeError.modelFileMissing(expectedFileName: configuration.expectedModelFileName)
    }
}
