//
//  kodaisummaryengine.swift
//  kodai_macos
//

import Foundation
import FoundationModels

@MainActor
final class SummaryEngine {
    private let model = SystemLanguageModel.default

    func generateSessionSummary(
        messages: [KodaiChatMessage],
        existingSummary: String? = nil
    ) async throws -> String {
        let transcript = messages.suffix(40).map { msg in
            let role = msg.role == "user" ? "User" : "Kodai"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")

        let prompt: String
        if let existing = existingSummary, !existing.isEmpty {
            prompt = """
            Previous summary:
            \(existing)

            New messages to incorporate:
            \(transcript)

            Update the summary in ≤120 tokens. Focus on decisions, outcomes, and open questions.
            """
        } else {
            prompt = """
            Conversation:
            \(transcript)

            Summarize this conversation in ≤120 tokens. Focus on decisions, outcomes, and open questions.
            """
        }

        let session = LanguageModelSession(instructions: "You summarize conversations accurately and concisely.")
        var result = ""
        for try await partial in session.streamResponse(to: prompt) {
            result = partial.content
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateProjectSummary(
        title: String,
        existingSummary: String?,
        sessionSummaries: [String]
    ) async throws -> String {
        let sessionsText = sessionSummaries.isEmpty
            ? "(no session summaries available)"
            : sessionSummaries.joined(separator: "\n---\n")

        let prompt: String
        if let existing = existingSummary, !existing.isEmpty {
            prompt = """
            Project: \(title)

            Current summary:
            \(existing)

            Session summaries:
            \(sessionsText)

            Update this project summary in ≤200 tokens. Preserve active decisions and status.
            """
        } else {
            prompt = """
            Project: \(title)

            Session summaries:
            \(sessionsText)

            Create a project summary in ≤200 tokens. Include active decisions and current status.
            """
        }

        let session = LanguageModelSession(instructions: "You summarize projects accurately and concisely.")
        var result = ""
        for try await partial in session.streamResponse(to: prompt) {
            result = partial.content
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
