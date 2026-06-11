//
//  chatviewmodel.swift
//  kodai_macos
//

import Foundation
import SwiftData
import Observation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class ChatViewModel {
    var inputText = ""
    var messages: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            text: "What are we building today?"
        )
    ]

    var selectedChat: KodaiChatSession?
    var isLoading = false
    var selectedMode: OutputMode = .chat
    var estimatedContextPercent: Int = 0

    private let kodai = KodaiModel()

    private var responseTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?

    private var activeAssistantID: UUID?
    private var activeStartedAt: Date?
    private var activeFirstTokenAt: Date?
    private var activeLastTokenAt: Date?
    private var activePromptTokens: Int = 0

    private let estimatedContextWindowTokenLimit = 4096

    var lastAssistantMessage: String {
        messages.reversed().first { $0.role == .assistant }?.text ?? ""
    }

    func send(context: ModelContext) {
        responseTask = Task {
            await runModel(context: context)
        }
    }

    func refreshContextEstimate(pendingInput: String = "") {
        estimatedContextPercent = estimatedCurrentContextPercent(pendingInput: pendingInput)
    }

    @discardableResult
    func createNewChat(context: ModelContext) -> KodaiChatSession {
        if isLoading {
            stopGeneration()
        }

        kodai.reset()

        let session = makeStoredChatSession(context: context)
        selectedChat = session

        messages = [
            ChatMessage(role: .assistant, text: "Fresh chat. What are we building today?")
        ]

        inputText = ""
        selectedMode = .chat
        estimatedContextPercent = estimatedCurrentContextPercent()
        saveModelContext(context)

        return session
    }

    func selectChat(_ session: KodaiChatSession) {
        if isLoading {
            stopGeneration()
        }

        kodai.reset()
        selectedChat = session
        messages = messagesForSession(session)
        inputText = ""
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    func renameChat(
        _ session: KodaiChatSession,
        to newTitle: String,
        context: ModelContext
    ) {
        let cleanTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else { return }

        session.title = String(cleanTitle.prefix(60))
        session.updatedAt = .now

        saveModelContext(context)
    }

    func deleteChat(
        _ session: KodaiChatSession,
        fallback fallbackChat: KodaiChatSession?,
        context: ModelContext
    ) {
        if isLoading {
            stopGeneration()
        }

        let wasSelected = selectedChat?.id == session.id

        context.delete(session)
        saveModelContext(context)

        if wasSelected {
            if let fallbackChat {
                selectChat(fallbackChat)
            } else {
                selectedChat = nil
                kodai.reset()
                messages = [
                    ChatMessage(role: .assistant, text: "What are we building today?")
                ]
                inputText = ""
                estimatedContextPercent = 0
            }
        }
    }

    func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    func resetSession() {
        kodai.reset()
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    func stopGeneration() {
        responseTask?.cancel()
        responseTask = nil
        metricsTask?.cancel()
        metricsTask = nil

        if let assistantID = activeAssistantID,
           let startedAt = activeStartedAt {
            finishStoppedMessage(
                assistantID: assistantID,
                startedAt: startedAt
            )
        }

        isLoading = false
        activeAssistantID = nil
        activeStartedAt = nil
        activeFirstTokenAt = nil
        activeLastTokenAt = nil
        activePromptTokens = 0
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    private func runModel(context: ModelContext) async {
        let cleanInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanInput.isEmpty else { return }

        let currentSession = ensureCurrentChat(context: context)

        metricsTask?.cancel()

        inputText = ""
        isLoading = true

        let startedAt = Date()
        activeStartedAt = startedAt
        activeFirstTokenAt = nil
        activeLastTokenAt = startedAt

        let promptHistory = recentConversationHistory(limit: 15)
        activePromptTokens = estimatedTokenCount(selectedMode.systemPrompt)
            + estimatedTokenCount(promptHistory)
            + estimatedTokenCount(cleanInput)

        let userMessage = ChatMessage(role: .user, text: cleanInput)
        messages.append(userMessage)
        saveStoredMessage(role: .user, content: cleanInput, in: currentSession, context: context)

        let assistantMessage = ChatMessage(
            role: .assistant,
            text: "",
            metrics: ResponseTelemetry(
                phase: "Preparing",
                promptTokens: activePromptTokens,
                outputTokens: 0,
                contextUsedPercent: estimatedContextPercent,
                tokensPerSecond: 0,
                totalLatency: 0
            )
        )
        messages.append(assistantMessage)

        let assistantID = assistantMessage.id
        activeAssistantID = assistantID
        estimatedContextPercent = estimatedCurrentContextPercent()

        startMetricsTicker(
            assistantID: assistantID,
            startedAt: startedAt
        )

        let finalText = await kodai.streamResponse(
            to: cleanInput,
            mode: selectedMode,
            history: promptHistory
        ) { [weak self] partialText in
            guard let self else { return }

            let now = Date()
            if self.activeFirstTokenAt == nil && !partialText.isEmpty {
                self.activeFirstTokenAt = now
            }
            if !partialText.isEmpty {
                self.activeLastTokenAt = now
            }

            let phase = partialText.isEmpty ? "Thinking" : "Generating"

            if let index = self.messages.firstIndex(where: { $0.id == assistantID }) {
                self.messages[index].text = partialText
            }

            self.updateMessageMetrics(
                assistantID: assistantID,
                phase: phase,
                startedAt: startedAt
            )
        }

        metricsTask?.cancel()
        metricsTask = nil

        if Task.isCancelled {
            finishStoppedMessage(assistantID: assistantID, startedAt: startedAt)
        } else if finalText.isEmpty {
            if let index = messages.firstIndex(where: { $0.id == assistantID }),
               messages[index].text.isEmpty {
                messages[index].text = "No response."
            }

            updateMessageMetrics(
                assistantID: assistantID,
                phase: "No response",
                startedAt: startedAt
            )
        } else {
            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].text = finalText
            }

            updateMessageMetrics(
                assistantID: assistantID,
                phase: "Generated",
                startedAt: startedAt
            )
        }

        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
            saveStoredMessage(role: .assistant, content: messages[index].text, in: currentSession, context: context)
        }

        isLoading = false
        responseTask = nil
        activeAssistantID = nil
        activeStartedAt = nil
        activeFirstTokenAt = nil
        activeLastTokenAt = nil
        activePromptTokens = 0
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    @discardableResult
    private func ensureCurrentChat(context: ModelContext) -> KodaiChatSession {
        if let selectedChat {
            return selectedChat
        }

        let session = makeStoredChatSession(context: context)
        selectedChat = session
        saveModelContext(context)
        return session
    }

    private func makeStoredChatSession(context: ModelContext) -> KodaiChatSession {
        let session = KodaiChatSession()
        context.insert(session)
        return session
    }

    private func messagesForSession(_ session: KodaiChatSession) -> [ChatMessage] {
        let storedMessages = session.messages.sorted { $0.createdAt < $1.createdAt }

        guard !storedMessages.isEmpty else {
            return [
                ChatMessage(role: .assistant, text: "Fresh chat. What are we building today?")
            ]
        }

        return storedMessages.map { storedMessage in
            ChatMessage(
                role: ChatRole(rawValue: storedMessage.role) ?? .assistant,
                text: storedMessage.content
            )
        }
    }

    private func finishStoppedMessage(
        assistantID: UUID,
        startedAt: Date
    ) {
        if let index = messages.firstIndex(where: { $0.id == assistantID }),
           messages[index].text.isEmpty {
            messages[index].text = "Stopped."
        }

        updateMessageMetrics(
            assistantID: assistantID,
            phase: "Stopped",
            startedAt: startedAt
        )
    }

    private func startMetricsTicker(
        assistantID: UUID,
        startedAt: Date
    ) {
        metricsTask?.cancel()

        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)

                guard let self else { return }
                guard self.isLoading else { continue }

                let currentText = self.messages.first(where: { $0.id == assistantID })?.text ?? ""
                let phase = currentText.isEmpty ? "Thinking" : "Generating"

                self.updateMessageMetrics(
                    assistantID: assistantID,
                    phase: phase,
                    startedAt: startedAt
                )
            }
        }
    }

    private func updateMessageMetrics(
        assistantID: UUID,
        phase: String,
        startedAt: Date
    ) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else {
            return
        }

        let now = Date()
        let output = messages[index].text
        let totalLatency = max(now.timeIntervalSince(startedAt), 0.01)
        let outputTokens = estimatedTokenCount(output)

        let ttft: Double? = activeFirstTokenAt.map { $0.timeIntervalSince(startedAt) }
        let lastToken = activeLastTokenAt ?? now
        let decodeTime: Double? = activeFirstTokenAt.map { max(lastToken.timeIntervalSince($0), 0.01) }

        let tokensPerSecond: Double
        if let dt = decodeTime, dt > 0, outputTokens > 0 {
            tokensPerSecond = Double(outputTokens) / dt
        } else {
            tokensPerSecond = 0
        }

        estimatedContextPercent = estimatedCurrentContextPercent()

        messages[index].metrics = ResponseTelemetry(
            phase: phase,
            promptTokens: activePromptTokens,
            outputTokens: outputTokens,
            contextUsedPercent: estimatedContextPercent,
            timeToFirstToken: ttft,
            decodeTime: decodeTime,
            tokensPerSecond: tokensPerSecond,
            totalLatency: totalLatency
        )
    }

    private func saveStoredMessage(
        role: ChatRole,
        content: String,
        in session: KodaiChatSession,
        context: ModelContext
    ) {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanContent.isEmpty else { return }

        let storedMessage = KodaiChatMessage(
            role: role.rawValue,
            content: cleanContent
        )

        context.insert(storedMessage)
        session.messages.append(storedMessage)
        session.updatedAt = .now

        if role == .user, session.title == "New chat" {
            session.title = makeChatTitle(from: cleanContent)
        }

        saveModelContext(context)
    }

    private func makeChatTitle(from text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= 38 {
            return singleLine.isEmpty ? "New chat" : singleLine
        }

        return String(singleLine.prefix(38)) + "…"
    }

    private func saveModelContext(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("SwiftData save failed: \(error)")
        }
    }

    private func estimatedCurrentContextPercent(pendingInput: String = "") -> Int {
        var contextText = """
        Mode instructions:
        \(selectedMode.systemPrompt)

        Recent conversation:
        \(recentConversationHistory(limit: 10))
        """

        let cleanPendingInput = pendingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPendingInput.isEmpty {
            contextText += "\n\nPending user message:\n\(cleanPendingInput)"
        }

        let contextTokens = estimatedTokenCount(contextText)
        let percent = (Double(contextTokens) / Double(estimatedContextWindowTokenLimit)) * 100.0

        return min(100, max(0, Int(percent.rounded())))
    }

    private func estimatedTokenCount(_ text: String) -> Int {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(cleanText.count) / 4.0)))
    }

    private func recentConversationHistory(limit: Int = 10) -> String {
        messages
            .suffix(limit)
            .map { message in
                let role = message.role == .user ? "User" : "Kodai"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")
    }
}
