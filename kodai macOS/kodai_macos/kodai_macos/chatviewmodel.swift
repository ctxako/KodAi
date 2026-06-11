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

private let userProfile = """
You are Kodai, a private on-device assistant for Charles.
Charles is a developer building Kodai, a macOS AI assistant app using Swift, SwiftUI, and Apple's Foundation Models framework.
He prefers short, practical responses. Don't over-explain unless asked.
"""

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
    var selectedMode: OutputMode = .chat {
        didSet {
            if selectedMode != oldValue {
                kodai.configure(instructions: buildInstructions())
            }
        }
    }
    var estimatedContextPercent: Int = 0

    private let kodai = KodaiModel()
    let telemetryStore = TelemetryStore()

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

    var chatTelemetry: ChatTelemetry {
        let activeTokens = Int(Double(estimatedContextPercent) / 100.0 * Double(estimatedContextWindowTokenLimit))
        let summaryAge = max(0, messages.count - 1)

        let allMetrics = messages.compactMap { $0.metrics }
        let generatedMetrics = allMetrics.filter { $0.phase == "Generated" }

        let avgSpeed: Double = {
            let speeds = generatedMetrics.map { $0.tokensPerSecond }.filter { $0 > 0 }
            guard !speeds.isEmpty else { return 0 }
            return speeds.reduce(0, +) / Double(speeds.count)
        }()

        let avgLatency: Double = {
            let latencies = generatedMetrics.map { $0.totalLatency }
            guard !latencies.isEmpty else { return 0 }
            return latencies.reduce(0, +) / Double(latencies.count)
        }()

        let avgTTFT: Double = {
            let ttfts = generatedMetrics.compactMap { $0.timeToFirstToken }
            guard !ttfts.isEmpty else { return 0 }
            return ttfts.reduce(0, +) / Double(ttfts.count)
        }()

        return ChatTelemetry(
            contextPercent: estimatedContextPercent,
            activeTokens: activeTokens,
            contextWindowSize: estimatedContextWindowTokenLimit,
            messageCount: messages.count,
            summaryAge: summaryAge,
            failureCount: allMetrics.filter { $0.phase == "No response" }.count,
            averageSpeed: avgSpeed,
            averageLatency: avgLatency,
            averageTimeToFirstToken: avgTTFT,
            streamName: selectedChat?.stream?.title
        )
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
        kodai.configure(instructions: buildInstructions())
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
        kodai.configure(instructions: buildInstructions())
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

    @discardableResult
    func createStream(title: String = "New stream", context: ModelContext) -> KodaiStream {
        let stream = KodaiStream(title: title)
        context.insert(stream)
        saveModelContext(context)
        return stream
    }

    func renameStream(_ stream: KodaiStream, to newTitle: String, context: ModelContext) {
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        stream.title = String(clean.prefix(60))
        stream.updatedAt = .now
        saveModelContext(context)
    }

    func deleteStream(_ stream: KodaiStream, keepChats: Bool, context: ModelContext) {
        if keepChats {
            for session in stream.sessions {
                session.stream = nil
            }
        } else {
            let wasSelectedInStream = stream.sessions.contains { $0.id == selectedChat?.id }
            for session in stream.sessions {
                context.delete(session)
            }
            if wasSelectedInStream {
                selectedChat = nil
                kodai.reset()
                messages = [
                    ChatMessage(role: .assistant, text: "What are we building today?")
                ]
                inputText = ""
                estimatedContextPercent = 0
            }
        }
        context.delete(stream)
        saveModelContext(context)
    }

    func assignChat(_ session: KodaiChatSession, to stream: KodaiStream?, context: ModelContext) {
        session.stream = stream
        stream?.updatedAt = .now
        saveModelContext(context)
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
        kodai.configure(instructions: buildInstructions())
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

        if isLoading {
            telemetryStore.cancelRequest()
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
        let reqID = telemetryStore.beginRequest()
        telemetryStore.emit(.requestStarted, to: reqID)
        activeStartedAt = startedAt
        activeFirstTokenAt = nil
        activeLastTokenAt = startedAt

        let promptHistory = recentConversationHistory(limit: 15)
        activePromptTokens = estimatedTokenCount(selectedMode.systemPrompt)
            + estimatedTokenCount(promptHistory)
            + estimatedTokenCount(cleanInput)
        telemetryStore.emit(.promptCounted, to: reqID)

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
        telemetryStore.emit(.contextChecked, to: reqID)

        startMetricsTicker(
            assistantID: assistantID,
            startedAt: startedAt
        )

        telemetryStore.emit(.modelPrefillStarted, to: reqID)

        let finalText = await kodai.streamResponse(
            to: cleanInput
        ) { [weak self] partialText in
            guard let self else { return }

            let now = Date()
            if self.activeFirstTokenAt == nil && !partialText.isEmpty {
                self.activeFirstTokenAt = now
                self.telemetryStore.emit(.firstTokenReceived, to: reqID)
            }
            if !partialText.isEmpty {
                self.activeLastTokenAt = now
                self.telemetryStore.emit(.tokenReceived, to: reqID)
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
            telemetryStore.emit(.responseFailed, to: reqID)
            if let idx = messages.firstIndex(where: { $0.id == assistantID }),
               let m = messages[idx].metrics {
                telemetryStore.finishRequest(id: reqID, summary: RequestSummary(
                    tokensPerSecond: m.tokensPerSecond,
                    totalLatency: m.totalLatency,
                    timeToFirstToken: m.timeToFirstToken,
                    failed: true
                ))
            }
        } else {
            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].text = finalText
            }

            updateMessageMetrics(
                assistantID: assistantID,
                phase: "Generated",
                startedAt: startedAt
            )
            telemetryStore.emit(.responseFinished, to: reqID)
            if let idx = messages.firstIndex(where: { $0.id == assistantID }),
               let m = messages[idx].metrics {
                telemetryStore.finishRequest(id: reqID, summary: RequestSummary(
                    tokensPerSecond: m.tokensPerSecond,
                    totalLatency: m.totalLatency,
                    timeToFirstToken: m.timeToFirstToken,
                    failed: false
                ))
            }
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

    private func buildInstructions() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let dateString = dateFormatter.string(from: Date())

        var lines = [
            userProfile,
            "",
            "Current date and time: \(dateString)",
        ]

        if let chat = selectedChat?.title {
            lines.append("Current conversation: \(chat)")
        }
        if let stream = selectedChat?.stream?.title {
            lines.append("Project stream: \(stream)")
        }

        lines += [
            "",
            "Current mode: \(selectedMode.rawValue)",
            "",
            "Mode instructions:",
            selectedMode.systemPrompt,
        ]

        return lines.joined(separator: "\n")
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
