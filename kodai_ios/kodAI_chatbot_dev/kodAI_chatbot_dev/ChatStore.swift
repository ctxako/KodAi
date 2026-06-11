//
//  ChatStore.swift
//  kodAI_chatbot_dev
//
//  Created by Codex on 6/7/26.
//

import Foundation

actor ChatStore {
    private let sessionsFileURL: URL
    private let streamsFileURL: URL
    private let promptSettingsFileURL: URL
    private let log = AppLog(category: "ChatStore")

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "kodAI_chatbot_dev"
        let directoryURL = supportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
        sessionsFileURL = directoryURL.appendingPathComponent("ChatSessions.json")
        streamsFileURL = directoryURL.appendingPathComponent("Streams.json")
        promptSettingsFileURL = directoryURL.appendingPathComponent("PromptSettings.json")
    }

    func loadSessions() async throws -> [ChatSession] {
        guard FileManager.default.fileExists(atPath: sessionsFileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: sessionsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ChatSession].self, from: data)
        } catch {
            log.event("failed to decode sessions: \(error.localizedDescription)")
            return []
        }
    }

    func saveSessions(_ sessions: [ChatSession]) async throws {
        let directoryURL = sessionsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsFileURL, options: [.atomic])
    }

    func loadStreams() async throws -> [Stream] {
        guard FileManager.default.fileExists(atPath: streamsFileURL.path) else {
            log.event("streams loaded count=0")
            return []
        }

        do {
            let data = try Data(contentsOf: streamsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let streams = try decoder.decode([Stream].self, from: data)
            log.event("streams loaded count=\(streams.count)")
            return streams
        } catch {
            log.event("failed to decode streams: \(error.localizedDescription)")
            return []
        }
    }

    func saveStreams(_ streams: [Stream]) async throws {
        let directoryURL = streamsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(streams)
        try data.write(to: streamsFileURL, options: [.atomic])
        log.event("streams saved count=\(streams.count)")
    }

    func loadPromptSettings() async throws -> ModelPromptSettings {
        guard FileManager.default.fileExists(atPath: promptSettingsFileURL.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: promptSettingsFileURL)
            return try JSONDecoder().decode(ModelPromptSettings.self, from: data)
        } catch {
            log.event("failed to decode prompt settings: \(error.localizedDescription)")
            return .default
        }
    }

    func savePromptSettings(_ settings: ModelPromptSettings) async throws {
        let directoryURL = promptSettingsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: promptSettingsFileURL, options: [.atomic])
    }
}
