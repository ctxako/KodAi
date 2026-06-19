//
//  ChatViewModel.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Foundation
import KodaiKernel
import Observation
import UIKit

/// Slash command vocabulary, parsing, and picker metadata live in KodaiKernel;
/// this app executes the parsed intents.
typealias SlashCommand = KodaiSlashCommandMetadata

struct PendingSummaryConfirmation: Identifiable, Equatable {
    let id = UUID()
    let messageID: ChatMessage.ID
    let summary: String
}

/// One sampled-token decision captured for the interpretation/observation UI.
/// `text` is the emitted chunk so concatenating snapshots in order reproduces
/// the rendered message text, keeping the certainty heatmap aligned with what
/// the user actually sees.
struct TokenSnapshot: Identifiable {
    let id = UUID()
    let step: Int
    let text: String
    let alternatives: [TokenAlternative]
    /// True probability of the sampled token (raw, pre-sampling distribution).
    let selectedProbability: Float
    /// Full-vocab Shannon entropy in nats.
    let entropy: Float
    /// Top-1 minus top-2 probability.
    let margin: Float

    /// False for end-of-stream flush chunks that carry no distribution; those
    /// are excluded from confidence stats and drawn neutral in the heatmap.
    var isAnalyzed: Bool { !alternatives.isEmpty }

    /// The model's top-ranked candidate (what greedy decoding would pick).
    /// `alternatives` is probability-sorted, so the argmax is first.
    var greedyAlternative: TokenAlternative? { alternatives.first }

    /// True when sampling chose a token other than the model's top pick — a
    /// fork point where randomness changed the output.
    var divergedFromGreedy: Bool {
        isAnalyzed && !(alternatives.first?.isSelected ?? true)
    }
}

@Observable
@MainActor
final class ChatViewModel {
    private(set) var sessions: [ChatSession] = []
    private(set) var streams: [Stream] = []
    private(set) var activeSessionID: UUID?
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isGenerating: Bool = false
    private(set) var phase: InferencePhase = .idle
    private(set) var activeAssistantMessageID: ChatMessage.ID?
    private(set) var generatedTokenCount: Int = 0
    private(set) var summaryPhase: SummaryPhase?
    private(set) var exportSnapshot: ChatExportSnapshot?
    private(set) var warmupStatus: WarmupStatus?
    private(set) var pendingSummaryConfirmation: PendingSummaryConfirmation?
    private(set) var projects: [KodaiProjectLite] = []
    private(set) var selectedProjectID: UUID?
    private(set) var pendingToolProposal: PendingToolProposalLite?
    private(set) var recentActivityEvents: [ActivityEventLite] = []
    private(set) var latestContextSnapshot: ContextSnapshotLite?
    /// Per-message ordered token decisions. Survives generation so a completed
    /// message can be inspected later; pruned to the active thread on each send.
    private(set) var tokenHistories: [ChatMessage.ID: [TokenSnapshot]] = [:]

    /// Most recent real next-token distribution, used to seed the sampler
    /// playground's "Last token" source. Walks back from the newest message to
    /// the latest step that actually weighed more than one candidate.
    var latestTokenAlternatives: [TokenAlternative]? {
        for message in messages.reversed() {
            guard let history = tokenHistories[message.id] else { continue }
            if let snapshot = history.last(where: { $0.alternatives.count > 1 }) {
                return snapshot.alternatives
            }
        }
        return nil
    }

    var activeProcessSummary: InferenceProcessSummary? {
        guard activeAssistantMessageID != nil, phase != .idle else { return nil }

        return InferenceProcessSummary(
            finalPhase: phase,
            generatedTokenCount: max(generatedTokenCount, pendingGeneratedTokenCount),
            elapsedSeconds: sendStartedAt.map { Date().timeIntervalSince($0) },
            modelName: LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.expectedModelFileName,
            failureMessage: nil,
            phasesReached: currentPhaseHistory,
            diagnostics: currentDiagnostics
        )
    }

    var headerTelemetryText: String {
        "\(compactTokenCountText(estimatedTotalTokenCount)) · \(contextWindowPercentageText)"
    }

    var activeSession: ChatSession? {
        guard let activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    var selectedProject: KodaiProjectLite? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var activeAssistantMode: AssistantMode {
        activeSession?.assistantMode ?? .default
    }

    var favoriteStreams: [Stream] {
        streams
            .filter(\.isFavorite)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var settingsSnapshot: SettingsSnapshot {
        let configuration = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M
        let summaries = sessions.flatMap(\.messages).compactMap(\.processSummary)
        let generatedTokens = summaries.reduce(0) { $0 + $1.generatedTokenCount }
        let assistantResponses = sessions.flatMap(\.messages).filter { $0.role == .assistant }.count
        let totalMessages = sessions.reduce(0) { $0 + $1.messages.count }
        let lastSummary = summaries.last

        return SettingsSnapshot(
            shortDisplayName: configuration.shortDisplayName,
            modelName: configuration.expectedModelFileName,
            contextSize: Int(configuration.contextSize),
            maxOutputTokens: Int(configuration.maxGeneratedTokens),
            temperature: Double(configuration.temperature),
            topP: Double(configuration.topP),
            repeatPenalty: Double(configuration.repeatPenalty),
            currentPhase: phase.rawValue,
            backendName: "llama.cpp",
            lifetimeGeneratedTokens: generatedTokens,
            lifetimePromptTokens: nil,
            lifetimeAssistantTokens: generatedTokens,
            currentChatTokenEstimate: estimatedTotalTokenCount,
            contextUsagePercentage: contextWindowPercentageText,
            totalChats: sessions.count,
            totalStreams: streams.count,
            totalMessages: totalMessages,
            averageTokensPerResponse: assistantResponses > 0 ? Double(generatedTokens) / Double(assistantResponses) : nil,
            lastGenerationSpeed: lastSummary?.tokensPerSecond,
            lastGenerationDuration: lastSummary?.elapsedSeconds
        )
    }

    private var estimatedTotalTokenCount: Int {
        let totalCharacters = messages.reduce(0) { $0 + $1.text.count }
        return TokenEstimator.estimate(characterCount: totalCharacters)
    }

    private var contextWindowPercentageText: String {
        "\(contextPressurePercent)%"
    }

    private var contextPressurePercent: Int {
        let estimatedTokens = Double(estimatedTotalTokenCount)
        let maxTokens = Double(LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.contextSize)
        let percentage = maxTokens > 0 ? (estimatedTokens / maxTokens) * 100.0 : 0
        let clampedPercentage = min(max(percentage, 0), 100)
        return Int(clampedPercentage.rounded())
    }

    private func compactTokenCountText(_ tokenCount: Int) -> String {
        guard tokenCount >= 1_000 else { return "\(tokenCount)" }

        let value = Double(tokenCount) / 1_000.0
        return String(format: "%.1fk", value)
    }

    private let log = AppLog(category: "Chat")
    private let inferenceService = InferenceService()
    private let chatStore = ChatStore()
    // K2D: SwiftData-backed workspace store (falls back to JSON internally).
    private let projectTaskStore = WorkspaceProjectStore()
    private var generationTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var hideStatusTask: Task<Void, Never>?
    private var pendingAssistantText = ""
    private var pendingAssistantMessageID: ChatMessage.ID?
    private var pendingGeneratedTokenCount = 0
    private var pendingDistribution: TokenDistribution = .empty
    private var tokenSnapshotStep = 0
    private let maxTokenSnapshotsPerMessage = 2048
    private var currentPhaseHistory: [InferencePhase] = []
    private var currentDiagnostics: [String] = []
    private var generationHapticEventsByMessageID: [ChatMessage.ID: Set<GenerationHapticEvent>] = [:]
    private(set) var sendStartedAt: Date?
    private let uiFlushInterval: Duration = .milliseconds(75)
    private let summaryChunkCharacterLimit = 3_600

    init() {
        Task {
            await loadSessions()
        }
        Task {
            await loadProjects()
        }
        Task { [weak self] in
            guard let self else { return }
            await inferenceService.prewarm { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.setWarmupStatus(status)
                }
            }
        }
    }

    func send() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        if prompt.hasPrefix("/") {
            runSlashCommand(prompt)
            return
        }

        sendStartedAt = Date()
        log.event("send tapped", since: sendStartedAt)

        let localContextPromptBlock = buildLocalContextAndUpdateSnapshot(
            reason: "Sending message to local model"
        )

        messages.append(ChatMessage(role: .user, text: prompt))
        log.event("user message appended", since: sendStartedAt)

        messages.append(ChatMessage(role: .assistant, text: ""))
        guard let assistantMessageID = messages.last?.id else { return }
        log.event("assistant placeholder appended", since: sendStartedAt)
        let promptMessages = messages.filter { $0.id != assistantMessageID }
        updateActiveSession()
        saveSessions()

        inputText = ""
        isGenerating = true
        activeAssistantMessageID = assistantMessageID
        generatedTokenCount = 0
        tokenSnapshotStep = 0
        pendingDistribution = .empty
        pruneTokenHistories()
        currentPhaseHistory = []
        currentDiagnostics = []
        generationHapticEventsByMessageID[assistantMessageID] = []
        hideStatusTask?.cancel()
        playGenerationHaptic(.thinkingStarted, for: assistantMessageID)
        setPhase(.loadingModel)

        generationTask = Task { [weak self] in
            guard let self else { return }

            log.event("generation task started", since: sendStartedAt)

            do {
                var hasReceivedFirstToken = false
                let promptStack = makePromptStack(localContextPromptBlock: localContextPromptBlock)
                let stream = await inferenceService.generate(
                    messages: promptMessages,
                    promptStack: promptStack,
                    contextPressurePercent: contextPressurePercent
                )

                for try await event in stream {
                    if Task.isCancelled {
                        flushPendingAssistantText(reason: "cancelled")
                        cancelScheduledFlush()
                        return
                    }

                    switch event {
                    case .phase(let phase):
                        setPhase(phase)
                    case .warmup(let status):
                        setWarmupStatus(status)
                    case .diagnostic(let message):
                        appendDiagnostic(message)
                    case .tokenAlternatives(let distribution):
                        pendingDistribution = distribution
                    case .token(let chunk, let generatedTokenCount):
                        if !hasReceivedFirstToken {
                            hasReceivedFirstToken = true
                            clearWarmupStatus()
                            log.event("first token received", since: sendStartedAt)
                            playGenerationHaptic(.streamingStarted, for: assistantMessageID)
                        }
                        recordTokenSnapshot(chunk: chunk, for: assistantMessageID)
                        buffer(chunk, generatedTokenCount: generatedTokenCount, toAssistantMessage: assistantMessageID)
                    case .done(let finishReason):
                        resetTokenTrajectoryTracking()
                        flushPendingAssistantText(reason: "finished")
                        ensureAssistantHasVisibleText(for: assistantMessageID, finishReason: finishReason)
                        log.event("final assistant text length=\(assistantTextLength(for: assistantMessageID))", since: sendStartedAt)
                        setPhase(.completed)
                        playGenerationHaptic(.completed, for: assistantMessageID)
                        applyProcessSummary(to: assistantMessageID, finalPhase: .completed)
                        isGenerating = false
                        generationTask = nil
                        activeAssistantMessageID = nil
                        cancelScheduledFlush()
                        updateActiveSession()
                        saveSessions()
                    case .cancelled:
                        resetTokenTrajectoryTracking()
                        flushPendingAssistantText(reason: "cancelled")
                        log.event("final assistant text length=\(assistantTextLength(for: assistantMessageID))", since: sendStartedAt)
                        setPhase(.cancelled)
                        playGenerationHaptic(.cancelled, for: assistantMessageID)
                        applyProcessSummary(to: assistantMessageID, finalPhase: .cancelled)
                        removeEmptyAssistantMessageIfNeeded(assistantMessageID)
                        isGenerating = false
                        generationTask = nil
                        hideStatusAfterDelay()
                        cancelScheduledFlush()
                        updateActiveSession()
                        saveSessions()
                    case .completed, .error:
                        // Emitted only by the macOS FoundationModels backend; the iOS
                        // llama runtime signals end-of-turn via .done/.cancelled.
                        break
                    }
                }
            } catch {
                if Task.isCancelled {
                    cancelScheduledFlush()
                    return
                }

                resetTokenTrajectoryTracking()
                flushPendingAssistantText(reason: "failed")
                showFailure(error.localizedDescription, inAssistantMessage: assistantMessageID)
                log.event("final assistant text length=\(assistantTextLength(for: assistantMessageID))", since: sendStartedAt)
                setPhase(.failed)
                playGenerationHaptic(.failed, for: assistantMessageID)
                applyProcessSummary(to: assistantMessageID, finalPhase: .failed, failureMessage: error.localizedDescription)
                isGenerating = false
                generationTask = nil
                hideStatusAfterDelay()
                cancelScheduledFlush()
                updateActiveSession()
                saveSessions()
            }
        }
    }

