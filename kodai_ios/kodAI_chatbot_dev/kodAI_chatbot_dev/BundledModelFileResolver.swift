//
//  BundledModelFileResolver.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/6/26.
//

import Foundation

nonisolated struct BundledModelFileResolver: Sendable {
    private let log = AppLog(category: "ModelResolver")
    private let modelDownloader: ModelDownloader

    nonisolated init(modelDownloader: ModelDownloader = ModelDownloader()) {
        self.modelDownloader = modelDownloader
    }

    nonisolated func resolve(configuration: LocalModelConfiguration) throws -> URL {
        let localURL = try modelDownloader.localModelURL(fileName: configuration.expectedModelFileName)
        log.event("local model path=\(localURL.path)")

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
