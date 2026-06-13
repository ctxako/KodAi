//
//  chatviewmodel.swift
//  kodai_macos
//

import Foundation
import SwiftData
import Observation
import KodaiCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let userProfile = """
You are Kodai, a private on-device assistant for Charles.
Charles is a developer building Kodai, a macOS AI assistant app using Swift, SwiftUI, and Apple's Foundation Models framework.
He prefers short, practical responses. Don't over-explain unless asked.

Kodai is project- and task-aware. When project, task, or deadline context appears in the conversation, use it naturally.
- If asked what to work on, prioritize overdue tasks first, then tasks due today, then upcoming project work.
- Reference specific task titles and deadlines when they appear in context.
- If the user describes something that sounds like a task they need to track, suggest they use `/task <title>` to create it.
- You cannot create tasks, projects, or mark tasks complete directly. For those actions, direct the user:
  - `/task <title>` — create a task in the current project
  - `/project <name>` — create a new project
  - `/done <task name>` — mark a task as complete
"""

@MainActor
@Observable
final class ChatViewModel {
    var inputText = ""
    var messages: [ChatMessage] = []

    var selectedChat: KodaiChatSession?
    var isLoading = false
    var selectedMode: OutputMode = .chat {
        didSet {
            if selectedMode != oldValue {
                backend.configure(instructions: buildInstructions(), chatID: selectedChat?.id)
            }
        }
    }
    var estimatedContextPercent: Int = 0
    var turnRecords: [UUID: TurnRecord] = [:]
    var pendingToolProposal: PendingToolProposal?
    var isSummarizing = false

    private let backend = FoundationModelsBackend()
    private let summaryEngine = SummaryEngine()
    let telemetryStore = TelemetryStore()
    let ledgerRecorder = LedgerRecorder()
    private let contextAssembler = ContextAssembler(
        budget: TokenBudget(total: FoundationModelsBackend.contextWindowTokenLimit)
    )

    private var responseTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?

    private var activeAssistantID: UUID?
    private var activeStartedAt: Date?
    private var activeFirstTokenAt: Date?
    private var activeLastTokenAt: Date?
    private var activePromptTokens: Int = 0

    var lastAssistantMessage: String {
        messages.reversed().first { $0.role == .assistant }?.text ?? ""
    }

    var isWaitingForFirstToken: Bool {
        isLoading && activeFirstTokenAt == nil
    }

