//
//  kodaimodel.swift
//  kodai_macos
//

import Foundation
import FoundationModels

@MainActor
@Observable
final class KodaiModel {
    // Single source of truth for the estimated context window size (chars / 4 ≈ tokens).
    static let contextWindowTokenLimit = 4096

    private let model = SystemLanguageModel.default
    private var currentSession: LanguageModelSession?
    private var currentChatID: UUID?
    // Per-chat session cache so history survives chat switches within a session.
    private var sessionCache: [UUID: LanguageModelSession] = [:]
    private var currentInstructions = ""

    /// Create a fresh session with new instructions (e.g. mode change).
    /// Updates the cache entry for the current chat if one is set.
    func configure(instructions: String, chatID: UUID? = nil) {
        currentInstructions = instructions
        let resolvedID = chatID ?? currentChatID
        currentChatID = resolvedID
        let session = LanguageModelSession(instructions: instructions)
        currentSession = session
        if let id = resolvedID {
            sessionCache[id] = session
        }
    }

    /// Restore or create a session for a specific chat.
    /// If the chat already has a cached session it is reused (history preserved).
    func switchToChat(_ chatID: UUID, instructions: String) {
        currentInstructions = instructions
        currentChatID = chatID
        if let cached = sessionCache[chatID] {
            currentSession = cached
        } else {
            let session = LanguageModelSession(instructions: instructions)
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

    /// Drop the current session without touching the cache (used on full reset).
    func reset() {
        currentSession = nil
        currentChatID = nil
    }

    func streamResponse(
        to input: String,
        onPartial: @escaping @MainActor (String) -> Void
    ) async -> String {

        switch model.availability {
        case .available:
            break

        case .unavailable(let reason):
            let message = """
            Apple Intelligence model unavailable.

            Reason:
            \(reason)
            """
            onPartial(message)
            return message

        @unknown default:
            let message = "Apple Intelligence model unavailable."
            onPartial(message)
            return message
        }

        if currentSession == nil {
            let session = LanguageModelSession(instructions: currentInstructions)
            currentSession = session
            if let id = currentChatID {
                sessionCache[id] = session
            }
        }

        do {
            let stream = currentSession!.streamResponse(to: input)

            var finalText = ""
            var lastUIUpdate = Date.distantPast

            for try await partial in stream {
                try Task.checkCancellation()

                let text = partial.content.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = text

                let now = Date()
                if now.timeIntervalSince(lastUIUpdate) >= 0.035 {
                    onPartial(text)
                    lastUIUpdate = now
                }
            }

            onPartial(finalText)
            return finalText

        } catch is CancellationError {
            return ""

        } catch {
            let message = "Kodai model error: \(error.localizedDescription)"
            onPartial(message)
            return message
        }
    }
}
