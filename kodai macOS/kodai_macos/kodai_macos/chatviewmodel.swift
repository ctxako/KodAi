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
- You can create tasks and projects with your tools (createTask, createProject). When the user asks you to track or plan work, call the tool — the user approves before anything is saved.
- You can work with files in folders the user granted: file_glob and file_grep to find, file_read to read, file_write and file_edit to change (the user approves every write). Chain them: find → read → edit. Never guess file contents — read first.
- A tool's returned JSON is the real outcome. If it reports ok, confirm what was created; if it reports an error or cancellation, say so plainly and never claim the action happened.
- You cannot mark tasks complete. For that, direct the user to `/done <task name>`.
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
                configureEngines(instructions: buildInstructions(), chatID: selectedChat?.id)
            }
        }
    }
    var estimatedContextPercent: Int = 0
    var turnRecords: [UUID: TurnRecord] = [:]
    var isSummarizing = false

    /// Which brain answers the next turn. Persisted; the status pill and
    /// per-turn badges always reflect what actually ran.
    var selectedEngine: ChatEngine = ChatEngine(
        rawValue: UserDefaults.standard.string(forKey: ChatEngine.storageKey) ?? ""
    ) ?? .appleFM {
        didSet {
            guard selectedEngine != oldValue else { return }
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: ChatEngine.storageKey)
            if selectedEngine == .ollama {
                ollamaBackend.configure(instructions: buildInstructions(), chatID: selectedChat?.id)
                engineHealth.startPolling { [weak self] in self?.ollamaBackend.model ?? "" }
            } else {
                engineHealth.stopPolling()
            }
        }
    }
    var fmAvailable = false

    /// Ollama model selection, bound by the engine pill.
    var ollamaModel: String {
        get { ollamaBackend.model }
        set { ollamaBackend.model = newValue }
    }
    var lastOllamaStats: OllamaTurnStats? { ollamaBackend.lastStats }

    let confirmBroker: ConfirmBroker
    let folderGrants: FolderGrantStore
    let engineHealth = EngineHealthMonitor()
    private let workspaceExecutor: WorkspaceToolExecutor
    private let fileExecutor: FileToolExecutor
    private let backend: FoundationModelsBackend
    private let ollamaBackend = OllamaBackend()
    private let summaryEngine = SummaryEngine()
    let telemetryStore = TelemetryStore()
    let ledgerRecorder = LedgerRecorder()
    private let contextAssembler = ContextAssembler(
        budget: TokenBudget(total: FoundationModelsBackend.contextWindowTokenLimit)
    )

    private var responseTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?

    private var activeAssistantID: UUID?
    private var activeEngineLabel: String?
    private var activeBackendName = "FoundationModels"
    private var activeModelName = "SystemLanguageModel.default"
    private var activeStartedAt: Date?
    private var activeFirstTokenAt: Date?
    private var activeLastTokenAt: Date?
    private var activePromptTokens: Int = 0
    private var recentCreatedTaskCorrectionTarget: (taskID: UUID, sessionID: UUID)?

    init() {
        let broker = ConfirmBroker()
        let executor = WorkspaceToolExecutor(broker: broker)
        let grants = FolderGrantStore()
        let files = FileToolExecutor(grants: grants, broker: broker)
        confirmBroker = broker
        workspaceExecutor = executor
        folderGrants = grants
        fileExecutor = files
        backend = FoundationModelsBackend(tools: [
            CreateTaskTool(executor: executor),
            CreateProjectTool(executor: executor),
            SearchKnowledgeBaseTool(),
            ReadFileTool(executor: files),
            GlobFilesTool(executor: files),
            GrepFilesTool(executor: files),
            WriteFileTool(executor: files),
            EditFileTool(executor: files)
        ])

        if selectedEngine == .ollama {
            engineHealth.startPolling { [weak self] in self?.ollamaBackend.model ?? "" }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.fmAvailable = await self.backend.isAvailable
        }
    }

    var lastAssistantMessage: String {
        messages.reversed().first { $0.role == .assistant }?.text ?? ""
    }

    var isWaitingForFirstToken: Bool {
        isLoading && activeFirstTokenAt == nil
    }

    var chatTelemetry: ChatTelemetry {
        let activeTokens = Int(Double(estimatedContextPercent) / 100.0 * Double(contextWindowTokens))
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
            contextWindowSize: contextWindowTokens,
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
        if handleRecentTaskDueDateCorrection(trimmed, context: context) {
            return
        }
        recentCreatedTaskCorrectionTarget = nil

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
        confirmBroker.cancelPending()
        resetEngines()

        let session = KodaiChatSession(projectID: project?.id)
        selectedChat = session

        messages = []
        turnRecords = [:]

        inputText = ""
        selectedMode = .chat
        configureEngines(instructions: buildInstructions(), chatID: session.id)
        estimatedContextPercent = estimatedCurrentContextPercent()

        return session
    }

    func selectChat(_ session: KodaiChatSession, context: ModelContext) {
        if isLoading {
            stopGeneration()
        }

        discardTransientSelectedChat(excluding: session.id)
        cleanupEmptySessions(context: context, excluding: session.id)
        confirmBroker.cancelPending()
        selectedChat = session
        messages = messagesForSession(session)
        turnRecords = [:]
        inputText = ""
        switchEnginesToChat(session.id, instructions: buildInstructions())
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
            evictEngineSessions(for: sessionID)
        }
        saveModelContext(context)
    }

    private func discardTransientSelectedChat(excluding excludedID: UUID? = nil) {
        guard let selectedChat,
              selectedChat.id != excludedID,
              selectedChat.modelContext == nil else {
            return
        }

        evictEngineSessions(for: selectedChat.id)
        selectedChat.projectID = nil
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

        evictEngineSessions(for: session.id)
        context.delete(session)
        saveModelContext(context)

        if wasSelected {
            if let fallbackChat {
                selectChat(fallbackChat, context: context)
            } else {
                selectedChat = nil
                resetEngines()
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
                evictEngineSessions(for: session.id)
                context.delete(session)
            }
            if wasSelectedInStream {
                selectedChat = nil
                resetEngines()
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

    private func currentProject(in projects: [KodaiProject]) -> KodaiProject? {
        guard let projectID = selectedChat?.projectID else { return nil }
        return projects.first { $0.id == projectID }
    }

    private func currentProject(context: ModelContext) -> KodaiProject? {
        try? context.kodaiProject(id: selectedChat?.projectID)
    }

    @discardableResult
    func createProject(title: String = "New project", details: String = "", context: ModelContext) -> KodaiProject {
        let project = KodaiProject(title: title, details: details)
        context.insert(project)
#if DEBUG
        print("[PersistenceCheck] insert KodaiProject id=\(project.id) store=KodaiWorkspace")
#endif
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
        let projectSessions: [KodaiChatSession]
        let projectSummaries: [KodaiSummary]
        do {
            projectSessions = try context.kodaiChatSessions(projectID: project.id)
            projectSummaries = try context.kodaiSummaries(projectID: project.id)
        } catch {
            return
        }

        let wasSelectedInProject = projectSessions.contains { $0.id == selectedChat?.id }
        for summary in projectSummaries {
            summary.projectID = nil
        }
        for session in projectSessions {
            evictEngineSessions(for: session.id)
            context.delete(session)
        }
        context.delete(project)
        saveModelContext(context)
        if wasSelectedInProject {
            selectedChat = nil
            resetEngines()
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
        session.projectID = project?.id
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
        let normalizedDueDate = dueDate.flatMap { TaskDueDateSemantics.normalized($0) }
        let task = KodaiTask(
            title: title,
            notes: notes,
            priority: priority,
            dueDate: normalizedDueDate,
            project: project
        )
        context.insert(task)
#if DEBUG
        print("[PersistenceCheck] insert KodaiTask id=\(task.id) store=KodaiWorkspace")
#endif
        if project.tasks != nil { project.tasks!.append(task) } else { project.tasks = [task] }
        project.updatedAt = .now
        let dueSuffix = normalizedDueDate.map { " (due \(shortDateString($0)))" } ?? ""
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
        let normalizedDueDate = dueDate.flatMap { TaskDueDateSemantics.normalized($0) }
        task.dueDate = normalizedDueDate
        task.updatedAt = .now
        let summary: String
        if let date = normalizedDueDate {
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
                    session: session,
                    projectID: session.projectID
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
        let sessionSummaries = ((try? context.kodaiChatSessions(projectID: project.id)) ?? [])
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
        configureEngines(instructions: buildInstructions(), chatID: selectedChat?.id)
        estimatedContextPercent = estimatedCurrentContextPercent()
    }

    func stopGeneration() {
        // Decline any tool call suspended on a confirmation first, so its
        // continuation resumes before the stream task is torn down.
        confirmBroker.cancelPending()
        responseTask?.cancel()
        responseTask = nil
        backend.cancel()
        ollamaBackend.cancel()
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
        confirmBroker.cancelPending()

        inputText = ""
        isLoading = true

        let startedAt = Date()
        let reqID = telemetryStore.beginRequest()
        telemetryStore.emit(.requestStarted, to: reqID)
        activeStartedAt = startedAt
        activeFirstTokenAt = nil
        activeLastTokenAt = startedAt

        // Engine choice is locked per turn. If Ollama is selected but not
        // reachable, fall back to FM with a truthful badge — never silently.
        var turnEngine = selectedEngine
        if turnEngine == .ollama {
            let reachable = await ollamaBackend.isAvailable
            if ollamaModel.isEmpty || !reachable {
                turnEngine = .appleFM
                activeEngineLabel = "Apple FM · fallback (Ollama offline)"
            } else {
                activeEngineLabel = ollamaModel
            }
        } else {
            activeEngineLabel = "Apple FM"
        }
        activeBackendName = turnEngine == .ollama ? "Ollama" : "FoundationModels"
        activeModelName = turnEngine == .ollama ? ollamaModel : "SystemLanguageModel.default"

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
                totalLatency: 0,
                engineLabel: activeEngineLabel
            )
        )
        messages.append(assistantMessage)

        let assistantID = assistantMessage.id
        activeAssistantID = assistantID
        estimatedContextPercent = estimatedCurrentContextPercent()
        telemetryStore.emit(.contextChecked, to: reqID)

        startMetricsTicker(assistantID: assistantID, startedAt: startedAt)

        bindWorkspaceExecutor(
            context: context,
            projects: projects,
            assistantID: assistantID,
            startedAt: startedAt
        )

        telemetryStore.emit(.modelPrefillStarted, to: reqID)

        // Consume the inference stream.
        var finalText = ""
        var wasCancelled = false
        var completedResult: InferenceResult?

        // Ollama turns run the multi-step agent loop (find → read → act with
        // real tool results between steps); FM keeps its native session loop.
        // The step budget scales with the loaded model's context window.
        let eventStream: AsyncStream<InferenceEvent>
        if turnEngine == .ollama {
            let stepBudget = contextWindowTokens >= 16_384 ? 10
                : (contextWindowTokens >= 8_192 ? 8 : 4)
            let chatID = currentSession.id
            eventStream = AgentRunner.stream(
                config: AgentRunner.Configuration(
                    model: ollamaModel,
                    stepBudget: stepBudget,
                    tools: agentToolSpecs()
                ),
                systemInstructions: assembledInstructions,
                history: ollamaBackend.history(for: chatID),
                userPrompt: cleanInput,
                onCompletion: { [weak self] history, stats in
                    guard let self else { return }
                    self.ollamaBackend.setHistory(history, for: chatID)
                    if let stats { self.ollamaBackend.noteStats(stats) }
                }
            )
        } else {
            eventStream = backend.stream(prompt: cleanInput, instructions: assembledInstructions)
        }

        for await event in eventStream {
            switch event {
            case .phase(_), .warmup(_), .diagnostic(_), .done(_), .tokenDecision(_):
                // .tokenDecision carries pre-sampling logit telemetry from the
                // llama.cpp runtime; Foundation Models never emits it on macOS.
                break

            case .toolActivity(let activity):
                // Agent-loop steps: live phase in the metrics line, and a
                // step chip in the transcript once the call resolves.
                updateMessageMetrics(
                    assistantID: assistantID,
                    phase: Self.toolActivityLabel(activity),
                    startedAt: startedAt
                )
                if activity.phase == .succeeded || activity.phase == .failed,
                   let detail = activity.detail,
                   let index = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[index].agentSteps.append(detail)
                }

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

        // Release any tool call still suspended on a confirmation (e.g. the
        // stream ended or was cancelled mid-confirm), then drop this turn's
        // context bindings so nothing can write through a stale ModelContext.
        confirmBroker.cancelPending()
        workspaceExecutor.clearTurnBindings()
        fileExecutor.clearTurnBindings()

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
            }
        }

        isLoading = false
        responseTask = nil
        activeAssistantID = nil
        activeEngineLabel = nil
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
        bindEngineChatID(session.id)
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
            totalLatency: totalLatency,
            engineLabel: activeEngineLabel ?? messages[index].metrics?.engineLabel
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

    // MARK: – Agent tool bridge

    /// The same executors that power the FM tools, in Ollama's native
    /// tools format for the agent loop. One executor layer, two engines —
    /// confirm gates and ledger logging apply identically.
    private func agentToolSpecs() -> [AgentToolSpec] {
        let files = fileExecutor
        let workspace = workspaceExecutor
        return [
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "file_read",
                    description: "Read a text file from the user's granted folders. Returns up to 150 lines; pass start_line to continue a long file.",
                    properties: [
                        "path": ["type": "string", "description": "File path, e.g. '~/life/kb/kodai.md'"],
                        "start_line": ["type": "integer", "description": "1-based line to start from; omit for the beginning"],
                    ],
                    required: ["path"]
                ),
                run: { args in
                    files.readFile(
                        path: args["path"] ?? "",
                        startLine: Int(args["start_line"] ?? args["startLine"] ?? "") ?? 0
                    )
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "file_glob",
                    description: "List files matching a glob pattern (e.g. '*.md') inside the user's granted folders, newest first.",
                    properties: [
                        "pattern": ["type": "string", "description": "Glob pattern, e.g. '*.md' or 'kb/*.md'"],
                    ],
                    required: ["pattern"]
                ),
                run: { args in
                    files.globFiles(pattern: args["pattern"] ?? "")
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "file_grep",
                    description: "Search file contents in the user's granted folders (case-insensitive). Returns path:line matches — follow up with file_read.",
                    properties: [
                        "query": ["type": "string", "description": "Text to search for"],
                        "file_pattern": ["type": "string", "description": "Optional glob to limit files, e.g. '*.md'"],
                    ],
                    required: ["query"]
                ),
                run: { args in
                    files.grepFiles(
                        query: args["query"] ?? "",
                        filePattern: args["file_pattern"] ?? args["filePattern"] ?? ""
                    )
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "file_write",
                    description: "Create or fully replace a text file in a write-granted folder. The user approves every write.",
                    properties: [
                        "path": ["type": "string", "description": "File path inside a write-granted folder"],
                        "content": ["type": "string", "description": "The complete file content"],
                    ],
                    required: ["path", "content"]
                ),
                run: { args in
                    await files.writeFile(path: args["path"] ?? "", content: args["content"] ?? "")
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "file_edit",
                    description: "Replace text inside an existing file. old_text must match the file verbatim exactly once — file_read first. The user approves every edit.",
                    properties: [
                        "path": ["type": "string", "description": "File path inside a write-granted folder"],
                        "old_text": ["type": "string", "description": "Exact existing text to replace"],
                        "new_text": ["type": "string", "description": "Replacement text"],
                    ],
                    required: ["path", "old_text", "new_text"]
                ),
                run: { args in
                    await files.editFile(
                        path: args["path"] ?? "",
                        oldText: args["old_text"] ?? args["oldText"] ?? "",
                        newText: args["new_text"] ?? args["newText"] ?? ""
                    )
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "kb_search",
                    description: "Semantic search over the user's personal knowledge base (~/life/kb): projects, plans, decisions, notes. Read-only.",
                    properties: [
                        "query": ["type": "string", "description": "What to look for"],
                    ],
                    required: ["query"]
                ),
                run: { args in
                    let query = (args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !query.isEmpty else {
                        return .failure(tool: "kb_search", error: "empty query")
                    }
                    let results = await LifeKnowledgeBase.search(query: query, limit: 4)
                    return .ok(tool: "kb_search", result: ["results": results])
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "task_create",
                    description: "Create a task in the user's current project. The user approves before it is saved.",
                    properties: [
                        "title": ["type": "string", "description": "Task title"],
                        "priority": ["type": "string", "description": "low, medium, or high"],
                        "due_date": ["type": "string", "description": "Due date like 2026-07-10, or omit"],
                    ],
                    required: ["title"]
                ),
                run: { args in
                    await workspace.createTask(
                        title: args["title"] ?? "",
                        priority: args["priority"] ?? "medium",
                        dueDate: args["due_date"] ?? args["dueDate"] ?? ""
                    )
                }
            ),
            AgentToolSpec(
                spec: OllamaToolSpec(
                    name: "project_create",
                    description: "Create a new project for the user. The user approves before it is saved.",
                    properties: [
                        "title": ["type": "string", "description": "Project name"],
                    ],
                    required: ["title"]
                ),
                run: { args in
                    await workspace.createProject(title: args["title"] ?? "")
                }
            ),
        ]
    }

    // MARK: – Engine plumbing

    /// Both engines mirror session lifecycle so switching mid-app never
    /// routes a chat at a stale or missing session.
    private func configureEngines(instructions: String, chatID: UUID?) {
        backend.configure(instructions: instructions, chatID: chatID)
        ollamaBackend.configure(instructions: instructions, chatID: chatID)
    }

    private func switchEnginesToChat(_ chatID: UUID, instructions: String) {
        backend.switchToChat(chatID, instructions: instructions)
        ollamaBackend.switchToChat(chatID, instructions: instructions)
    }

    private func bindEngineChatID(_ chatID: UUID) {
        backend.bindChatID(chatID)
        ollamaBackend.bindChatID(chatID)
    }

    private func evictEngineSessions(for chatID: UUID) {
        backend.evictSession(for: chatID)
        ollamaBackend.evictSession(for: chatID)
    }

    private func resetEngines() {
        backend.reset()
        ollamaBackend.reset()
    }

    /// The active engine's context window — FM is fixed at 4096; Ollama
    /// reports the real loaded context via /api/ps when known.
    var contextWindowTokens: Int {
        guard selectedEngine == .ollama else {
            return FoundationModelsBackend.contextWindowTokenLimit
        }
        if case .ready(let running) = engineHealth.health, running.contextLength > 0 {
            return running.contextLength
        }
        return OllamaBackend.assumedContextWindow
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

        if let standing = KodaiProfileLoader.standingInstructions(grants: folderGrants) {
            lines += ["", "User's standing instructions (KODAI.md):", standing]
        }

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
            KodaiOutputModePromptBuilder.build(for: selectedMode.outputFormat),
        ]

        return lines.joined(separator: "\n")
    }

    // MARK: – Today's tasks helpers

    func todaysTasks(from projects: [KodaiProject]) -> [KodaiTask] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        return projects
            .filter { $0.status == .active }
            .flatMap { $0.tasks ?? [] }
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
        let modeInstructions = KodaiOutputModePromptBuilder.build(for: selectedMode.outputFormat)
        let modeContent = "Current mode: \(selectedMode.rawValue)\nMode instructions:\n\(modeInstructions)"

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

        // KODAI.md — the user's standing instructions, right after persona.
        if let standing = KodaiProfileLoader.standingInstructions(grants: folderGrants) {
            let content = "User's standing instructions (KODAI.md):\n\(standing)"
            blocks.append(ContextBlock(
                kind: "user_profile",
                content: content,
                tokenEstimate: TokenEstimator.estimate(content),
                priority: 1
            ))
        }

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
        if let project = currentProject(in: projects),
           let projSummary = project.summary,
           !projSummary.isEmpty {
            let content = "Project (\(project.title)):\n\(projSummary)"
            blocks.append(ContextBlock(
                kind: "project_summary",
                content: content,
                tokenEstimate: TokenEstimator.estimate(content),
                priority: 3
            ))
        }

        // Active tasks — titles-only, ≤3 highest priority, injected when project has open tasks
        if let project = currentProject(in: projects) {
            let activeTitles = (project.tasks ?? [])
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
        if let project = currentProject(in: projects), project.deadline != nil {
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
            backend: activeBackendName,
            modelName: activeModelName,
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
        let modeInstructions = KodaiOutputModePromptBuilder.build(for: selectedMode.outputFormat)
        var contextText = """
        Mode instructions:
        \(modeInstructions)

        Recent conversation:
        \(recentConversationHistory(limit: 10))
        """

        let cleanPendingInput = pendingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPendingInput.isEmpty {
            contextText += "\n\nPending user message:\n\(cleanPendingInput)"
        }

        let contextTokens = estimatedTokenCount(contextText)
        let percent = (Double(contextTokens) / Double(contextWindowTokens)) * 100.0

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

        guard let project = currentProject(context: context) else {
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

    // MARK: – Workspace tool execution

    /// Binds this turn's ModelContext and project list into the executor so
    /// confirmed tool calls write through live state. Cleared when the turn's
    /// stream finishes.
    private func bindWorkspaceExecutor(
        context: ModelContext,
        projects: [KodaiProject],
        assistantID: UUID,
        startedAt: Date
    ) {
        workspaceExecutor.onActivity = { [weak self] activity in
            guard let self else { return }
            self.updateMessageMetrics(
                assistantID: assistantID,
                phase: Self.toolActivityLabel(activity),
                startedAt: startedAt
            )
        }

        fileExecutor.onActivity = { [weak self] activity in
            guard let self else { return }
            self.updateMessageMetrics(
                assistantID: assistantID,
                phase: Self.toolActivityLabel(activity),
                startedAt: startedAt
            )
        }

        fileExecutor.recordToolRun = { [weak self] tool, summary in
            guard let self else { return }
            self.ledgerRecorder.recordActivity(
                kind: .toolCall,
                summary: "\(tool): \(summary)",
                context: context
            )
        }

        workspaceExecutor.performCreateTask = { [weak self] title, priority, dueDate in
            guard let self else {
                return .failure(tool: WorkspaceToolExecutor.createTaskToolID, error: "workspace unavailable")
            }
            guard let project = self.currentProject(in: projects) else {
                return .failure(
                    tool: WorkspaceToolExecutor.createTaskToolID,
                    error: "no active project — the user must open a project chat or create one first"
                )
            }
            let session = self.ensureCurrentChat(context: context)
            let task = self.createTask(
                in: project,
                title: title,
                priority: priority,
                dueDate: dueDate,
                context: context
            )
            self.noteRecentCreatedTask(task, sessionID: session.id)

            var fields = [
                "title": task.title,
                "priority": priority.rawValue,
                "project": project.title
            ]
            if let due = task.dueDate {
                fields["due"] = self.shortDateString(due)
            }
            return .ok(tool: WorkspaceToolExecutor.createTaskToolID, result: fields)
        }

        workspaceExecutor.performCreateProject = { [weak self] title in
            guard let self else {
                return .failure(tool: WorkspaceToolExecutor.createProjectToolID, error: "workspace unavailable")
            }
            let project = self.createProject(title: title, context: context)
            self.ledgerRecorder.recordActivity(
                kind: .taskChange,
                summary: "created project: \(project.title)",
                context: context
            )
            return .ok(
                tool: WorkspaceToolExecutor.createProjectToolID,
                result: ["title": project.title]
            )
        }
    }

    /// Marks a just-created task as the target for a follow-up due-date
    /// correction ("no, due June 13th!") in the same chat session.
    func noteRecentCreatedTask(_ task: KodaiTask, sessionID: UUID) {
        recentCreatedTaskCorrectionTarget = (task.id, sessionID)
    }

    private static func toolActivityLabel(_ activity: ToolActivity) -> String {
        switch activity.phase {
        case .started, .executing:
            return "Working"
        case .awaitingConfirmation:
            return "Waiting for approval"
        case .succeeded:
            return "Generating"
        case .failed, .cancelled:
            return "Generating"
        }
    }

    private func handleRecentTaskDueDateCorrection(_ input: String, context: ModelContext) -> Bool {
        guard let target = recentCreatedTaskCorrectionTarget,
              target.sessionID == selectedChat?.id,
              let correctedDate = TaskDueDateSemantics.correctionDate(from: input) else {
            return false
        }

        let taskID = target.taskID
        var descriptor = FetchDescriptor<KodaiTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        descriptor.fetchLimit = 1
        guard let task = try? context.fetch(descriptor).first else {
            recentCreatedTaskCorrectionTarget = nil
            return false
        }

        inputText = ""
        recentCreatedTaskCorrectionTarget = nil
        let currentSession = ensureCurrentChat(context: context)
        messages.append(ChatMessage(role: .user, text: input))
        saveStoredMessage(role: .user, content: input, in: currentSession, context: context)

        updateTaskDueDate(task, dueDate: correctedDate, context: context)
        let reply = "Updated task: \(task.title) (due \(shortDateString(correctedDate)))"
        messages.append(ChatMessage(role: .assistant, text: reply))
        saveStoredMessage(role: .assistant, content: reply, in: currentSession, context: context)
        return true
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

        guard let project = currentProject(context: context) else {
            reply("No active project — open a project chat or use /project to create one.")
            return
        }

        guard let queryTitle = command.title, !queryTitle.isEmpty else {
            let openTasks = (project.tasks ?? [])
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
        let matches = (project.tasks ?? []).filter { !$0.isCompleted && $0.title.lowercased().contains(query) }

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
