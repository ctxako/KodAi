//
//  ollamabackend.swift
//  kodai_macos
//
//  Second chat engine: a local Ollama server, reached only at
//  127.0.0.1:11434 — nothing ever leaves the machine (same localhost-only
//  doctrine as kb_search's embedding calls). Stateless HTTP, so this backend
//  keeps per-chat message histories mirroring FoundationModelsBackend's
//  session cache. Token counts and speeds come from Ollama's real
//  eval_count/eval_duration stats, not estimates — the status pill and
//  per-turn badges report ground truth.
//

import Foundation
import KodaiCore

// MARK: - Engine choice

enum ChatEngine: String, CaseIterable {
    case appleFM
    case ollama

    static let storageKey = "engine.selected"
    static let ollamaModelKey = "engine.ollama.model"

    var displayName: String {
        switch self {
        case .appleFM: "Apple FM"
        case .ollama: "Ollama"
        }
    }
}

// MARK: - Wire types

struct OllamaChatMessage {
    var role: String
    var content: String
    /// Tool calls the model requested (assistant role), pass-through for history.
    var toolCalls: [OllamaToolCall] = []
    /// Tool name for role "tool" result messages.
    var toolName: String? = nil

    func asJSON() -> [String: Any] {
        var dict: [String: Any] = ["role": role, "content": content]
        if !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { $0.asJSON() }
        }
        if let toolName { dict["tool_name"] = toolName }
        return dict
    }
}

struct OllamaToolCall: Equatable {
    let name: String
    /// Stringified argument values, matching the kernel's RawToolCall shape.
    let arguments: [String: String]
    /// Raw arguments object, preserved for history round-trips.
    let rawArguments: [String: Any]

    static func == (lhs: OllamaToolCall, rhs: OllamaToolCall) -> Bool {
        lhs.name == rhs.name && lhs.arguments == rhs.arguments
    }

    func asJSON() -> [String: Any] {
        ["function": ["name": name, "arguments": rawArguments]]
    }
}

/// A tool description in Ollama's /api/chat `tools` format.
struct OllamaToolSpec {
    let name: String
    let description: String
    /// JSON-schema `properties` object: [param: ["type": …, "description": …]].
    let properties: [String: [String: String]]
    let required: [String]

    func asJSON() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ],
            ],
        ]
    }
}

/// One decoded NDJSON chunk from /api/chat.
struct OllamaChunk {
    var content = ""
    var toolCalls: [OllamaToolCall] = []
    var done = false
    var promptEvalCount: Int?
    var evalCount: Int?
    var evalDurationNs: Int64?
    var loadDurationNs: Int64?
    var totalDurationNs: Int64?
}

/// Real per-turn stats from Ollama's final chunk, for the status pill.
struct OllamaTurnStats: Equatable {
    let model: String
    let promptTokens: Int
    let outputTokens: Int
    let tokensPerSecond: Double
    let loadSeconds: Double
    let totalSeconds: Double
}

// MARK: - Backend

@MainActor
final class OllamaBackend: KodaiInferenceBackend {

    static let host = "http://127.0.0.1:11434"
    static let assumedContextWindow = 8_192

    var model: String {
        get { UserDefaults.standard.string(forKey: ChatEngine.ollamaModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: ChatEngine.ollamaModelKey) }
    }

    private(set) var lastStats: OllamaTurnStats?

    private var histories: [UUID: [OllamaChatMessage]] = [:]
    private var currentChatID: UUID?
    private(set) var currentInstructions = ""
    private var streamTask: Task<Void, Never>?

    // MARK: KodaiInferenceBackend

    var isAvailable: Bool {
        get async {
            var request = URLRequest(
                url: URL(string: "\(Self.host)/api/version")!,
                timeoutInterval: 2
            )
            request.httpMethod = "GET"
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return true
        }
    }

