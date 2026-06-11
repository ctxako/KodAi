//
//  ContentView.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//


import SwiftUI
import Foundation
import FoundationModels
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \KodaiChatSession.updatedAt, order: .reverse)
    private var chatSessions: [KodaiChatSession]

    @StateObject private var kodai = KodaiModel()

    @State private var responseTask: Task<Void, Never>?
    @State private var metricsTask: Task<Void, Never>?

    @State private var activeAssistantID: UUID?
    @State private var activeStartedAt: Date?
    @State private var activeFirstTokenAt: Date?
    @State private var activeLastTokenAt: Date?
    @State private var activePromptTokens: Int = 0

    @State private var inputText = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            text: "What are we building today?"
        )
    ]

    @State private var selectedChat: KodaiChatSession?
    @State private var isLoading = false
    @State private var selectedMode: OutputMode = .chat
    @State private var estimatedContextPercent: Int = 0
    @State private var sidebarOpen = true

    @FocusState private var composerFocused: Bool

    private let estimatedContextWindowTokenLimit = 4096

    // Must track the sidebar's frame in KodaiSidebar: width (266/66)
    // plus its 10pt leading padding, plus a 10pt gap to the content.
    private let sidebarOpenWidth: CGFloat = 266
    private let sidebarClosedWidth: CGFloat = 66
    private let sidebarLeadingPadding: CGFloat = 10
    private let sidebarContentGap: CGFloat = 10

    private var contentLeadingPadding: CGFloat {
        (sidebarOpen ? sidebarOpenWidth : sidebarClosedWidth)
            + sidebarLeadingPadding
            + sidebarContentGap
    }

    private var lastAssistantMessage: String {
        messages.reversed().first { $0.role == .assistant }?.text ?? ""
    }

    private var chatTelemetry: ChatTelemetry {
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

        return ChatTelemetry(
            contextPercent: estimatedContextPercent,
            activeTokens: activeTokens,
            contextWindowSize: estimatedContextWindowTokenLimit,
            messageCount: messages.count,
            summaryAge: summaryAge,
            failureCount: allMetrics.filter { $0.phase == "No response" }.count,
            averageSpeed: avgSpeed,
            averageLatency: avgLatency
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            KodaiBackground()

            VStack(spacing: 0) {
                ChatScrollView(messages: messages)

                ComposerView(
                    inputText: $inputText,
                    selectedMode: $selectedMode,
                    composerFocused: $composerFocused,
                    isLoading: isLoading,
                    telemetry: chatTelemetry,
                    onSend: {
                        responseTask = Task {
                            await runModel()
                        }
                    },
                    onStop: {
                        stopGeneration()
                    }
                )
            }
            .padding(.leading, contentLeadingPadding)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)

            sidebar
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 950, minHeight: 650)
        .onAppear {
            if selectedChat == nil, let newestChat = chatSessions.first {
                selectChat(newestChat)
            }

            estimatedContextPercent = estimatedCurrentContextPercent()
        }
        .onChange(of: chatSessions.map { $0.id }) {
            if selectedChat == nil, let newestChat = chatSessions.first {
                selectChat(newestChat)
            }
        }
        .onChange(of: inputText) {
            guard !isLoading else { return }
            estimatedContextPercent = estimatedCurrentContextPercent(pendingInput: inputText)
        }
        .onChange(of: selectedMode) {
            estimatedContextPercent = estimatedCurrentContextPercent(pendingInput: inputText)
        }
    }

    private var sidebar: some View {
        KodaiSidebar(
            sidebarOpen: $sidebarOpen,
            selectedMode: $selectedMode,
            estimatedContextPercent: estimatedContextPercent,
            lastAssistantMessage: lastAssistantMessage,
            chatSessions: chatSessions,
            selectedChatID: selectedChat?.id,
            onRenameChat: { session, newTitle in
                renameChat(session, to: newTitle)
            },
            onDeleteChat: { session in
                deleteChat(session)
            },
            onNewSession: {
                createNewChat()
            },
            onCopyLatest: {
                copyToClipboard(lastAssistantMessage)
            },
            onSelectChat: { session in
                selectChat(session)
            },
            onResetSession: {
                kodai.reset()
                estimatedContextPercent = estimatedCurrentContextPercent()
            }
        )
    }

    @discardableResult
    private func createNewChat() -> KodaiChatSession {
        if isLoading {
            stopGeneration()
        }

        kodai.reset()

        let session = makeStoredChatSession()
        selectedChat = session

        messages = [
            ChatMessage(role: .assistant, text: "Fresh chat. What are we building today?")
        ]

        inputText = ""
        selectedMode = .chat
        estimatedContextPercent = estimatedCurrentContextPercent()
        saveModelContext()

        return session
    }

    private func selectChat(_ session: KodaiChatSession) {
        if isLoading {
            stopGeneration()
        }

        kodai.reset()
        selectedChat = session
        messages = messagesForSession(session)
        inputText = ""
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    @discardableResult
    private func ensureCurrentChat() -> KodaiChatSession {
        if let selectedChat {
            return selectedChat
        }

        let session = makeStoredChatSession()
        selectedChat = session
        saveModelContext()
        return session
    }

    private func makeStoredChatSession() -> KodaiChatSession {
        let session = KodaiChatSession()
        modelContext.insert(session)
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

    @MainActor
    private func runModel() async {
        let cleanInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanInput.isEmpty else { return }

        let currentSession = ensureCurrentChat()

        metricsTask?.cancel()

        inputText = ""
        composerFocused = false
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
        saveStoredMessage(role: .user, content: cleanInput, in: currentSession)

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
        ) { partialText in

            let now = Date()
            if activeFirstTokenAt == nil && !partialText.isEmpty {
                activeFirstTokenAt = now
            }
            if !partialText.isEmpty {
                activeLastTokenAt = now
            }

            let phase = partialText.isEmpty ? "Thinking" : "Generating"

            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].text = partialText
            }

            updateMessageMetrics(
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
            saveStoredMessage(role: .assistant, content: messages[index].text, in: currentSession)
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

    private func stopGeneration() {
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

        metricsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)

                await MainActor.run {
                    guard isLoading else { return }

                    let currentText = messages.first(where: { $0.id == assistantID })?.text ?? ""
                    let phase = currentText.isEmpty ? "Thinking" : "Generating"

                    updateMessageMetrics(
                        assistantID: assistantID,
                        phase: phase,
                        startedAt: startedAt
                    )
                }
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
        in session: KodaiChatSession
    ) {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanContent.isEmpty else { return }

        let storedMessage = KodaiChatMessage(
            role: role.rawValue,
            content: cleanContent
        )

        modelContext.insert(storedMessage)
        session.messages.append(storedMessage)
        session.updatedAt = .now

        if role == .user, session.title == "New chat" {
            session.title = makeChatTitle(from: cleanContent)
        }

        saveModelContext()
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

    private func saveModelContext() {
        do {
            try modelContext.save()
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

    private func renameChat(_ session: KodaiChatSession, to newTitle: String) {
        let cleanTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else { return }

        session.title = String(cleanTitle.prefix(60))
        session.updatedAt = .now

        saveModelContext()
    }

    private func deleteChat(_ session: KodaiChatSession) {
        if isLoading {
            stopGeneration()
        }

        let fallbackChat = chatSessions.first { $0.id != session.id }
        let wasSelected = selectedChat?.id == session.id

        modelContext.delete(session)
        saveModelContext()

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

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
