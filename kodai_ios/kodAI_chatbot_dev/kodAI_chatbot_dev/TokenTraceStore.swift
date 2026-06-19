//
//  TokenTraceStore.swift
//  kodAI_chatbot_dev
//
//  Persists per-response token traces so the Thread Atlas and Generation Trace
//  survive relaunch. Chats themselves live in ChatStore (JSON); traces are kept
//  in a parallel per-session file here, loaded lazily when a chat is opened so
//  neither memory nor the main sessions file is bloated by them.
//
//  The on-disk form is already "reduced": TokenSnapshot only ever held the top-k
//  alternatives plus three scalars (no full vocabulary), so a whole response is
//  only tens of KB. We additionally cap how many recent responses are persisted
//  per chat so a long conversation's trace file can't grow without bound.
//

import Foundation

/// One analyzed token decision in persistable form (1:1 with TokenSnapshot's payload).
nonisolated struct TokenTraceRecord: Codable, Sendable {
    struct Alternative: Codable, Sendable {
        let tokenID: Int32
        let text: String
        let probability: Float
        let isSelected: Bool
    }
    let step: Int
    let text: String
    let selectedProbability: Float
    let entropy: Float
    let margin: Float
    let alternatives: [Alternative]
}

/// Versioned container so the schema can evolve without breaking old files.
private struct SessionTraceFile: Codable, Sendable {
    var version: Int = 1
    var traces: [String: [TokenTraceRecord]]   // message UUID string → records
}

actor TokenTraceStore {
    /// Persist at most the most-recent responses per chat (older traces are dropped).
    static let maxResponsesPerSession = 25

    private let directoryURL: URL
    private let log = AppLog(category: "TokenTraceStore")

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "kodAI_chatbot_dev"
        directoryURL = support
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Traces", isDirectory: true)
    }

    private func fileURL(for sessionID: UUID) -> URL {
        directoryURL.appendingPathComponent("Traces-\(sessionID.uuidString).json")
    }

    func load(sessionID: UUID) -> [String: [TokenTraceRecord]] {
        let url = fileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SessionTraceFile.self, from: data).traces
        } catch {
            log.event("failed to load traces: \(error.localizedDescription)")
            return [:]
        }
    }

    func save(_ traces: [String: [TokenTraceRecord]], sessionID: UUID) {
        guard !traces.isEmpty else {
            delete(sessionID: sessionID)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SessionTraceFile(traces: traces))
            try data.write(to: fileURL(for: sessionID), options: [.atomic])
        } catch {
            log.event("failed to save traces: \(error.localizedDescription)")
        }
    }

    func delete(sessionID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: sessionID))
    }
}
