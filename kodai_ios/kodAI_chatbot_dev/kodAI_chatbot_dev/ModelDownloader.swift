//
//  ModelDownloader.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/6/26.
//

import Foundation

nonisolated struct ModelDownloader: Sendable {
    nonisolated static let qwenDownloadURL = URL(
        string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    )!

    private let fileManager: FileManager
    private let log = AppLog(category: "ModelDownloader")

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ensureDownloaded(configuration: LocalModelConfiguration) async throws -> URL {
        let destinationURL = try localModelURL(fileName: configuration.expectedModelFileName)

        log.event("model download URL=\(Self.qwenDownloadURL.absoluteString)")
        log.event("local model path=\(destinationURL.path)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            log.event("local model already exists")
            return destinationURL
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        log.event("download started")
        let (temporaryURL, response) = try await URLSession.shared.download(from: Self.qwenDownloadURL)
        try Task.checkCancellation()

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            try? fileManager.removeItem(at: temporaryURL)
            throw URLError(.badServerResponse)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: temporaryURL)
            log.event("local model already exists")
            return destinationURL
        }

        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(destinationURL.lastPathComponent)", isDirectory: false)

        try fileManager.moveItem(at: temporaryURL, to: stagingURL)
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        log.event("temp file moved into Application Support")
        log.event("download completed")
        return destinationURL
    }

    nonisolated func localModelURL(fileName: String) throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupportURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
