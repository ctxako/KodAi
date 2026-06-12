//
//  foundationmodelsbackend.swift
//  kodai_macos
//

import Foundation
import FoundationModels
import KodaiCore

// MARK: - Error

private enum FMInferenceError: LocalizedError {
    case modelUnavailable(String)
    case noSession

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "Apple Intelligence unavailable: \(reason)"
        case .noSession: "No inference session available."
        }
    }
}

// MARK: - Backend

@MainActor
final class FoundationModelsBackend: KodaiInferenceBackend {

    static let contextWindowTokenLimit = 4096

    private let model = SystemLanguageModel.default
    private var currentSession: LanguageModelSession?
    private var currentChatID: UUID?
    // Per-chat session cache so history survives chat switches within a session.
    private var sessionCache: [UUID: LanguageModelSession] = [:]
    private(set) var currentInstructions = ""
    private var streamTask: Task<Void, Never>?

    let proposalCollector = ToolProposalCollector()
    private let kodaiTools: [any Tool]

    init() {
        kodaiTools = [CreateTaskTool(collector: proposalCollector)]
    }

    // MARK: KodaiInferenceBackend

    var isAvailable: Bool {
        get async {
            if case .available = model.availability { return true }
            return false
        }
    }

    func stream(prompt: String, instructions: String) -> AsyncStream<InferenceEvent> {
        streamTask?.cancel()

        // Lazily create a session if none exists yet.
        if currentSession == nil {
            let eff = currentInstructions.isEmpty ? instructions : currentInstructions
            currentInstructions = eff
            let session = LanguageModelSession(tools: kodaiTools, instructions: eff)
            currentSession = session
            if let id = currentChatID { sessionCache[id] = session }
        }

        // makeStream() lets us set up the Task and onTermination without putting
        // actor-isolated mutations inside a @Sendable closure.
        let (asyncStream, continuation) = AsyncStream.makeStream(of: InferenceEvent.self)

        let task = Task { @MainActor [weak self] in
            guard let self else { continuation.finish(); return }

            continuation.yield(.phase(.resolving))

            switch self.model.availability {
            case .available:
                break
            case .unavailable(let reason):
                continuation.yield(.error(FMInferenceError.modelUnavailable("\(reason)")))
                continuation.finish()
                return
            @unknown default:
                continuation.yield(.error(FMInferenceError.modelUnavailable("Unknown availability")))
                continuation.finish()
                return
            }

            guard let session = self.currentSession else {
                continuation.yield(.error(FMInferenceError.noSession))
                continuation.finish()
                return
            }

            continuation.yield(.phase(.prefilling))

            let startedAt = Date()
            var finalText = ""
            var lastUIUpdate = Date.distantPast

            do {
                let responseStream = session.streamResponse(to: prompt)
                continuation.yield(.phase(.decoding))

                for try await partial in responseStream {
                    try Task.checkCancellation()
                    let text = partial.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    finalText = text

                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdate) >= 0.035 {
                        continuation.yield(.token(text))
                        lastUIUpdate = now
                    }
                }

                // Flush the final accumulated text before completing.
                continuation.yield(.token(finalText))

                let duration = max(Date().timeIntervalSince(startedAt), 0.001)
                let outputTokensEst = max(1, Int(ceil(Double(finalText.count) / 4.0)))
                let promptTokensEst = max(1, Int(ceil(Double(prompt.count + instructions.count) / 4.0)))
                let tps: Double? = outputTokensEst > 0 ? Double(outputTokensEst) / duration : nil

                continuation.yield(.completed(InferenceResult(
                    fullText: finalText,
                    promptTokensEst: promptTokensEst,
                    outputTokensEst: outputTokensEst,
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
        currentSession = nil
        currentChatID = nil
    }

    // MARK: Session management

    /// Create a fresh session (e.g. mode change). Updates the cache entry for the current chat.
    func configure(instructions: String, chatID: UUID? = nil) {
        currentInstructions = instructions
        let resolvedID = chatID ?? currentChatID
        currentChatID = resolvedID
        let session = LanguageModelSession(tools: kodaiTools, instructions: instructions)
        currentSession = session
        if let id = resolvedID {
            sessionCache[id] = session
        }
    }

    /// Restore or create a session for a specific chat; preserves history if cached.
    func switchToChat(_ chatID: UUID, instructions: String) {
        currentInstructions = instructions
        currentChatID = chatID
        if let cached = sessionCache[chatID] {
            currentSession = cached
        } else {
            let session = LanguageModelSession(tools: kodaiTools, instructions: instructions)
            currentSession = session
            sessionCache[chatID] = session
        }
    }

    /// Bind an existing (unkeyed) session to a newly-assigned chat UUID.
    func bindChatID(_ chatID: UUID) {
        currentChatID = chatID
        if let session = currentSession {
            sessionCache[chatID] = session
        }
    }

    /// Remove a deleted chat's session from the cache.
    func evictSession(for chatID: UUID) {
        sessionCache.removeValue(forKey: chatID)
        if currentChatID == chatID {
            currentSession = nil
            currentChatID = nil
        }
    }
}