    var chatTelemetry: ChatTelemetry {
        let activeTokens = Int(Double(estimatedContextPercent) / 100.0 * Double(FoundationModelsBackend.contextWindowTokenLimit))
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
            contextWindowSize: FoundationModelsBackend.contextWindowTokenLimit,
            messageCount: messages.count,
            summaryAge: summaryAge,
            failureCount: allMetrics.filter { $0.phase == "No response" }.count,
            averageSpeed: avgSpeed,
            averageLatency: avgLatency,
            averageTimeToFirstToken: avgTTFT,
            streamName: selectedChat?.stream?.title
        )
    }

    func send(context: ModelContext, projects: [KodaiProject] = []) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = KodaiSlashCommandParser.parse(trimmed) {
            switch command.kind {
            case .summary:
                inputText = ""
                triggerSessionSummary(context: context)
                return
            case .task:
                handleTaskCommand(command, context: context)
                return
            case .project:
                handleProjectCommand(command, context: context)
                return
            case .done:
                handleDoneCommand(command, context: context)
                return
            case .help, .commands:
                handleHelpCommand(command, context: context)
                return
            case .proposeTask, .export, .stats, .tools, .unknown:
                break
            }
        }
        responseTask = Task {
            await runModel(context: context, projects: projects)
        }
    }

    func refreshContextEstimate(pendingInput: String = "") {
        estimatedContextPercent = estimatedCurrentContextPercent(pendingInput: pendingInput)
    }

    @discardableResult
    func createNewChat(context: ModelContext, project: KodaiProject? = nil) -> KodaiChatSession {
        if isLoading {
            stopGeneration()
        }

        discardTransientSelectedChat()
        cleanupEmptySessions(context: context)
        pendingToolProposal = nil
        backend.reset()

        let session = KodaiChatSession(project: project)
        selectedChat = session

        messages = []
        turnRecords = [:]

        inputText = ""
        selectedMode = .chat
        backend.configure(instructions: buildInstructions(), chatID: session.id)
        estimatedContextPercent = estimatedCurrentContextPercent()

        return session
    }

    func selectChat(_ session: KodaiChatSession, context: ModelContext) {
        if isLoading {
            stopGeneration()
        }

        discardTransientSelectedChat(excluding: session.id)
        cleanupEmptySessions(context: context, excluding: session.id)
        pendingToolProposal = nil
        selectedChat = session
        messages = messagesForSession(session)
        turnRecords = [:]
        inputText = ""
        backend.switchToChat(session.id, instructions: buildInstructions())
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    func cleanupEmptySessions(context: ModelContext, excluding excludedID: UUID? = nil) {
        let descriptor = FetchDescriptor<KodaiChatSession>()

        guard let sessions = try? context.fetch(descriptor) else { return }

        var deletedSessionIDs: [UUID] = []
        for session in sessions where session.id != excludedID && Self.isEmptySession(session) {
            deletedSessionIDs.append(session.id)
            context.delete(session)
        }

        guard !deletedSessionIDs.isEmpty else { return }

        for sessionID in deletedSessionIDs {
            backend.evictSession(for: sessionID)
        }
        saveModelContext(context)
    }

    private func discardTransientSelectedChat(excluding excludedID: UUID? = nil) {
        guard let selectedChat,
              selectedChat.id != excludedID,
              selectedChat.modelContext == nil else {
            return
        }

        backend.evictSession(for: selectedChat.id)
        selectedChat.project = nil
        selectedChat.stream = nil
        self.selectedChat = nil
    }

    static func isEmptySession(_ session: KodaiChatSession) -> Bool {
        !session.messages.contains { message in
            let isUserVisibleRole = message.role == ChatRole.user.rawValue
                || message.role == ChatRole.assistant.rawValue
            return isUserVisibleRole
                && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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

        backend.evictSession(for: session.id)
        context.delete(session)
        saveModelContext(context)

        if wasSelected {
            if let fallbackChat {
                selectChat(fallbackChat, context: context)
            } else {
                selectedChat = nil
                backend.reset()
                messages = []
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
                backend.evictSession(for: session.id)
                context.delete(session)
            }
            if wasSelectedInStream {
                selectedChat = nil
                backend.reset()
                messages = []
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

    // MARK: – Project CRUD

    @discardableResult
    func createProject(title: String = "New project", details: String = "", context: ModelContext) -> KodaiProject {
        let project = KodaiProject(title: title, details: details)
        context.insert(project)
        saveModelContext(context)
        return project
    }

    func renameProject(_ project: KodaiProject, title: String, details: String, context: ModelContext) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        project.title = String(clean.prefix(60))
        project.details = details
        project.updatedAt = .now
        saveModelContext(context)
    }

    func archiveProject(_ project: KodaiProject, context: ModelContext) {
        project.status = .archived
        project.updatedAt = .now
        saveModelContext(context)
    }

    func unarchiveProject(_ project: KodaiProject, context: ModelContext) {
        project.status = .active
        project.updatedAt = .now
        saveModelContext(context)
    }

    func deleteProject(_ project: KodaiProject, context: ModelContext) {
        let wasSelectedInProject = project.sessions.contains { $0.id == selectedChat?.id }
        for session in project.sessions {
            backend.evictSession(for: session.id)
        }
        context.delete(project)
        saveModelContext(context)
        if wasSelectedInProject {
            selectedChat = nil
            backend.reset()
            messages = []
            inputText = ""
            estimatedContextPercent = 0
        }
    }

    func updateProjectSummary(_ project: KodaiProject, summary: String, context: ModelContext) {
        project.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : summary
        project.summaryUpdatedAt = .now
        project.updatedAt = .now
        saveModelContext(context)
    }

    func assignChatToProject(_ session: KodaiChatSession, project: KodaiProject?, context: ModelContext) {
        session.project = project
        project?.updatedAt = .now
        saveModelContext(context)
    }

    // MARK: – Task CRUD

    @discardableResult
    func createTask(
        in project: KodaiProject,
        title: String,
        notes: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        context: ModelContext
    ) -> KodaiTask {
        let task = KodaiTask(title: title, notes: notes, priority: priority, dueDate: dueDate, project: project)
        context.insert(task)
        project.tasks.append(task)
        project.updatedAt = .now
        let dueSuffix = dueDate.map { " (due \(shortDateString($0)))" } ?? ""
        ledgerRecorder.recordActivity(kind: .taskChange, summary: "created: \(title)\(dueSuffix)", context: context)
        saveModelContext(context)
        return task
    }

    func toggleTask(_ task: KodaiTask, context: ModelContext) {
        let wasCompleted = task.isCompleted
        task.isCompleted = !wasCompleted
        task.completedAt = wasCompleted ? nil : .now
        task.updatedAt = .now
        ledgerRecorder.recordActivity(
            kind: .taskChange,
            summary: "\(wasCompleted ? "reopened" : "completed"): \(task.title)",
            context: context
        )
        saveModelContext(context)
    }

    func deleteTask(_ task: KodaiTask, context: ModelContext) {
        let title = task.title
        context.delete(task)
        ledgerRecorder.recordActivity(kind: .taskChange, summary: "deleted: \(title)", context: context)
        saveModelContext(context)
    }

    func renameTask(_ task: KodaiTask, title: String, context: ModelContext) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        task.title = clean
        task.updatedAt = .now
        saveModelContext(context)
    }

    func updateTaskDueDate(_ task: KodaiTask, dueDate: Date?, context: ModelContext) {
        task.dueDate = dueDate
        task.updatedAt = .now
        let summary: String
        if let date = dueDate {
            summary = "rescheduled: \(task.title) → \(shortDateString(date))"
        } else {
            summary = "cleared due date: \(task.title)"
        }
        ledgerRecorder.recordActivity(kind: .taskChange, summary: summary, context: context)
        saveModelContext(context)
    }

    func updateProjectDeadline(_ project: KodaiProject, deadline: Date?, context: ModelContext) {
        project.deadline = deadline
        project.updatedAt = .now
        let summary: String
        if let date = deadline {
            summary = "deadline set: \(project.title) → \(shortDateString(date))"
        } else {
            summary = "deadline cleared: \(project.title)"
        }
        ledgerRecorder.recordActivity(kind: .taskChange, summary: summary, context: context)
        saveModelContext(context)
    }

    // MARK: – Summary

    func triggerSessionSummary(context: ModelContext) {
        guard let session = selectedChat else { return }
        guard !isSummarizing, !isLoading else { return }

        let sortedMessages = session.messages.sorted { $0.createdAt < $1.createdAt }
        guard !sortedMessages.isEmpty else { return }

        let existingSummary = session.summaries
            .sorted { $0.createdAt > $1.createdAt }
            .first?.content
        let lastMsgID = sortedMessages.last?.id

        isSummarizing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSummarizing = false }
            do {
                let content = try await self.summaryEngine.generateSessionSummary(
                    messages: sortedMessages,
                    existingSummary: existingSummary
                )
                guard !content.isEmpty else { return }
                let summary = KodaiSummary(
                    kind: .session,
                    content: content,
                    previousContent: existingSummary,
                    session: session
                )
                context.insert(summary)
                if let lastMsgID { session.summarizedThroughMessageID = lastMsgID }
                self.saveModelContext(context)
            } catch {
                // Silent — background operation
            }
        }
    }

    func generateProjectSummary(_ project: KodaiProject, context: ModelContext) {
        guard !isSummarizing else { return }

        let title = project.title
        let existing = project.summary
        let sessionSummaries = project.sessions
            .flatMap { $0.summaries }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.content }

        isSummarizing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSummarizing = false }
            do {
                let content = try await self.summaryEngine.generateProjectSummary(
                    title: title,
                    existingSummary: existing,
                    sessionSummaries: sessionSummaries
                )
                guard !content.isEmpty else { return }
                self.updateProjectSummary(project, summary: content, context: context)
            } catch {
                // Silent — background operation
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
        backend.configure(instructions: buildInstructions(), chatID: selectedChat?.id)
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    func stopGeneration() {
        responseTask?.cancel()
        responseTask = nil
        backend.cancel()
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

    private func runModel(context: ModelContext, projects: [KodaiProject]) async {
        let cleanInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanInput.isEmpty else { return }

        let currentSession = ensureCurrentChat(context: context)

        metricsTask?.cancel()
        pendingToolProposal = nil

        inputText = ""
        isLoading = true

        let startedAt = Date()
        let reqID = telemetryStore.beginRequest()
        telemetryStore.emit(.requestStarted, to: reqID)
        activeStartedAt = startedAt
        activeFirstTokenAt = nil
        activeLastTokenAt = startedAt

        // Assemble context blocks + manifest before streaming.
        // History excluded here — LanguageModelSession owns conversational continuity.
        let (assembledInstructions, turnManifest) = assembleContext(userMessage: cleanInput, projects: projects)
        activePromptTokens = turnManifest.totalTokens + TokenEstimator.estimate(cleanInput)
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

        startMetricsTicker(assistantID: assistantID, startedAt: startedAt)

        telemetryStore.emit(.modelPrefillStarted, to: reqID)

        // Consume the inference stream.
        var finalText = ""
        var wasCancelled = false
        var completedResult: InferenceResult?

        for await event in backend.stream(prompt: cleanInput, instructions: assembledInstructions) {
            switch event {
            case .phase(_), .warmup(_), .diagnostic(_), .done(_):
                break

            case .token(let text, _):
                let now = Date()
                if activeFirstTokenAt == nil && !text.isEmpty {
                    activeFirstTokenAt = now
                    telemetryStore.emit(.firstTokenReceived, to: reqID)
                }
                if !text.isEmpty {
                    activeLastTokenAt = now
                    telemetryStore.emit(.tokenReceived, to: reqID)
                }

                let phase = text.isEmpty ? "Thinking" : "Generating"
                if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[index].text = text
                }
                updateMessageMetrics(assistantID: assistantID, phase: phase, startedAt: startedAt)

            case .completed(let result):
                finalText = result.fullText
                completedResult = result

            case .cancelled:
                wasCancelled = true

            case .error(let err):
                let message = "Kodai model error: \(err.localizedDescription)"
                if let index = messages.firstIndex(where: { $0.id == assistantID }),
                   messages[index].text.isEmpty {
                    messages[index].text = message
                }
            }
        }

        metricsTask?.cancel()
        metricsTask = nil

        if Task.isCancelled || wasCancelled {
            finishStoppedMessage(assistantID: assistantID, startedAt: startedAt)
        } else if finalText.isEmpty {
            if let index = messages.firstIndex(where: { $0.id == assistantID }),
               messages[index].text.isEmpty {
                messages[index].text = "No response."
            }

            updateMessageMetrics(assistantID: assistantID, phase: "No response", startedAt: startedAt)
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

            updateMessageMetrics(assistantID: assistantID, phase: "Generated", startedAt: startedAt)
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
            let assistantText = messages[index].text
            saveStoredMessage(role: .assistant, content: assistantText, in: currentSession, context: context)

            if !assistantText.isEmpty, !wasCancelled, !Task.isCancelled {
                let ttftMs = activeFirstTokenAt.map { $0.timeIntervalSince(startedAt) * 1000 }
                let turn = recordTurnLedger(
                    userText: cleanInput,
                    assistantText: assistantText,
                    systemPrompt: assembledInstructions,
                    startedAt: startedAt,
                    timeToFirstTokenMs: ttftMs,
                    completedResult: completedResult,
                    manifest: turnManifest,
                    sessionID: currentSession.id,
                    context: context
                )
                turnRecords[assistantID] = turn

                if let proposal = backend.proposalCollector.take() {
                    pendingToolProposal = proposal
                    ledgerRecorder.recordActivity(
                        kind: .toolProposal,
                        summary: proposalSummary(proposal),
                        context: context
                    )
                }
            }
        }

        isLoading = false
        responseTask = nil
        activeAssistantID = nil
        activeStartedAt = nil
        activeFirstTokenAt = nil
        activeLastTokenAt = nil
        activePromptTokens = 0
        estimatedContextPercent = estimatedCurrentContextPercent()
        checkAndAutoSummarize(context: context)
    }

    @discardableResult
    private func ensureCurrentChat(context: ModelContext) -> KodaiChatSession {
        if let selectedChat {
            return selectedChat
        }

        let session = KodaiChatSession()
        selectedChat = session
        backend.bindChatID(session.id)
        return session
    }

    private func messagesForSession(_ session: KodaiChatSession) -> [ChatMessage] {
        let storedMessages = session.messages.sorted { $0.createdAt < $1.createdAt }

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

        if role == .user, session.modelContext == nil {
            context.insert(session)
        }

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

    // MARK: – Today's tasks helpers

    func todaysTasks(from projects: [KodaiProject]) -> [KodaiTask] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        return projects
            .filter { $0.status == .active }
            .flatMap { $0.tasks }
            .filter { task in
                guard !task.isCompleted, let due = task.dueDate else { return false }
                return due < endOfToday
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private func formattedTodayTasksContext(_ tasks: [KodaiTask]) -> String {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cap = 10
        let capped = Array(tasks.prefix(cap))

        let overdueCount = capped.filter { ($0.dueDate ?? now) < startOfToday }.count
        var header = "Today's tasks (\(tasks.count) total"
        if overdueCount > 0 { header += ", \(overdueCount) overdue" }
        header += "):"

        let lines = capped.map { task -> String in
            let due = task.dueDate ?? now
            let label: String
            if due < startOfToday {
                let days = Calendar.current.dateComponents([.day], from: due, to: startOfToday).day ?? 0
                label = days > 0 ? "overdue \(days)d" : "overdue"
            } else {
                label = "due today"
            }
            let project = task.project?.title ?? "—"
            return "• [\(label)] \(task.title) — Project: \(project)"
        }
        return ([header] + lines).joined(separator: "\n")
    }

    private func formattedProjectDeadlineContext(_ project: KodaiProject) -> String {
        guard let deadline = project.deadline else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: deadline)
        let past = deadline < Date()
        let status = past ? " (overdue)" : ""
        return "Project deadline: \(project.title) — \(dateString)\(status)"
    }

    /// Build system instructions + context manifest for one turn.
    /// History is intentionally excluded: LanguageModelSession owns conversational continuity.
    private func assembleContext(userMessage: String, projects: [KodaiProject]) -> (instructions: String, manifest: ContextManifest) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let dateString = dateFormatter.string(from: Date())

        let personaContent = userProfile
        let timeContent = "Date/time: \(dateString)"
        let modeContent = "Current mode: \(selectedMode.rawValue)\nMode instructions:\n\(selectedMode.systemPrompt)"

        var blocks: [ContextBlock] = [
            ContextBlock(
                kind: "persona",
                content: personaContent,
                tokenEstimate: TokenEstimator.estimate(personaContent),
                priority: 0
            ),
            ContextBlock(
                kind: "time",
                content: timeContent,
                tokenEstimate: TokenEstimator.estimate(timeContent),
                priority: 1
            ),
            ContextBlock(
                kind: "mode",
                content: modeContent,
                tokenEstimate: TokenEstimator.estimate(modeContent),
                priority: 5
            ),
        ]

        var metaLines: [String] = []
        if let chatTitle = selectedChat?.title { metaLines.append("Current conversation: \(chatTitle)") }
        if let streamTitle = selectedChat?.stream?.title { metaLines.append("Project stream: \(streamTitle)") }
        if !metaLines.isEmpty {
            let metaContent = metaLines.joined(separator: "\n")
            blocks.append(ContextBlock(
                kind: "meta",
                content: metaContent,
                tokenEstimate: TokenEstimator.estimate(metaContent),
                priority: 3
            ))
        }

        // Session summary — injected when chat was previously summarized
        if let session = selectedChat {
            if let latest = session.summaries.sorted(by: { $0.createdAt > $1.createdAt }).first {
                let content = "Session context:\n\(latest.content)"
                blocks.append(ContextBlock(
                    kind: "session_summary",
                    content: content,
                    tokenEstimate: TokenEstimator.estimate(content),
                    priority: 2
                ))
            }
        }

        // Project summary — injected for every turn in a project chat
        if let project = selectedChat?.project, let projSummary = project.summary, !projSummary.isEmpty {
            let content = "Project (\(project.title)):\n\(projSummary)"
            blocks.append(ContextBlock(
                kind: "project_summary",
                content: content,
                tokenEstimate: TokenEstimator.estimate(content),
                priority: 3
            ))
        }

        // Active tasks — titles-only, ≤3 highest priority, injected when project has open tasks
        if let project = selectedChat?.project {
            let activeTitles = project.tasks
                .filter { !$0.isCompleted }
                .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
                .prefix(3)
                .map { $0.title }
            if !activeTitles.isEmpty {
                let content = "Active tasks: " + activeTitles.joined(separator: ", ")
                blocks.append(ContextBlock(
                    kind: "active_tasks",
                    content: content,
                    tokenEstimate: TokenEstimator.estimate(content),
                    priority: 4,
                    sourceID: project.id
                ))
            }
        }

        // Today's tasks — cross-project due/overdue tasks
        let dueTasks = todaysTasks(from: projects)
        if !dueTasks.isEmpty {
            let content = formattedTodayTasksContext(dueTasks)
            blocks.append(ContextBlock(
                kind: "today_tasks",
                content: content,
                tokenEstimate: TokenEstimator.estimate(content),
                priority: 3
            ))
        }

        // Project deadline — shown when current project has a deadline
        if let project = selectedChat?.project, project.deadline != nil {
            let content = formattedProjectDeadlineContext(project)
            if !content.isEmpty {
                blocks.append(ContextBlock(
                    kind: "project_deadline",
                    content: content,
                    tokenEstimate: TokenEstimator.estimate(content),
                    priority: 3,
                    sourceID: project.id
                ))
            }
        }

        let (instructions, manifest) = contextAssembler.assemble(blocks: blocks)
        return (instructions, manifest)
    }

    @discardableResult
    private func recordTurnLedger(
        userText: String,
        assistantText: String,
        systemPrompt: String,
        startedAt: Date,
        timeToFirstTokenMs: Double?,
        completedResult: InferenceResult?,
        manifest: ContextManifest,
        sessionID: UUID,
        context: ModelContext
    ) -> TurnRecord {
        let latencyMs = completedResult.map { $0.duration * 1000 }
            ?? max(Date().timeIntervalSince(startedAt), 0) * 1000
        let inputTokens = completedResult?.promptTokensEst ?? activePromptTokens
        let outputTokens = completedResult?.outputTokensEst ?? TokenEstimator.estimate(assistantText)

        return ledgerRecorder.recordTurn(
            userText: userText,
            assistantText: assistantText,
            systemPrompt: systemPrompt,
            sessionID: sessionID,
            manifest: manifest,
            backend: "FoundationModels",
            modelName: "SystemLanguageModel.default",
            latencyMs: latencyMs,
            timeToFirstTokenMs: timeToFirstTokenMs,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            contextPercent: estimatedContextPercent,
            context: context
        )
    }

    private func checkAndAutoSummarize(context: ModelContext) {
        guard !isSummarizing, !isLoading else { return }
        guard let session = selectedChat else { return }

        let allMessages = session.messages
        let total = allMessages.count
        guard total > 0 else { return }

        let unsummarized: Int
        if let throughID = session.summarizedThroughMessageID {
            let sorted = allMessages.sorted { $0.createdAt < $1.createdAt }
            if let idx = sorted.firstIndex(where: { $0.id == throughID }) {
                unsummarized = total - (idx + 1)
            } else {
                unsummarized = total
            }
        } else {
            unsummarized = total
        }

        if unsummarized >= 20 || estimatedContextPercent >= 70 {
            triggerSessionSummary(context: context)
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
        let percent = (Double(contextTokens) / Double(FoundationModelsBackend.contextWindowTokenLimit)) * 100.0

        return min(100, max(0, Int(percent.rounded())))
    }

    private func estimatedTokenCount(_ text: String) -> Int {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(cleanText.count) / 4.0)))
    }

    private func shortDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: – Slash command: /task

    private func handleTaskCommand(_ command: KodaiParsedSlashCommand, context: ModelContext) {
        inputText = ""
        let currentSession = ensureCurrentChat(context: context)

        messages.append(ChatMessage(role: .user, text: command.rawInput))
        saveStoredMessage(role: .user, content: command.rawInput, in: currentSession, context: context)

        func reply(_ text: String) {
            messages.append(ChatMessage(role: .assistant, text: text))
            saveStoredMessage(role: .assistant, content: text, in: currentSession, context: context)
        }

        guard let title = command.title, !title.isEmpty else {
            reply("Usage: `/task <title>` — optionally add `priority:high` or `due:Jun20`.")
            return
        }

        guard let project = selectedChat?.project else {
            reply("No active project — open a project chat or use /project to create one.")
            return
        }

        let priority = command.taskPriority.map(TaskPriority.init) ?? .medium
        let dueDate = command.dueDate
        createTask(in: project, title: title, priority: priority, dueDate: dueDate, context: context)

        var parts: [String] = [priority.rawValue]
        if let due = dueDate { parts.append("due \(shortDateString(due))") }
        reply("Created task: \(title) (\(parts.joined(separator: ", ")))")
    }

    // MARK: – Tool proposal confirmation

    func confirmProposal(context: ModelContext, projects: [KodaiProject]) {
        guard let proposal = pendingToolProposal else { return }
        let currentSession = ensureCurrentChat(context: context)

        switch proposal.kind {
        case .createTask(let p):
            let project: KodaiProject? = {
                if let id = p.projectID {
                    return projects.first { $0.id == id }
                }
                return selectedChat?.project
            }()

            guard let project else {
                let msg = "No active project — open a project chat or use /project to create one."
                messages.append(ChatMessage(role: .assistant, text: msg))
                saveStoredMessage(role: .assistant, content: msg, in: currentSession, context: context)
                pendingToolProposal = nil
                return
            }

            let priority = TaskPriority(rawValue: p.priority.lowercased()) ?? .medium
            createTask(in: project, title: p.title, priority: priority, dueDate: p.dueDate, context: context)

            var parts: [String] = [priority.rawValue]
            if let due = p.dueDate { parts.append("due \(shortDateString(due))") }
            let msg = "Created task: \(p.title) (\(parts.joined(separator: ", ")))"
            messages.append(ChatMessage(role: .assistant, text: msg))
            saveStoredMessage(role: .assistant, content: msg, in: currentSession, context: context)
        }

        pendingToolProposal = nil
    }

    func cancelProposal(context: ModelContext) {
        guard let proposal = pendingToolProposal else { return }
        ledgerRecorder.recordActivity(
            kind: .toolProposal,
            summary: "dismissed: \(proposalSummary(proposal))",
            context: context
        )
        pendingToolProposal = nil
        let currentSession = ensureCurrentChat(context: context)
        let msg = "Canceled task creation."
        messages.append(ChatMessage(role: .assistant, text: msg))
        saveStoredMessage(role: .assistant, content: msg, in: currentSession, context: context)
    }

    private func proposalSummary(_ proposal: PendingToolProposal) -> String {
        switch proposal.kind {
        case .createTask(let p):
            var parts = ["proposed task: \(p.title)"]
            if let name = p.projectName { parts.append("project: \(name)") }
            return parts.joined(separator: ", ")
        }
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

    // MARK: – Slash command: /project

    private func handleProjectCommand(_ command: KodaiParsedSlashCommand, context: ModelContext) {
        inputText = ""

        guard let parsedTitle = command.title, !parsedTitle.isEmpty else {
            let session = ensureCurrentChat(context: context)
            messages.append(ChatMessage(role: .user, text: command.rawInput))
            saveStoredMessage(role: .user, content: command.rawInput, in: session, context: context)
            let reply = "Usage: `/project <name>` — creates a new project and opens a chat in it."
            messages.append(ChatMessage(role: .assistant, text: reply))
            saveStoredMessage(role: .assistant, content: reply, in: session, context: context)
            return
        }

        let title = String(parsedTitle.prefix(60))
        let project = createProject(title: title, context: context)
        ledgerRecorder.recordActivity(kind: .taskChange, summary: "created project: \(title)", context: context)

        createNewChat(context: context, project: project)

        guard let newSession = selectedChat else { return }

        messages.append(ChatMessage(role: .user, text: command.rawInput))
        saveStoredMessage(role: .user, content: command.rawInput, in: newSession, context: context)
        let reply = "Created project: \(title)"
        messages.append(ChatMessage(role: .assistant, text: reply))
        saveStoredMessage(role: .assistant, content: reply, in: newSession, context: context)
    }

    // MARK: – Slash command: /done

    private func handleDoneCommand(_ command: KodaiParsedSlashCommand, context: ModelContext) {
        inputText = ""
        let currentSession = ensureCurrentChat(context: context)

        messages.append(ChatMessage(role: .user, text: command.rawInput))
        saveStoredMessage(role: .user, content: command.rawInput, in: currentSession, context: context)

        func reply(_ text: String) {
            messages.append(ChatMessage(role: .assistant, text: text))
            saveStoredMessage(role: .assistant, content: text, in: currentSession, context: context)
        }

        guard let project = selectedChat?.project else {
            reply("No active project — open a project chat or use /project to create one.")
            return
        }

        guard let queryTitle = command.title, !queryTitle.isEmpty else {
            let openTasks = project.tasks
                .filter { !$0.isCompleted }
                .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
            if openTasks.isEmpty {
                reply("No open tasks in this project.")
            } else {
                let list = openTasks.map { "• \($0.title)" }.joined(separator: "\n")
                reply("Open tasks in \(project.title):\n\(list)")
            }
            return
        }

        let query = queryTitle.lowercased()
        let matches = project.tasks.filter { !$0.isCompleted && $0.title.lowercased().contains(query) }

        switch matches.count {
        case 0:
            reply("No open task matched: \(queryTitle)")
        case 1:
            let task = matches[0]
            toggleTask(task, context: context)
            reply("Completed task: \(task.title)")
        default:
            let titles = matches.map { "• \($0.title)" }.joined(separator: "\n")
            reply("Multiple tasks matched \"\(queryTitle)\" — be more specific:\n\(titles)")
        }
    }

    // MARK: – Slash command: /help, /commands

    private func handleHelpCommand(_ command: KodaiParsedSlashCommand, context: ModelContext) {
        inputText = ""
        let currentSession = ensureCurrentChat(context: context)

        messages.append(ChatMessage(role: .user, text: command.rawInput))
        saveStoredMessage(role: .user, content: command.rawInput, in: currentSession, context: context)

        let reply = """
        **Available slash commands**

        `/task <title>` — create a task in the current project
        `/task <title> priority:high due:Jun20` — create a task with priority and due date
        `/project <name>` — create a new project and switch into it
        `/done <task>` — complete a matching open task
        `/done` — list open tasks in the current project
        `/summary` — summarize the current chat
        `/help` or `/commands` — show this list
        """

        messages.append(ChatMessage(role: .assistant, text: reply))
        saveStoredMessage(role: .assistant, content: reply, in: currentSession, context: context)
    }
}
