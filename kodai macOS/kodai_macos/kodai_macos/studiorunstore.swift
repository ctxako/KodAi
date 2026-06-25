//
//  studiorunstore.swift
//  kodai_macos
//
//  Local run history for the Studio — the working set you A/B compare against.
//  Persisted as JSON in Application Support (the same lightweight pattern the
//  iOS app uses for chats), deliberately kept out of the chat SwiftData store.
//  D1 remains the shared/published record; this is the operator's local log.
//

import Foundation

/// One completed benchmark run: the per-prompt statistics plus the conditions
/// it ran under, so two runs are comparable.
struct StudioRun: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let engineLabel: String
    let modelName: String
    let quant: String
    let device: String
    let repetitions: Int
    let experimentId: String
    let approxTokens: Bool
    let prompts: [PromptStats]

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        engineLabel: String,
        modelName: String,
        quant: String,
        device: String,
        repetitions: Int,
        experimentId: String,
        approxTokens: Bool,
        prompts: [PromptStats]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.engineLabel = engineLabel
        self.modelName = modelName
        self.quant = quant
        self.device = device
        self.repetitions = repetitions
        self.experimentId = experimentId
        self.approxTokens = approxTokens
        self.prompts = prompts
    }

    var avgThroughput: Double {
        guard !prompts.isEmpty else { return 0 }
        return prompts.map(\.throughput.mean).reduce(0, +) / Double(prompts.count)
    }

    var avgLatency: Double {
        let vals = prompts.map(\.latency.mean).filter { $0 > 0 }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    var peakMemory: Double {
        prompts.map(\.memory.maximum).max() ?? 0
    }

    var shortLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return "\(modelName) · \(f.string(from: timestamp))"
    }
}

/// JSON-backed history store. Never silently overwrites a file it couldn't
/// decode — a corrupt file is set aside, not clobbered.
struct StudioRunStore {
    private let fileName = "StudioRuns.json"

    private var fileURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(fileName)
    }

    func load() -> [StudioRun] {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([StudioRun].self, from: data)
        } catch {
            // Set the bad file aside rather than lose it on the next save.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return []
        }
    }

    func save(_ runs: [StudioRun]) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(runs)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: history is a convenience, not the source of truth.
        }
    }
}
