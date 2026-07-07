//
//  enginehealthmonitor.swift
//  kodai_macos
//
//  Live health state for the Ollama engine, driving the status pill and the
//  "do this, then this" setup checklist. The ladder is checked in order —
//  server reachable → model installed → model loaded — and the first rung
//  that fails is the state, so the UI always shows the *next* action, with
//  real facts (installed models, VRAM, context length) from the API, never
//  guesses. FM health stays where it was (SystemLanguageModel.availability).
//

import Foundation
import Observation

/// Where the Ollama engine stands, from the user's point of view.
enum OllamaHealth: Equatable {
    /// Nothing answered at 127.0.0.1:11434 — install and/or start Ollama.
    case serverDown
    /// Server up, but the selected model isn't installed — `ollama pull …`.
    case modelMissing(installed: [String])
    /// Server up, model installed but not loaded — first message will be slow.
    case coldStart
    /// Model loaded and ready.
    case ready(OllamaRunningModel)

    var isUsable: Bool {
        switch self {
        case .serverDown, .modelMissing: false
        case .coldStart, .ready: true
        }
    }
}

struct OllamaRunningModel: Equatable {
    let name: String
    let parameterSize: String
    let quantization: String
    let vramBytes: Int64
    let contextLength: Int

    var vramDisplay: String {
        let gb = Double(vramBytes) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }
}

@MainActor
@Observable
final class EngineHealthMonitor {

    private(set) var health: OllamaHealth = .serverDown
    private(set) var installedModels: [String] = []
    private(set) var serverVersion: String?
    private(set) var lastChecked: Date?
    private(set) var isChecking = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// One full ladder check for the given model.
    func check(model: String) async {
        isChecking = true
        defer {
            isChecking = false
            lastChecked = Date()
        }

        guard let version = await fetchVersion() else {
            health = .serverDown
            installedModels = []
            serverVersion = nil
            return
        }
        serverVersion = version

        let installed = await fetchInstalledModels()
        installedModels = installed

        let modelInstalled = !model.isEmpty && installed.contains { installedName in
            installedName == model || installedName.hasPrefix("\(model):")
        }
        guard modelInstalled else {
            health = .modelMissing(installed: installed)
            return
        }

        let running = await fetchRunningModels()
        if let match = running.first(where: { $0.name == model || $0.name.hasPrefix("\(model):") }) {
            health = .ready(match)
        } else {
            health = .coldStart
        }
    }

    /// Poll while the Ollama engine is selected; stops any previous poll.
    func startPolling(model: @escaping @MainActor () -> String, interval: TimeInterval = 30) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.check(model: model())
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - API calls (all 127.0.0.1, short timeouts)

    private func fetchVersion() async -> String? {
        guard let object = await getJSON("/api/version") else { return nil }
        return object["version"] as? String ?? "unknown"
    }

    private func fetchInstalledModels() async -> [String] {
        guard let object = await getJSON("/api/tags"),
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    private func fetchRunningModels() async -> [OllamaRunningModel] {
        guard let object = await getJSON("/api/ps"),
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let details = entry["details"] as? [String: Any] ?? [:]
            return OllamaRunningModel(
                name: name,
                parameterSize: details["parameter_size"] as? String ?? "?",
                quantization: details["quantization_level"] as? String ?? "?",
                vramBytes: (entry["size_vram"] as? NSNumber)?.int64Value ?? 0,
                contextLength: entry["context_length"] as? Int ?? 0
            )
        }
    }

    private func getJSON(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: "\(OllamaBackend.host)\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}