    func dismissExportSheet() {
        exportSnapshot = nil
    }

    func cancelSummaryConfirmation() {
        guard let pendingSummaryConfirmation else { return }

        messages.removeAll { $0.id == pendingSummaryConfirmation.messageID }
        self.pendingSummaryConfirmation = nil
        updateActiveSession()
        saveSessions()
    }

    func confirmSummaryCompaction(summary: String) {
        let normalizedSummary = normalizedSummary(summary) ?? formattedEmptyConversationSummary()
        messages = [ChatMessage(role: .assistant, text: normalizedSummary)]
        pendingSummaryConfirmation = nil
        saveCurrentChatSummary(normalizedSummary)
        updateActiveSession()
        saveSessions()
    }

    func updateExportComment(for messageID: ChatMessage.ID, comment: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }

        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = messages[index]
        messages[index] = ChatMessage(
            id: message.id,
            role: message.role,
            text: message.text,
            createdAt: message.createdAt,
            processSummary: message.processSummary,
            exportComment: trimmedComment.isEmpty ? nil : trimmedComment
        )
        updateActiveSession()
        saveSessions()
    }

    func stop() {
        log.event("stop tapped", since: sendStartedAt)

        cancelActiveGeneration(flushPendingAssistantText: true)
        setPhase(.cancelled)
        if let activeAssistantMessageID {
            playGenerationHaptic(.cancelled, for: activeAssistantMessageID)
            applyProcessSummary(to: activeAssistantMessageID, finalPhase: .cancelled)
            removeEmptyAssistantMessageIfNeeded(activeAssistantMessageID)
        }
        updateActiveSession()
        saveSessions()
        hideStatusAfterDelay()
        log.event("generation cancelled", since: sendStartedAt)
    }

    func newChat() {
        newChat(streamID: nil)
    }

    func newChat(in streamID: Stream.ID) {
        guard streams.contains(where: { $0.id == streamID }) else { return }
        newChat(streamID: streamID)
    }

    func setActiveAssistantMode(_ mode: AssistantMode) {
        guard let activeSessionID else { return }
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        guard sessions[index].messages.isEmpty else { return }

        sessions[index].assistantMode = mode
        sessions[index].updatedAt = Date()
        saveSessions()
    }

    private func newChat(streamID: Stream.ID?) {
        log.event("new chat tapped", since: sendStartedAt)

        if isGenerating {
            cancelActiveGeneration(flushPendingAssistantText: false)
            if let activeAssistantMessageID {
                removeEmptyAssistantMessageIfNeeded(activeAssistantMessageID)
            }
            updateActiveSession()
            log.event("active generation cancelled for new chat", since: sendStartedAt)
        } else {
            clearPendingAssistantText()
            cancelScheduledFlush()
        }

        let session = ChatSession(streamID: streamID)
        sessions.insert(session, at: 0)
        if let streamID, let streamIndex = streams.firstIndex(where: { $0.id == streamID }) {
            streams[streamIndex].chatIDs.insert(session.id, at: 0)
            streams[streamIndex].updatedAt = Date()
        }
        activeSessionID = session.id
        messages.removeAll()
        saveSessions()
        if streamID != nil {
            saveStreams()
        }
        log.event("new chat created", since: sendStartedAt)

        isGenerating = false
        activeAssistantMessageID = nil
        generatedTokenCount = 0
        currentPhaseHistory = []
        setPhase(.idle)
        log.event("generation state reset for new chat", since: sendStartedAt)
    }

    func selectSession(_ session: ChatSession) {
        guard !isGenerating else { return }
        guard activeSessionID != session.id else { return }

        clearPendingAssistantText()
        cancelScheduledFlush()
        activeSessionID = session.id
        messages = messagesRemovingEmptyAssistantPlaceholders(from: session.messages)
        activeAssistantMessageID = nil
        generatedTokenCount = 0
        currentPhaseHistory = []
        setPhase(.idle)
    }

    func deleteSession(_ session: ChatSession) {
        guard !isGenerating else { return }
        deleteSessions(withIDs: Set([session.id]))
    }

    func togglePinSession(_ session: ChatSession) {
        guard !isGenerating else { return }
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }

        sessions[index].isPinned.toggle()
        sortSessions()
        saveSessions()
    }

    func renameSession(id: ChatSession.ID, title: String) {
        guard !isGenerating else { return }
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        sessions[index].title = normalizedChatTitle(title)
        saveSessions()
        log.event("chat renamed id=\(id)")
    }

    @discardableResult
    func createStream(title: String) -> Stream {
        let now = Date()
        let stream = Stream(
            title: normalizedStreamTitle(title),
            createdAt: now,
            updatedAt: now
        )
        streams.insert(stream, at: 0)
        saveStreams()
        log.event("stream created id=\(stream.id)")
        return stream
    }

    func renameStream(id: Stream.ID, title: String) {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return }

        streams[index].title = normalizedStreamTitle(title)
        streams[index].updatedAt = Date()
        saveStreams()
        log.event("stream renamed id=\(id)")
    }

    func toggleStreamFavorite(id: Stream.ID) {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return }

        streams[index].isFavorite.toggle()
        streams[index].updatedAt = Date()
        saveStreams()
        log.event("stream favorite toggled id=\(id) isFavorite=\(streams[index].isFavorite)")
    }

    func deleteStream(id: Stream.ID, deleteChats: Bool) {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return }

        let chatIDs = Set(streams[index].chatIDs)
        streams.remove(at: index)

        if deleteChats {
            deleteSessions(withIDs: chatIDs)
        } else {
            for sessionIndex in sessions.indices where chatIDs.contains(sessions[sessionIndex].id) {
                sessions[sessionIndex].streamID = nil
            }
            saveSessions()
        }

        saveStreams()
        log.event("stream deleted id=\(id) deleteChats=\(deleteChats)")
    }

    func assignChat(chatID: ChatSession.ID, streamID: Stream.ID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == chatID }) else { return }
        guard streams.contains(where: { $0.id == streamID }) else { return }

        if let oldStreamID = sessions[sessionIndex].streamID,
           let oldStreamIndex = streams.firstIndex(where: { $0.id == oldStreamID }) {
            streams[oldStreamIndex].chatIDs.removeAll { $0 == chatID }
            streams[oldStreamIndex].updatedAt = Date()
        }

        sessions[sessionIndex].streamID = streamID
        guard let streamIndex = streams.firstIndex(where: { $0.id == streamID }) else { return }
        if !streams[streamIndex].chatIDs.contains(chatID) {
            streams[streamIndex].chatIDs.append(chatID)
        }
        streams[streamIndex].updatedAt = Date()
        saveSessions()
        saveStreams()
        log.event("chat assigned to stream chatID=\(chatID) streamID=\(streamID)")
    }

    func assignCurrentChatToStream(_ streamID: Stream.ID) {
        guard streams.contains(where: { $0.id == streamID }) else { return }

        guard let activeSessionID, activeSession != nil else {
            newChat(streamID: streamID)
            return
        }

        assignChat(chatID: activeSessionID, streamID: streamID)
    }

    func removeChatFromStream(chatID: ChatSession.ID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == chatID }) else { return }
        guard let streamID = sessions[sessionIndex].streamID else { return }

        sessions[sessionIndex].streamID = nil
        if let streamIndex = streams.firstIndex(where: { $0.id == streamID }) {
            streams[streamIndex].chatIDs.removeAll { $0 == chatID }
            streams[streamIndex].updatedAt = Date()
        }

        saveSessions()
        saveStreams()
        log.event("chat removed from stream chatID=\(chatID) streamID=\(streamID)")
    }

    func chatsForStream(id: Stream.ID) -> [ChatSession] {
        guard let stream = streams.first(where: { $0.id == id }) else { return [] }

        let chatIDs = Set(stream.chatIDs)
        return sessions.filter { chatIDs.contains($0.id) }
    }

    func looseChats() -> [ChatSession] {
        sessions.filter { $0.streamID == nil }
    }

    func openChatSummary(chatID: ChatSession.ID) {
        log.event("chat summary opened chatID=\(chatID)")
    }

    func openStreamSummary(streamID: Stream.ID) {
        log.event("stream summary opened streamID=\(streamID)")
    }

    func updateChatSummary(chatID: ChatSession.ID) {
        guard !isGenerating else {
            log.event("summary skipped because generation is active chatID=\(chatID)")
            return
        }
        guard let index = sessions.firstIndex(where: { $0.id == chatID }) else { return }

        summaryPhase = .chat
        log.event("chat summary update started chatID=\(chatID)")
        let summary = deterministicChatSummary(for: sessions[index])
        sessions[index].summary = normalizedSummary(summary)
        sessions[index].updatedAt = Date()
        saveSessions()
        log.event("chat summary update completed chatID=\(chatID)")
        summaryPhase = nil
    }

    func saveChatSummary(chatID: ChatSession.ID, summary: String) {
        guard let index = sessions.firstIndex(where: { $0.id == chatID }) else { return }

        sessions[index].summary = normalizedSummary(summary)
        sessions[index].updatedAt = Date()
        saveSessions()
        log.event("chat summary saved chatID=\(chatID)")
    }

    func saveStreamSummary(streamID: Stream.ID, summary: String) {
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }

        let now = Date()
        streams[index].summary = normalizedSummary(summary)
        streams[index].updatedAt = now
        saveStreams()
        log.event("stream summary saved streamID=\(streamID)")
    }

    func rebuildStreamSummary(streamID: Stream.ID) {
        guard !isGenerating else {
            log.event("summary skipped because generation is active streamID=\(streamID)")
            return
        }
        guard let index = streams.firstIndex(where: { $0.id == streamID }) else { return }

        sendStartedAt = Date()
        summaryPhase = .stream
        isGenerating = true
        generatedTokenCount = 0
        pendingGeneratedTokenCount = 0
        currentPhaseHistory = []
        currentDiagnostics = []
        hideStatusTask?.cancel()
        setPhase(.loadingModel)
        log.event("stream summary rebuild started streamID=\(streamID)")

        let stream = streams[index]
        let streamChats = chatsForStream(id: streamID)
        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let summary = try await generateStreamSummary(for: stream, chats: streamChats)
                guard !Task.isCancelled else { return }
                guard let currentIndex = streams.firstIndex(where: { $0.id == streamID }) else {
                    isGenerating = false
                    summaryPhase = nil
                    generationTask = nil
                    return
                }

                let now = Date()
                streams[currentIndex].summary = normalizedSummary(summary)
                streams[currentIndex].updatedAt = now
                setPhase(.completed)
                saveStreams()
                log.event("stream summary rebuild completed streamID=\(streamID)")
                isGenerating = false
                summaryPhase = nil
                generationTask = nil
                hideStatusAfterDelay()
            } catch {
                if Task.isCancelled {
                    summaryPhase = nil
                    return
                }

                setPhase(.failed)
                log.event("stream summary rebuild failed streamID=\(streamID) error=\(error.localizedDescription)")
                isGenerating = false
                summaryPhase = nil
                generationTask = nil
                hideStatusAfterDelay()
            }
        }
    }

    private func cancelActiveGeneration(flushPendingAssistantText shouldFlushPendingAssistantText: Bool) {
        generationTask?.cancel()
        generationTask = nil
        if shouldFlushPendingAssistantText {
            flushPendingAssistantText(reason: "cancelled")
        } else {
            clearPendingAssistantText()
        }
        cancelScheduledFlush()
        hideStatusTask?.cancel()
        Task {
            await inferenceService.cancel()
        }
        isGenerating = false
        summaryPhase = nil
    }

    private func loadSessions() async {
        do {
            var loadedSessions = try await chatStore.loadSessions()
            var loadedStreams = try await chatStore.loadStreams()
            loadedSessions.sort(by: sessionSort)
            loadedSessions = loadedSessions.filter { hasRealMessages($0) }
            normalizeStreamMembership(sessions: &loadedSessions, streams: &loadedStreams)

            if loadedSessions.isEmpty {
                let session = ChatSession()
                sessions = [session]
                streams = loadedStreams
                activeSessionID = session.id
                messages = session.messages
                saveSessions()
                saveStreams()
                return
            }

            sessions = loadedSessions.map { session in
                var cleanedSession = session
                cleanedSession.messages = messagesRemovingEmptyAssistantPlaceholders(from: session.messages)
                return cleanedSession
            }
            streams = loadedStreams
            let session = ChatSession()
            sessions.insert(session, at: 0)
            activeSessionID = session.id
            messages = session.messages
            saveSessions()
            saveStreams()
        } catch {
            log.event("failed to load sessions: \(error.localizedDescription)")
            let session = ChatSession()
            sessions = [session]
            streams = []
            activeSessionID = session.id
            messages = session.messages
        }
    }

    // MARK: - Glass-box activity & context visibility (in-memory)

    private let maxRecentActivityEvents = 100

    func recordActivity(
        kind: ActivityKindLite,
        title: String,
        detail: String? = nil,
        projectID: UUID? = nil,
        taskID: UUID? = nil,
        source: ActivitySourceLite = .user
    ) {
        let event = ActivityEventLite(
            kind: kind,
            title: title,
            detail: detail,
            projectID: projectID,
            taskID: taskID,
            source: source
        )
        recentActivityEvents.insert(event, at: 0)
        if recentActivityEvents.count > maxRecentActivityEvents {
            recentActivityEvents.removeLast(recentActivityEvents.count - maxRecentActivityEvents)
        }
        log.event("activity recorded kind=\(kind.rawValue) source=\(source.rawValue)")
    }

    // MARK: - Lightweight local context injection (per-request, not persisted)

    /// Gathers the app-local data (selected project, due tasks, assistant
    /// mode, chat stats) for the shared KodaiKernel prompt builder. The
    /// formatting and action-rule wording live in KodaiKernel.
    private func makeLocalContextSnapshotValue() -> KodaiLocalContextSnapshotValue {
        KodaiLocalContextSnapshotValue(
            selectedProject: selectedProject,
            todayAndOverdueTasks: todayAndOverdueTasks(),
            assistantModeDescription: activeAssistantMode.title,
            currentMessageCount: messages.count,
            currentChatTokenEstimate: estimatedTotalTokenCount
        )
    }

    /// Builds the compact per-request context prompt via the shared kernel
    /// builder. Returned per-request only — never saved into chat history.
    /// Returns nil when there is nothing to inject.
    func buildLightweightContextPrompt() -> String? {
        KodaiLocalContextPromptBuilder.build(snapshot: makeLocalContextSnapshotValue()).promptBlock
    }

    /// Builds the prompt block once and refreshes the glass-box snapshot
    /// from the same kernel result.
    private func buildLocalContextAndUpdateSnapshot(reason: String) -> String? {
        let result = KodaiLocalContextPromptBuilder.build(snapshot: makeLocalContextSnapshotValue())
        latestContextSnapshot = ContextSnapshotLite(reason: reason, blocks: result.contextBlocks)
        return result.promptBlock
    }

    // MARK: - Projects & Tasks (lightweight iOS-local layer)

    @discardableResult
    func createProject(title: String, source: ActivitySourceLite = .user) -> KodaiProjectLite {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = KodaiProjectLite(title: trimmedTitle.isEmpty ? "New Project" : trimmedTitle)
        projects.insert(project, at: 0)
        saveProjects()
        log.event("project created id=\(project.id)")
        recordActivity(kind: .projectCreated, title: "Created project", detail: project.title, projectID: project.id, source: source)
        return project
    }

    func updateProjectTitle(projectID: UUID, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let previousTitle = projects[index].title
        projects[index].title = trimmedTitle
        projects[index].updatedAt = Date()
        saveProjects()
        recordActivity(kind: .projectRenamed, title: "Renamed project", detail: "\(previousTitle) → \(trimmedTitle)", projectID: projectID)
    }

    func deleteProject(projectID: UUID) {
        let deletedTitle = projects.first(where: { $0.id == projectID })?.title
        projects.removeAll { $0.id == projectID }
        if selectedProjectID == projectID {
            selectedProjectID = nil
        }
        saveProjects()
        log.event("project deleted id=\(projectID)")
        recordActivity(kind: .projectDeleted, title: "Deleted project", detail: deletedTitle, projectID: projectID)
    }

    func selectProject(projectID: UUID?) {
        selectedProjectID = projectID
    }

    func createTask(title: String, projectID: UUID, dueDate: Date? = nil, source: ActivitySourceLite = .user) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let task = KodaiTaskLite(title: trimmedTitle, dueDate: dueDate)
        projects[index].tasks.append(task)
        projects[index].updatedAt = Date()
        saveProjects()
        log.event("task created id=\(task.id) projectID=\(projectID)")
        recordActivity(kind: .taskCreated, title: "Created task", detail: trimmedTitle, projectID: projectID, taskID: task.id, source: source)
    }

    func toggleTaskCompletion(taskID: UUID, projectID: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let taskIndex = projects[projectIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let isNowCompleted = !projects[projectIndex].tasks[taskIndex].isCompleted
        projects[projectIndex].tasks[taskIndex].isCompleted = isNowCompleted
        projects[projectIndex].tasks[taskIndex].completedAt = isNowCompleted ? Date() : nil
        projects[projectIndex].tasks[taskIndex].updatedAt = Date()
        projects[projectIndex].updatedAt = Date()
        saveProjects()
        recordActivity(
            kind: isNowCompleted ? .taskCompleted : .taskReopened,
            title: isNowCompleted ? "Completed task" : "Reopened task",
            detail: projects[projectIndex].tasks[taskIndex].title,
            projectID: projectID,
            taskID: taskID
        )
    }

    func deleteTask(taskID: UUID, projectID: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let deletedTitle = projects[projectIndex].tasks.first(where: { $0.id == taskID })?.title
        projects[projectIndex].tasks.removeAll { $0.id == taskID }
        projects[projectIndex].updatedAt = Date()
        saveProjects()
        log.event("task deleted id=\(taskID) projectID=\(projectID)")
        recordActivity(kind: .taskDeleted, title: "Deleted task", detail: deletedTitle, projectID: projectID, taskID: taskID)
    }

    func setProjectDeadline(projectID: UUID, deadline: Date?) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].deadline = deadline
        projects[index].updatedAt = Date()
        saveProjects()
        log.event("project deadline updated id=\(projectID) hasDeadline=\(deadline != nil)")
        recordActivity(
            kind: .projectDeadlineChanged,
            title: deadline == nil ? "Cleared project deadline" : "Set project deadline",
            detail: deadline.map { "\(projects[index].title) · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? projects[index].title,
            projectID: projectID
        )
    }

    // MARK: - Today / Overdue

    func overdueTasks() -> [DueTaskItem] {
        collectDueItems().overdue
    }

    func tasksDueToday() -> [DueTaskItem] {
        collectDueItems().today
    }

    func todayAndOverdueTasks() -> [DueTaskItem] {
        let items = collectDueItems()
        return items.overdue + items.today
    }

    private func collectDueItems() -> (overdue: [DueTaskItem], today: [DueTaskItem]) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var overdue: [DueTaskItem] = []
        var today: [DueTaskItem] = []

        for project in projects {
            for task in project.tasks where !task.isCompleted {
                guard let dueDate = task.dueDate else { continue }
                if dueDate < startOfToday {
                    overdue.append(DueTaskItem(task: task, projectID: project.id, projectTitle: project.title, isOverdue: true))
                } else if calendar.isDateInToday(dueDate) {
                    today.append(DueTaskItem(task: task, projectID: project.id, projectTitle: project.title, isOverdue: false))
                }
            }
        }

        let byDueDate: (DueTaskItem, DueTaskItem) -> Bool = {
            ($0.task.dueDate ?? .distantPast) < ($1.task.dueDate ?? .distantPast)
        }
        return (overdue.sorted(by: byDueDate), today.sorted(by: byDueDate))
    }

    // MARK: - Tool Proposals (in-memory, deterministic trigger only for now)

    func proposeCreateTask(
        title: String,
        details: String? = nil,
        projectID: UUID? = nil,
        dueDate: Date? = nil,
        priority: TaskPriorityLite = .normal
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let resolvedProjectID = projectID ?? selectedProjectID
        let projectTitle = resolvedProjectID.flatMap { id in
            projects.first(where: { $0.id == id })?.title
        }

        pendingToolProposal = PendingToolProposalLite(
            kind: .createTask,
            title: "Create task",
            message: "Confirm to create this task.",
            createTask: CreateTaskProposalLite(
                title: trimmedTitle,
                details: details,
                projectID: resolvedProjectID,
                projectTitle: projectTitle,
                dueDate: dueDate,
                priority: priority
            )
        )
        log.event("tool proposal created kind=createTask")
        recordActivity(kind: .toolProposalCreated, title: "Proposed task", detail: trimmedTitle, projectID: resolvedProjectID, source: .proposal)
    }

    func confirmPendingToolProposal() {
        guard let proposal = pendingToolProposal else { return }
        pendingToolProposal = nil

        switch proposal.kind {
        case .createTask:
            guard let createTask = proposal.createTask else { return }

            let projectID: UUID
            if let proposedID = createTask.projectID, projects.contains(where: { $0.id == proposedID }) {
                projectID = proposedID
            } else if let selected = selectedProjectID, projects.contains(where: { $0.id == selected }) {
                projectID = selected
            } else if let inbox = projects.first(where: { $0.title == "Inbox" }) {
                projectID = inbox.id
            } else {
                let inbox = createProject(title: "Inbox")
                projectID = inbox.id
                selectProject(projectID: inbox.id)
            }

            performCreateTaskProposal(createTask, in: projectID)
        }
    }

    private func performCreateTaskProposal(_ proposal: CreateTaskProposalLite, in projectID: UUID) {
        recordActivity(kind: .toolProposalConfirmed, title: "Confirmed proposal", detail: proposal.title, projectID: projectID, source: .proposal)
        createTask(title: proposal.title, projectID: projectID, dueDate: proposal.dueDate, source: .proposal)
        let projectTitle = projects.first(where: { $0.id == projectID })?.title ?? "Unknown"
        var lines = ["Created task: \(proposal.title)", "Project: \(projectTitle)"]
        if let dueDate = proposal.dueDate {
            lines.append("Due: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        appendSystemMessage(lines.joined(separator: "\n"))
        updateActiveSession()
        saveSessions()
        log.event("tool proposal confirmed kind=createTask")
    }

    func cancelPendingToolProposal() {
        guard let proposal = pendingToolProposal else { return }
        pendingToolProposal = nil
        recordActivity(kind: .toolProposalCancelled, title: "Cancelled proposal", detail: proposal.createTask?.title, source: .proposal)
        appendSystemMessage("Cancelled proposal. No task was created.")
        updateActiveSession()
        saveSessions()
        log.event("tool proposal cancelled")
    }

    private func loadProjects() async {
        do {
            projects = try await projectTaskStore.loadProjects()
        } catch {
            log.event("failed to load projects: \(error.localizedDescription)")
            projects = []
        }
    }

    private func saveProjects() {
        let projectsToSave = projects
        Task {
            do {
                try await projectTaskStore.saveProjects(projectsToSave)
            } catch {
                log.event("failed to save projects: \(error.localizedDescription)")
            }
        }
    }

    private func makePromptStack(localContextPromptBlock: String? = nil) -> ModelPromptStack {
        ModelPromptStack(
            settings: ModelPromptSettings(assistantMode: activeAssistantMode),
            runtimeConstraintPromptBlock: nil,
            localContextPromptBlock: localContextPromptBlock
        )
    }

    nonisolated static func makeRuntimeConstraintSnapshot(
        ambientContext: AmbientContext?,
        contextPressurePercent: Int
    ) -> ConstraintSnapshot {
        var snapshot = ConstraintSnapshot()
        snapshot.internetAccessEnabled = false
        snapshot.lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        snapshot.thermalState = ProcessInfo.processInfo.thermalState
        snapshot.contextPressurePercent = contextPressurePercent
        snapshot.modelName = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.expectedModelFileName

        if let ambientContext {
            switch ambientContext.weatherStatus {
            case .fresh, .cached:
                snapshot.weatherAvailable = true
            case .unavailable:
                snapshot.weatherAvailable = false
                snapshot.weatherUnavailableReason = "no local weather data"
            case .failed:
                snapshot.weatherAvailable = false
                snapshot.weatherUnavailableReason = "lookup failed"
            }
        }

        return snapshot
    }

    private func updateActiveSession() {
        guard let activeSessionID else { return }
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }

        sessions[index].messages = messages
        if sessions[index].title == "New Chat" {
            sessions[index].title = title(for: messages)
        }
        sessions[index].updatedAt = Date()
        sortSessions()
    }

    private func openExportSheet() {
        log.event("export command detected")
        inputText = ""

        let session = activeSession
        let stream = session?.streamID.flatMap { streamID in
            streams.first { $0.id == streamID }
        }

        exportSnapshot = ChatExportSnapshot(
            chatTitle: session?.title,
            createdAt: session?.createdAt,
            updatedAt: session?.updatedAt,
            messages: messages,
            modelName: LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.expectedModelFileName,
            contextLimit: Int(LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.contextSize),
            streamID: stream?.id,
            streamTitle: stream?.title
        )
        log.event("export sheet opened")
    }

    private func runSlashCommand(_ prompt: String) {
        guard let parsed = KodaiSlashCommandParser.parse(prompt), parsed.kind != .unknown else {
            log.event("unknown slash command ignored command=\(prompt)")
            appendSystemMessage("Unknown command. Type /help to see available commands.")
            inputText = ""
            return
        }

        recordActivity(
            kind: .slashCommandHandled,
            title: "Handled \(parsed.normalizedCommandName)",
            detail: parsed.rawArgument,
            source: .slashCommand
        )

        switch parsed.kind {
        case .project:
            handleProjectCommand(argument: parsed.rawArgument)
        case .task:
            handleTaskCommand(parsed)
        case .done:
            handleDoneCommand(argument: parsed.rawArgument)
        case .proposeTask:
            handleProposeCommand(parsed)
        case .help, .commands:
            handleHelpCommand()
        case .export:
            openExportSheet()
        case .summary:
            summarizeCurrentChat()
        case .stats:
            showStatsMessage()
        case .tools:
            showToolsMessage()
        case .unknown:
            log.event("unhandled slash command command=\(parsed.normalizedCommandName)")
        }
    }

    private func handleProjectCommand(argument: String?) {
        inputText = ""
        guard let title = argument, !title.isEmpty else {
            appendSystemMessage("Usage: /project <title>")
            return
        }
        let project = createProject(title: title, source: .slashCommand)
        selectProject(projectID: project.id)
        appendSystemMessage("Created project: \(project.title)")
        updateActiveSession()
        saveSessions()
    }

    private func handleTaskCommand(_ parsed: KodaiParsedSlashCommand) {
        inputText = ""
        guard let title = parsed.title, !title.isEmpty else {
            appendSystemMessage("Usage: /task <title> [due:today|tomorrow|Jun20|6/20]")
            return
        }
        let dueDate = parsed.dueDate

        let projectID: UUID
        if let selected = selectedProjectID, projects.contains(where: { $0.id == selected }) {
            projectID = selected
        } else {
            if let inbox = projects.first(where: { $0.title == "Inbox" }) {
                projectID = inbox.id
            } else {
                let inbox = createProject(title: "Inbox")
                projectID = inbox.id
                selectProject(projectID: inbox.id)
            }
        }

        createTask(title: title, projectID: projectID, dueDate: dueDate, source: .slashCommand)
        let projectTitle = projects.first(where: { $0.id == projectID })?.title ?? "Unknown"
        var lines = ["Created task: \(title)", "Project: \(projectTitle)"]
        if let dueDate {
            lines.append("Due: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        appendSystemMessage(lines.joined(separator: "\n"))
        updateActiveSession()
        saveSessions()
    }

    private func handleDoneCommand(argument: String?) {
        inputText = ""
        guard let query = argument, !query.isEmpty else {
            appendSystemMessage("Usage: /done <task title>")
            return
        }

        let queryLower = query.lowercased()

        if let selectedProjectID,
           let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }),
           let taskIndex = projects[projectIndex].tasks.firstIndex(where: {
               !$0.isCompleted && $0.title.lowercased().contains(queryLower)
           }) {
            let task = projects[projectIndex].tasks[taskIndex]
            projects[projectIndex].tasks[taskIndex].isCompleted = true
            projects[projectIndex].tasks[taskIndex].completedAt = Date()
            projects[projectIndex].tasks[taskIndex].updatedAt = Date()
            projects[projectIndex].updatedAt = Date()
            saveProjects()
            recordActivity(kind: .taskCompleted, title: "Completed task", detail: task.title, projectID: projects[projectIndex].id, taskID: task.id, source: .slashCommand)
            appendSystemMessage("Completed task: \(task.title)")
            updateActiveSession()
            saveSessions()
            return
        }

        for projectIndex in projects.indices {
            if let taskIndex = projects[projectIndex].tasks.firstIndex(where: {
                !$0.isCompleted && $0.title.lowercased().contains(queryLower)
            }) {
                let task = projects[projectIndex].tasks[taskIndex]
                projects[projectIndex].tasks[taskIndex].isCompleted = true
                projects[projectIndex].tasks[taskIndex].completedAt = Date()
                projects[projectIndex].tasks[taskIndex].updatedAt = Date()
                projects[projectIndex].updatedAt = Date()
                saveProjects()
                recordActivity(kind: .taskCompleted, title: "Completed task", detail: task.title, projectID: projects[projectIndex].id, taskID: task.id, source: .slashCommand)
                appendSystemMessage("Completed task: \(task.title)\nProject: \(projects[projectIndex].title)")
                updateActiveSession()
                saveSessions()
                return
            }
        }

        appendSystemMessage("No incomplete task matching \"\(query)\" was found.")
        updateActiveSession()
        saveSessions()
    }

    private func handleProposeCommand(_ parsed: KodaiParsedSlashCommand) {
        inputText = ""
        guard parsed.rawArgument != nil else {
            appendSystemMessage("Usage: /propose task <title> [due:today|tomorrow|Jun20|6/20]")
            return
        }

        guard let title = parsed.title, !title.isEmpty else {
            appendSystemMessage("Usage: /propose task <title> [due:today|tomorrow|Jun20|6/20]")
            updateActiveSession()
            saveSessions()
            return
        }

        proposeCreateTask(title: title, dueDate: parsed.dueDate)
        updateActiveSession()
        saveSessions()
    }

    private func handleHelpCommand() {
        inputText = ""
        let helpText = [
            "Available commands:",
            "",
            "/project <title> — Create a new project",
            "/task <title> — Create a task in the current project",
            "/task <title> due:today — Create a task due today",
            "/task <title> due:tomorrow — Create a task due tomorrow",
            "/task <title> due:Jun20 — Create a task due on a date",
            "/task <title> due:6/20 — Create a task due on a date",
            "/done <title> — Complete a task by name",
            "/propose task <title> — Propose a task to confirm or cancel",
            "/help — Show this list",
            "/commands — Show this list",
            "/summary — Summarize current chat",
            "/export — Export chat as Markdown",
            "/stats — Show chat/session stats",
            "/tools — Show local tool status"
        ].joined(separator: "\n")
        appendSystemMessage(helpText)
        updateActiveSession()
        saveSessions()
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text))
    }

    private func summarizeCurrentChat() {
        log.event("summary command detected")
        inputText = ""
        guard !messages.isEmpty else {
            let emptySummary = formattedEmptyConversationSummary()
            messages.append(ChatMessage(role: .assistant, text: emptySummary))
            if let assistantMessageID = messages.last?.id {
                pendingSummaryConfirmation = PendingSummaryConfirmation(
                    messageID: assistantMessageID,
                    summary: emptySummary
                )
            }
            updateActiveSession()
            saveSessions()
            return
        }

        sendStartedAt = Date()
        let sourceMessages = messages
        messages.append(ChatMessage(role: .assistant, text: ""))
        guard let assistantMessageID = messages.last?.id else { return }

        isGenerating = true
        summaryPhase = .chat
        activeAssistantMessageID = assistantMessageID
        generatedTokenCount = 0
        pendingGeneratedTokenCount = 0
        currentPhaseHistory = []
        currentDiagnostics = []
        generationHapticEventsByMessageID[assistantMessageID] = []
        hideStatusTask?.cancel()
        playGenerationHaptic(.thinkingStarted, for: assistantMessageID)
        setPhase(.loadingModel)

        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let summary = try await generateConversationSummary(from: sourceMessages)
                guard !Task.isCancelled else { return }

                setAssistantMessage(assistantMessageID, text: summary)
                setPhase(.completed)
                playGenerationHaptic(.completed, for: assistantMessageID)
                applyProcessSummary(to: assistantMessageID, finalPhase: .completed)
                pendingSummaryConfirmation = PendingSummaryConfirmation(
                    messageID: assistantMessageID,
                    summary: summary
                )
                isGenerating = false
                summaryPhase = nil
                generationTask = nil
                activeAssistantMessageID = nil
                cancelScheduledFlush()
                updateActiveSession()
                saveSessions()
            } catch {
                if Task.isCancelled {
                    cancelScheduledFlush()
                    summaryPhase = nil
                    return
                }

                showFailure(error.localizedDescription, inAssistantMessage: assistantMessageID)
                setPhase(.failed)
                playGenerationHaptic(.failed, for: assistantMessageID)
                applyProcessSummary(to: assistantMessageID, finalPhase: .failed, failureMessage: error.localizedDescription)
                isGenerating = false
                summaryPhase = nil
                generationTask = nil
                hideStatusAfterDelay()
                cancelScheduledFlush()
                updateActiveSession()
                saveSessions()
            }
        }
    }

    private func generateConversationSummary(from sourceMessages: [ChatMessage]) async throws -> String {
        let chunks = transcriptChunks(from: sourceMessages)
        var partialSummaries: [String]

        if chunks.count > 1 {
            partialSummaries = try await summarizedChunks(chunks)
        } else {
            partialSummaries = chunks
        }

        while partialSummaries.joined(separator: "\n\n").count > summaryChunkCharacterLimit, partialSummaries.count > 1 {
            let previousCharacterCount = partialSummaries.joined(separator: "\n\n").count
            let reducedSummaries = try await summarizedChunks(partialSummaries)
            partialSummaries = reducedSummaries
            guard reducedSummaries.joined(separator: "\n\n").count < previousCharacterCount else { break }
        }

        let finalTranscript = partialSummaries.joined(separator: "\n\n")
        let finalPrompt = summaryPrompt(
            transcript: finalTranscript,
            instructionPrefix: "You are summarizing the current chat thread for future reference. Produce the final summary in exactly this format:\n\nConversation Summary\n\nMain topic:\n...\n\nKey decisions:\n...\n\nImportant details:\n...\n\nUnresolved questions:\n...\n\nNext steps:\n..."
        )
        let summary = try await generatedSummaryText(for: finalPrompt)
        let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("Conversation Summary") ? normalized : "Conversation Summary\n\n\(normalized)"
    }

    private func generateStreamSummary(for stream: Stream, chats: [ChatSession]) async throws -> String {
        let sources = streamSummarySources(from: chats)
        guard !sources.isEmpty else {
            return "Main Summary\n\nThis stream does not have enough chat content to summarize yet."
        }

        var partialSummaries = streamSummaryChunks(from: sources)

        if partialSummaries.count > 1 {
            partialSummaries = try await summarizedStreamChunks(partialSummaries)
        }

        while partialSummaries.joined(separator: "\n\n").count > summaryChunkCharacterLimit, partialSummaries.count > 1 {
            let previousCharacterCount = partialSummaries.joined(separator: "\n\n").count
            let reducedSummaries = try await summarizedStreamChunks(partialSummaries)
            partialSummaries = reducedSummaries
            guard reducedSummaries.joined(separator: "\n\n").count < previousCharacterCount else { break }
        }

        let finalPrompt = streamSummaryPrompt(
            streamTitle: stream.title,
            sourceText: partialSummaries.joined(separator: "\n\n"),
            instructionPrefix: """
            You are summarizing all chats inside one stream. Produce a useful stream-level summary based only on the provided chat summaries, titles, and message excerpts. Start with a short Main Summary paragraph. Then add categorized bullets only where helpful, such as Decisions, Features Discussed, Open Tasks, Bugs/Issues, Design Preferences, Technical Constraints, and Next Steps. Merge duplicate ideas. Preserve specific feature names, files, UI locations, constraints, and decisions. Do not invent facts. If information is missing, omit it.
            """
        )
        let summary = try await generatedSummaryText(for: finalPrompt)
        let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("Main Summary") ? normalized : "Main Summary\n\n\(normalized)"
    }

    private func summarizedStreamChunks(_ chunks: [String]) async throws -> [String] {
        var summaries: [String] = []

        for (index, chunk) in chunks.enumerated() {
            let prompt = streamSummaryPrompt(
                streamTitle: nil,
                sourceText: chunk,
                instructionPrefix: "Summarize stream source chunk \(index + 1) of \(chunks.count). Keep only useful facts, decisions, constraints, open tasks, and technical details. Do not invent facts."
            )
            summaries.append(try await generatedSummaryText(for: prompt))
        }

        return summaries
    }

    private func summarizedChunks(_ chunks: [String]) async throws -> [String] {
        var summaries: [String] = []

        for (index, chunk) in chunks.enumerated() {
            let prompt = summaryPrompt(
                transcript: chunk,
                instructionPrefix: "Summarize this older chunk \(index + 1) of \(chunks.count) from the current chat. Keep useful technical details and do not invent facts."
            )
            summaries.append(try await generatedSummaryText(for: prompt))
        }

        return summaries
    }

    private func generatedSummaryText(for prompt: String) async throws -> String {
        var summary = ""
        let stream = await inferenceService.generate(
            messages: [ChatMessage(role: .user, text: prompt)],
            promptStack: makePromptStack(),
            contextPressurePercent: contextPressurePercent
        )

        for try await event in stream {
            if Task.isCancelled {
                throw CancellationError()
            }

            switch event {
            case .phase(let phase):
                setPhase(phase)
            case .warmup(let status):
                setWarmupStatus(status)
            case .diagnostic(let message):
                appendDiagnostic(message)
            case .tokenAlternatives:
                break
            case .token(let chunk, let generatedTokenCount):
                summary += chunk
                self.generatedTokenCount = generatedTokenCount
            case .done, .cancelled, .completed, .error:
                break
            }
        }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSummary.isEmpty ? formattedEmptyConversationSummary() : trimmedSummary
    }

    private func summaryPrompt(transcript: String, instructionPrefix: String) -> String {
        """
        \(instructionPrefix)

        You are summarizing the current chat thread for future reference. Produce an accurate, compact summary. Include the main topic, key decisions, important details, unresolved questions, and next steps. Do not invent facts. Preserve useful technical details, filenames, feature names, constraints, and user preferences. If the chat is long, prioritize information that would help continue the conversation later.

        Current chat transcript:
        \(transcript)
        """
    }

    private func streamSummaryPrompt(streamTitle: String?, sourceText: String, instructionPrefix: String) -> String {
        """
        \(instructionPrefix)

        Stream title:
        \(streamTitle ?? "Unavailable")

        Stream chat sources:
        \(sourceText)
        """
    }

    private func streamSummarySources(from chats: [ChatSession]) -> [String] {
        chats.compactMap { chat in
            if let summary = normalizedSummary(chat.summary ?? "") {
                return """
                Chat: \(chat.title)
                Existing chat summary:
                \(summary)
                """
            }

            let excerpts = streamMessageExcerpts(from: chat.messages)
            guard !excerpts.isEmpty || chat.title != "New Chat" else { return nil }

            return """
            Chat: \(chat.title)
            Message excerpts:
            \(excerpts)
            """
        }
    }

    private func streamMessageExcerpts(from messages: [ChatMessage]) -> String {
        let relevantMessages = Array(messagesRemovingEmptyAssistantPlaceholders(from: messages).suffix(8))
        return relevantMessages
            .map { message in
                let excerpt = condensedSummaryFragment(message.text, limit: 420)
                return "\(message.role.rawValue.capitalized): \(excerpt)"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func streamSummaryChunks(from sources: [String]) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        for source in sources {
            let candidate = currentChunk.isEmpty ? source : "\(currentChunk)\n\n\(source)"
            if candidate.count > summaryChunkCharacterLimit, !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = source
            } else {
                currentChunk = candidate
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private func transcriptChunks(from sourceMessages: [ChatMessage]) -> [String] {
        let transcriptLines = sourceMessages.map { message in
            "\(message.role.rawValue.capitalized): \(message.text)"
        }

        var chunks: [String] = []
        var currentChunk = ""

        for line in transcriptLines {
            let candidate = currentChunk.isEmpty ? line : "\(currentChunk)\n\n\(line)"
            if candidate.count > summaryChunkCharacterLimit, !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = line
            } else {
                currentChunk = candidate
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private func formattedEmptyConversationSummary() -> String {
        """
        Conversation Summary

        Main topic:
        No prior messages in this chat.

        Key decisions:
        None.

        Important details:
        None.

        Unresolved questions:
        None.

        Next steps:
        None.
        """
    }

    private func saveCurrentChatSummary(_ summary: String) {
        guard let activeSessionID else { return }
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }

        sessions[index].summary = normalizedSummary(summary)
        sessions[index].updatedAt = Date()
    }

    private func showStatsMessage() {
        log.event("stats command detected")
        inputText = ""

        let settings = settingsSnapshot
        let speedText = settings.lastGenerationSpeed.map { String(format: "%.1f tok/s", $0) } ?? "Unavailable"
        let durationText = settings.lastGenerationDuration.map { "\((Int($0.rounded())))s" } ?? "Unavailable"
        let statsText = [
            "Chat stats",
            "- Current chat messages: \(messages.count)",
            "- Current chat estimate: \(estimatedTotalTokenCount) tokens",
            "- Context usage: \(contextWindowPercentageText)",
            "- Total chats: \(settings.totalChats)",
            "- Total messages: \(settings.totalMessages)",
            "- Last generation speed: \(speedText)",
            "- Last duration: \(durationText)"
        ].joined(separator: "\n")

        messages.append(ChatMessage(role: .assistant, text: statsText))
        updateActiveSession()
    }

    private func showToolsMessage() {
        log.event("tools command detected")
        inputText = ""

        messages.append(ChatMessage(
            role: .assistant,
            text: "Tools are local app events in this build. /tools was handled locally and was not sent to the model."
        ))
        updateActiveSession()
    }

    private func removeEmptyAssistantMessageIfNeeded(_ id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[index].role == .assistant else { return }
        guard messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        messages.remove(at: index)
    }

    private func messagesRemovingEmptyAssistantPlaceholders(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { message in
            !(message.role == .assistant && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func saveSessions() {
        let sessionsToSave = sessions.filter { hasRealMessages($0) }
        Task {
            do {
                try await chatStore.saveSessions(sessionsToSave)
            } catch {
                log.event("failed to save sessions: \(error.localizedDescription)")
            }
        }
    }

    private func hasRealMessages(_ session: ChatSession) -> Bool {
        session.messages.contains { message in
            (message.role == .user || message.role == .assistant)
                && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func saveStreams() {
        let streamsToSave = streams
        Task {
            do {
                try await chatStore.saveStreams(streamsToSave)
            } catch {
                log.event("failed to save streams: \(error.localizedDescription)")
            }
        }
    }

    private func deleteSessions(withIDs ids: Set<ChatSession.ID>) {
        guard !ids.isEmpty else { return }

        let activeSessionWasDeleted = activeSessionID.map { ids.contains($0) } ?? false
        sessions.removeAll { ids.contains($0.id) }

        for streamIndex in streams.indices {
            streams[streamIndex].chatIDs.removeAll { ids.contains($0) }
            streams[streamIndex].updatedAt = Date()
        }

        if sessions.isEmpty {
            let replacement = ChatSession()
            sessions = [replacement]
            activeSessionID = replacement.id
            messages.removeAll()
        } else if activeSessionWasDeleted {
            let nextSession = sessions[0]
            activeSessionID = nextSession.id
            messages = nextSession.messages
        }

        saveSessions()
        saveStreams()
    }

    private func normalizeStreamMembership(sessions: inout [ChatSession], streams: inout [Stream]) {
        let sessionIDs = Set(sessions.map(\.id))
        let streamIDs = Set(streams.map(\.id))
        var sessionStreamIDs: [ChatSession.ID: Stream.ID] = [:]

        for streamIndex in streams.indices {
            var uniqueChatIDs: [ChatSession.ID] = []
            var seenChatIDs = Set<ChatSession.ID>()

            for chatID in streams[streamIndex].chatIDs where sessionIDs.contains(chatID) && !seenChatIDs.contains(chatID) {
                uniqueChatIDs.append(chatID)
                seenChatIDs.insert(chatID)
                sessionStreamIDs[chatID] = streams[streamIndex].id
            }

            streams[streamIndex].chatIDs = uniqueChatIDs
        }

        for sessionIndex in sessions.indices {
            if let streamID = sessionStreamIDs[sessions[sessionIndex].id] {
                sessions[sessionIndex].streamID = streamID
            } else if let streamID = sessions[sessionIndex].streamID, streamIDs.contains(streamID) {
                sessions[sessionIndex].streamID = streamID
                if let streamIndex = streams.firstIndex(where: { $0.id == streamID }),
                   !streams[streamIndex].chatIDs.contains(sessions[sessionIndex].id) {
                    streams[streamIndex].chatIDs.append(sessions[sessionIndex].id)
                }
            } else {
                sessions[sessionIndex].streamID = nil
            }
        }
    }

    private func normalizedStreamTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled Stream" : trimmedTitle
    }

    private func normalizedSummary(_ summary: String) -> String? {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSummary.isEmpty ? nil : trimmedSummary
    }

    private func deterministicChatSummary(for session: ChatSession) -> String {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstUserMessage = session.messages.first { $0.role == .user }?.text
        let latestAssistantResponse = session.messages.last { $0.role == .assistant }?.text

        var parts: [String] = []
        if !title.isEmpty && title != "New Chat" {
            parts.append("Chat about \(condensedSummaryFragment(title, limit: 48))")
        }
        if let firstUserMessage {
            let fragment = condensedSummaryFragment(firstUserMessage, limit: 72)
            if !fragment.isEmpty {
                parts.append("User asked: \(fragment)")
            }
        }
        if let latestAssistantResponse {
            let fragment = condensedSummaryFragment(latestAssistantResponse, limit: 84)
            if !fragment.isEmpty {
                parts.append("Latest answer: \(fragment)")
            }
        }

        return parts.prefix(3).joined(separator: ". ")
    }

    private func deterministicStreamSummary(for stream: Stream) -> String {
        let summaries = stream.chatIDs.compactMap { chatID in
            sessions.first(where: { $0.id == chatID })?.summary?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        if summaries.isEmpty {
            return ""
        }

        if summaries.count < 2 {
            return condensedSummaryFragment(summaries[0], limit: 140)
        }

        let combined = summaries
            .prefix(4)
            .map { condensedSummaryFragment($0, limit: 80) }
            .joined(separator: " ")
        return "Stream combines \(summaries.count) chat summaries: \(combined)"
    }

    private func condensedSummaryFragment(_ text: String, limit: Int) -> String {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > limit else { return collapsed }

        let prefix = collapsed.prefix(limit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func sortSessions() {
        sessions.sort(by: sessionSort)
    }

    private func sessionSort(_ lhs: ChatSession, _ rhs: ChatSession) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    private func title(for messages: [ChatMessage]) -> String {
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return "New Chat"
        }

        let trimmedTitle = firstUserMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard !trimmedTitle.isEmpty else { return "New Chat" }
        guard trimmedTitle.count > 40 else { return trimmedTitle }

        return String(trimmedTitle.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedChatTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "New Chat" : trimmedTitle
    }

    private func setPhase(_ newPhase: InferencePhase) {
        guard phase != newPhase else { return }

        phase = newPhase
        if activeAssistantMessageID != nil, currentPhaseHistory.last != newPhase {
            currentPhaseHistory.append(newPhase)
        }
        log.event("phase=\(newPhase.logValue)", since: sendStartedAt)
    }

    private func appendDiagnostic(_ message: String) {
        guard currentDiagnostics.last != message else { return }
        currentDiagnostics.append(message)
    }

    private func playGenerationHaptic(_ event: GenerationHapticEvent, for messageID: ChatMessage.ID) {
        var events = generationHapticEventsByMessageID[messageID, default: []]
        guard !events.contains(event) else { return }

        events.insert(event)
        generationHapticEventsByMessageID[messageID] = events
        GenerationHaptics.play(event)
    }

    private func append(_ text: String, toAssistantMessage id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }

        let message = messages[index]
        messages[index] = ChatMessage(
            id: message.id,
            role: message.role,
            text: message.text + text,
            createdAt: message.createdAt,
            processSummary: message.processSummary,
            exportComment: message.exportComment
        )
    }

    private func setAssistantMessage(_ id: ChatMessage.ID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }

        let message = messages[index]
        messages[index] = ChatMessage(
            id: message.id,
            role: message.role,
            text: text,
            createdAt: message.createdAt,
            processSummary: message.processSummary,
            exportComment: message.exportComment
        )
    }

    private func showFailure(_ message: String, inAssistantMessage id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[index].text.isEmpty else { return }

        let existingMessage = messages[index]
        messages[index] = ChatMessage(
            id: existingMessage.id,
            role: existingMessage.role,
            text: message,
            createdAt: existingMessage.createdAt,
            processSummary: existingMessage.processSummary,
            exportComment: existingMessage.exportComment
        )
    }

    private func ensureAssistantHasVisibleText(
        for id: ChatMessage.ID,
        finishReason: GenerationFinishReason
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let fallback: String
        #if DEBUG
        switch finishReason {
        case .endOfGenerationToken:
            fallback = "[debug] model emitted EOG before generating visible text"
        case .textualStopString:
            fallback = "[debug] stop string fired before generating visible text"
        default:
            fallback = "I didn't generate a response. Try rephrasing that."
        }
        #else
        fallback = "I didn't generate a response. Try rephrasing that."
        #endif

        let existingMessage = messages[index]
        messages[index] = ChatMessage(
            id: existingMessage.id,
            role: existingMessage.role,
            text: fallback,
            createdAt: existingMessage.createdAt,
            processSummary: existingMessage.processSummary,
            exportComment: existingMessage.exportComment
        )
    }

    private func applyProcessSummary(
        to id: ChatMessage.ID,
        finalPhase: InferencePhase,
        failureMessage: String? = nil
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }

        let message = messages[index]
        messages[index] = ChatMessage(
            id: message.id,
            role: message.role,
            text: message.text,
            createdAt: message.createdAt,
            processSummary: InferenceProcessSummary(
                finalPhase: finalPhase,
                generatedTokenCount: max(generatedTokenCount, pendingGeneratedTokenCount),
                elapsedSeconds: sendStartedAt.map { Date().timeIntervalSince($0) },
                modelName: LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.expectedModelFileName,
                failureMessage: failureMessage,
                phasesReached: currentPhaseHistory,
                diagnostics: currentDiagnostics
            ),
            exportComment: message.exportComment
        )
    }

    private func buffer(_ text: String, generatedTokenCount: Int, toAssistantMessage id: ChatMessage.ID) {
        pendingAssistantMessageID = id
        pendingAssistantText += text
        pendingGeneratedTokenCount = generatedTokenCount
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }

        let interval = uiFlushInterval
        flushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }

            self?.flushPendingAssistantText(reason: "timer")
        }
    }

    private func flushPendingAssistantText(reason: String) {
        flushTask = nil

        guard !pendingAssistantText.isEmpty, let pendingAssistantMessageID else { return }

        let text = pendingAssistantText
        pendingAssistantText = ""
        generatedTokenCount = pendingGeneratedTokenCount
        append(text, toAssistantMessage: pendingAssistantMessageID)
        log.event("ui flush reason=\(reason) chars=\(text.count) text=\(text.debugDescription)", since: sendStartedAt)
        log.event("assistant text after UI flush chars=\(assistantTextLength(for: pendingAssistantMessageID))", since: sendStartedAt)
    }

    private func cancelScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
    }

    private func clearPendingAssistantText() {
        pendingAssistantText = ""
        pendingAssistantMessageID = nil
        pendingGeneratedTokenCount = 0
    }

    /// Captures the current token decision against the active assistant message.
    /// `.tokenAlternatives` always immediately precedes its `.token` in the
    /// stream, so the stashed `pendingTokenAlternatives` belong to this chunk.
    private func recordTokenSnapshot(chunk: String, for id: ChatMessage.ID) {
        let snapshot = TokenSnapshot(
            step: tokenSnapshotStep,
            text: chunk,
            alternatives: pendingDistribution.alternatives,
            selectedProbability: pendingDistribution.selectedProbability,
            entropy: pendingDistribution.entropy,
            margin: pendingDistribution.margin
        )
        tokenSnapshotStep += 1
        pendingDistribution = .empty

        var history = tokenHistories[id, default: []]
        history.append(snapshot)
        if history.count > maxTokenSnapshotsPerMessage {
            history.removeFirst(history.count - maxTokenSnapshotsPerMessage)
        }
        tokenHistories[id] = history
    }

    private func resetTokenTrajectoryTracking() {
        pendingDistribution = .empty
        tokenSnapshotStep = 0
    }

    /// Keeps only histories for messages still present in the active thread so
    /// the in-memory map stays bounded across a long session.
    private func pruneTokenHistories() {
        let liveIDs = Set(messages.map(\.id))
        tokenHistories = tokenHistories.filter { liveIDs.contains($0.key) }
    }

    private func assistantTextLength(for id: ChatMessage.ID) -> Int {
        messages.first(where: { $0.id == id })?.text.count ?? 0
    }

    private func hideStatusAfterDelay() {
        hideStatusTask?.cancel()
        hideStatusTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            self?.activeAssistantMessageID = nil
            self?.generatedTokenCount = 0
        }
    }

    private func setWarmupStatus(_ status: WarmupStatus) {
        warmupStatus = status
    }

    func clearWarmupStatus() {
        warmupStatus = nil
    }
}

struct SettingsSnapshot: Equatable {
    let shortDisplayName: String
    let modelName: String
    let contextSize: Int
    let maxOutputTokens: Int?
    let temperature: Double?
    let topP: Double?
    let repeatPenalty: Double?
    let currentPhase: String?
    let backendName: String?
    let lifetimeGeneratedTokens: Int?
    let lifetimePromptTokens: Int?
    let lifetimeAssistantTokens: Int?
    let currentChatTokenEstimate: Int
    let contextUsagePercentage: String
    let totalChats: Int
    let totalStreams: Int
    let totalMessages: Int
    let averageTokensPerResponse: Double?
    let lastGenerationSpeed: Double?
    let lastGenerationDuration: TimeInterval?
}

enum AssistantMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default`
    case creative
    case analytical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return "Default"
        case .creative:
            return "Creative"
        case .analytical:
            return "Analytical"
        }
    }

    var prompt: String {
        switch self {
        case .default:
            return "Mode: Default. Be balanced, direct, and useful. Answer harmless casual, technical, gameplay, planning, and creative questions normally. Do not over-refuse."
        case .creative:
            return "Mode: Creative. Be playful, exploratory, idea-focused, and good at story writing, brainstorming, naming, worldbuilding, gameplay hypotheticals, and loose thinking. Ask at most one helpful follow-up only when needed."
        case .analytical:
            return "Mode: Analytical. Be precise, structured, and technical. Lead with direct conclusions. Minimize fluff. Be good at debugging, comparisons, architecture, decisions, and factual breakdowns."
        }
    }
}

struct ModelPromptSettings: Codable, Equatable, Sendable {
    var assistantMode: AssistantMode

    static let compactRuntimePrompt = "You are Kodai, a concise local assistant. Be direct, practical, and useful. Answer harmless requests normally. Refuse only clearly harmful real-world requests. If uncertain, say why briefly."

    enum CodingKeys: String, CodingKey {
        case assistantMode
    }

    init(assistantMode: AssistantMode = .default) {
        self.assistantMode = assistantMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assistantMode = try container.decodeIfPresent(AssistantMode.self, forKey: .assistantMode) ?? .default
    }

    static let `default` = ModelPromptSettings()
}

struct ModelPromptStack: Equatable, Sendable {
    var settings: ModelPromptSettings
    var runtimeConstraintPromptBlock: String?
    var localContextPromptBlock: String?
    var ambientContext: AmbientContext?

    var runtimeSystemPrompt: String {
        [
            ModelPromptSettings.compactRuntimePrompt,
            runtimeConstraintPromptBlock,
            settings.assistantMode.prompt,
            localContextPromptBlock,
            ambientContext?.promptBlock
        ].compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func withAmbientContext(_ ambientContext: AmbientContext) -> ModelPromptStack {
        ModelPromptStack(
            settings: settings,
            runtimeConstraintPromptBlock: runtimeConstraintPromptBlock,
            localContextPromptBlock: localContextPromptBlock,
            ambientContext: ambientContext
        )
    }
}

private extension InferenceProcessSummary {
    var tokensPerSecond: Double? {
        guard generatedTokenCount > 0 else { return nil }
        guard let elapsedSeconds, elapsedSeconds > 0 else { return nil }

        return Double(generatedTokenCount) / elapsedSeconds
    }
}

enum SummaryPhase: Equatable {
    case chat
    case stream

    var displayName: String {
        switch self {
        case .chat:
            return "Summarizing Chat"
        case .stream:
            return "Summarizing stream..."
        }
    }
}

private enum GenerationHapticEvent: Hashable {
    case thinkingStarted
    case streamingStarted
    case completed
    case cancelled
    case failed
}

private enum GenerationHaptics {
    static func play(_ event: GenerationHapticEvent) {
        switch event {
        case .thinkingStarted:
            playImpactPattern([.light, .soft])
        case .streamingStarted:
            playImpactPattern([.light, .light, .light])
        case .completed:
            playImpactPattern([.soft, .light])
        case .cancelled:
            playImpactPattern([.soft])
        case .failed:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }
    }

    private static func playImpactPattern(_ styles: [UIImpactFeedbackGenerator.FeedbackStyle]) {
        for (index, style) in styles.enumerated() {
            let delay = UInt64(index) * 90_000_000
            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                let generator = UIImpactFeedbackGenerator(style: style)
                generator.prepare()
                generator.impactOccurred()
            }
        }
    }
}

private extension InferencePhase {
    var logValue: String {
        switch self {
        case .idle:
            return "idle"
        case .resolving:
            return "resolving"
        case .initializing:
            return "initializing"
        case .checkingRuntimeState:
            return "checkingRuntimeState"
        case .checkingLocalTime:
            return "checkingLocalTime"
        case .checkingWeather:
            return "checkingWeather"
        case .usingCachedWeather:
            return "usingCachedWeather"
        case .downloadingModel:
            return "downloadingModel"
        case .loadingModel:
            return "loadingModel"
        case .formattingPrompt:
            return "formattingPrompt"
        case .tokenizing:
            return "tokenizing"
        case .prefilling:
            return "prefilling"
        case .decoding:
            return "decoding"
        case .flushingOutput:
            return "flushingOutput"
        case .completed:
            return "completed"
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        }
    }
}