    func stream(prompt: String, instructions: String) -> AsyncStream<InferenceEvent> {
        streamTask?.cancel()
        if currentInstructions.isEmpty { currentInstructions = instructions }

        let (asyncStream, continuation) = AsyncStream.makeStream(of: InferenceEvent.self)

        let task = Task { @MainActor [weak self] in
            guard let self else { continuation.finish(); return }

            continuation.yield(.phase(.resolving))
            let modelName = self.model
            guard !modelName.isEmpty else {
                continuation.yield(.error(OllamaError.noModelSelected))
                continuation.finish()
                return
            }

            var messages: [OllamaChatMessage] = [
                OllamaChatMessage(role: "system", content: instructions)
            ]
            let history = self.currentChatID.flatMap { self.histories[$0] } ?? []
            messages += history
            messages.append(OllamaChatMessage(role: "user", content: prompt))

            continuation.yield(.phase(.prefilling))
            let startedAt = Date()
            var accumulated = ""
            var finalChunk: OllamaChunk?
            var yieldedDecoding = false

            do {
                for try await chunk in Self.streamChat(model: modelName, messages: messages, tools: []) {
                    try Task.checkCancellation()
                    if !yieldedDecoding {
                        continuation.yield(.phase(.decoding))
                        yieldedDecoding = true
                    }
                    if !chunk.content.isEmpty {
                        accumulated += chunk.content
                        continuation.yield(.token(accumulated, generatedTokenCount: 0))
                    }
                    if chunk.done { finalChunk = chunk }
                }

                let duration = max(Date().timeIntervalSince(startedAt), 0.001)
                let outputTokens = finalChunk?.evalCount
                    ?? max(1, Int(ceil(Double(accumulated.count) / 4.0)))
                let promptTokens = finalChunk?.promptEvalCount
                    ?? max(1, Int(ceil(Double(prompt.count + instructions.count) / 4.0)))
                let tps: Double?
                if let evalNs = finalChunk?.evalDurationNs, evalNs > 0, let count = finalChunk?.evalCount {
                    tps = Double(count) / (Double(evalNs) / 1_000_000_000)
                } else {
                    tps = Double(outputTokens) / duration
                }

                self.lastStats = OllamaTurnStats(
                    model: modelName,
                    promptTokens: promptTokens,
                    outputTokens: outputTokens,
                    tokensPerSecond: tps ?? 0,
                    loadSeconds: Double(finalChunk?.loadDurationNs ?? 0) / 1_000_000_000,
                    totalSeconds: Double(finalChunk?.totalDurationNs ?? 0) / 1_000_000_000
                )

                // Persist the exchange so the next turn carries history.
                if let chatID = self.currentChatID {
                    var updated = self.histories[chatID] ?? []
                    updated.append(OllamaChatMessage(role: "user", content: prompt))
                    updated.append(OllamaChatMessage(role: "assistant", content: accumulated))
                    self.histories[chatID] = updated
                }

                continuation.yield(.completed(InferenceResult(
                    fullText: accumulated.trimmingCharacters(in: .whitespacesAndNewlines),
                    promptTokensEst: promptTokens,
                    outputTokensEst: outputTokens,
                    duration: duration,
                    tokensPerSecond: tps
                )))
                continuation.yield(.phase(.completed))
            } catch is CancellationError {
                continuation.yield(.cancelled)
            } catch {
                continuation.yield(.error(error))
            }

            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
        streamTask = task
        return asyncStream
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    func reset() {
        streamTask?.cancel()
        streamTask = nil
        currentChatID = nil
    }

    // MARK: Session management (mirrors FoundationModelsBackend)

    func configure(instructions: String, chatID: UUID? = nil) {
        currentInstructions = instructions
        let resolvedID = chatID ?? currentChatID
        currentChatID = resolvedID
        if let id = resolvedID { histories[id] = [] }
    }

    func switchToChat(_ chatID: UUID, instructions: String) {
        currentInstructions = instructions
        currentChatID = chatID
        if histories[chatID] == nil { histories[chatID] = [] }
    }

    func bindChatID(_ chatID: UUID) {
        if let old = currentChatID, old != chatID, let history = histories[old] {
            histories[chatID] = history
            histories.removeValue(forKey: old)
        }
        currentChatID = chatID
    }

    func evictSession(for chatID: UUID) {
        histories.removeValue(forKey: chatID)
        if currentChatID == chatID { currentChatID = nil }
    }

    /// Direct history access for the agent loop (task-driven multi-step turns
    /// manage their own message list and persist it back here).
    func history(for chatID: UUID) -> [OllamaChatMessage] {
        histories[chatID] ?? []
    }

    func setHistory(_ history: [OllamaChatMessage], for chatID: UUID) {
        histories[chatID] = history
    }

    var activeChatID: UUID? { currentChatID }

    /// The agent loop measures its own turns; it reports them here so the
    /// status pill shows the same truth either way.
    func noteStats(_ stats: OllamaTurnStats) {
        lastStats = stats
    }

    // MARK: - Low-level chat stream (shared with AgentRunner)

    enum OllamaError: LocalizedError {
        case noModelSelected
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .noModelSelected:
                "No Ollama model selected — pick one in the engine menu."
            case .badResponse(let code):
                "Ollama returned HTTP \(code) — is the server running? (ollama serve)"
            }
        }
    }

    /// Streams /api/chat NDJSON chunks. `tools` may be empty for plain chat.
    nonisolated static func streamChat(
        model: String,
        messages: [OllamaChatMessage],
        tools: [OllamaToolSpec]
    ) -> AsyncThrowingStream<OllamaChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages.map { $0.asJSON() },
                        "stream": true,
                    ]
                    if !tools.isEmpty {
                        body["tools"] = tools.map { $0.asJSON() }
                    }

                    var request = URLRequest(
                        url: URL(string: "\(host)/api/chat")!,
                        timeoutInterval: 300
                    )
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw OllamaError.badResponse(status) }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        continuation.yield(Self.chunk(from: object))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private static func chunk(from object: [String: Any]) -> OllamaChunk {
        var chunk = OllamaChunk()
        if let message = object["message"] as? [String: Any] {
            chunk.content = message["content"] as? String ?? ""
            if let calls = message["tool_calls"] as? [[String: Any]] {
                chunk.toolCalls = calls.compactMap { call in
                    guard let function = call["function"] as? [String: Any],
                          let name = function["name"] as? String else { return nil }
                    let raw = function["arguments"] as? [String: Any] ?? [:]
                    var stringified: [String: String] = [:]
                    for (key, value) in raw {
                        stringified[key] = Self.stringify(value)
                    }
                    return OllamaToolCall(name: name, arguments: stringified, rawArguments: raw)
                }
            }
        }
        chunk.done = object["done"] as? Bool ?? false
        chunk.promptEvalCount = object["prompt_eval_count"] as? Int
        chunk.evalCount = object["eval_count"] as? Int
        chunk.evalDurationNs = (object["eval_duration"] as? NSNumber)?.int64Value
        chunk.loadDurationNs = (object["load_duration"] as? NSNumber)?.int64Value
        chunk.totalDurationNs = (object["total_duration"] as? NSNumber)?.int64Value
        return chunk
    }

    nonisolated private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default: return String(describing: value)
        }
    }
}
