//
//  ChatView.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import KodaiKernel
import SwiftUI
import UIKit

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var expandedProcessMessageIDs: Set<ChatMessage.ID> = []
    @State private var isMenuOpen = false
    @State private var isTuningPresented = false
    @State private var showsThreadGlobe = false
    @State private var commentEditor: MessageCommentEditor?
    @AppStorage(PrefKey.messageTextSize) private var messageTextSize: MessageTextSize = .small
    @AppStorage(PrefKey.reduceMotion) private var reduceMotion = false
    @AppStorage(PrefKey.compactMessageSpacing) private var compactMessageSpacing = false
    @AppStorage(PrefKey.surpriseHighlighting) private var surpriseHighlighting = false
    @State private var isMessageListNearBottom = true
    @FocusState private var isInputFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                LiquidGlassBackground()
                mainContent(width: geometry.size.width)

                if isMenuOpen {
                    menuOverlay(width: min(geometry.size.width * 0.83, 326))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isMenuOpen)
            .simultaneousGesture(edgeMenuGesture)
            .overlay(alignment: .top) {
                if let summaryPhase = viewModel.summaryPhase {
                    SummaryPhaseLabel(text: summaryPhase.displayName)
                        .padding(.top, 64)
                        .transition(.opacity)
                }
            }
            .sheet(isPresented: exportSheetBinding) {
                if let snapshot = viewModel.exportSnapshot {
                    ExportChatSheet(
                        snapshot: snapshot,
                        onCancel: viewModel.dismissExportSheet
                    )
                }
            }
            .sheet(item: $commentEditor) { editor in
                MessageCommentEditorSheet(
                    editor: editor,
                    onCancel: {
                        commentEditor = nil
                    },
                    onSave: { comment in
                        viewModel.updateExportComment(for: editor.messageID, comment: comment)
                        commentEditor = nil
                    }
                )
            }
            .sheet(item: summaryConfirmationBinding) { confirmation in
                SummaryCompactionSheet(
                    initialSummary: confirmation.summary,
                    onCancel: viewModel.cancelSummaryConfirmation,
                    onConfirm: viewModel.confirmSummaryCompaction
                )
            }
            .sheet(isPresented: $isTuningPresented) {
                ModelTuningCard(
                    knobs: Binding(
                        get: { viewModel.samplerKnobs },
                        set: { viewModel.samplerKnobs = $0 }
                    )
                )
            }
            .fullScreenCover(isPresented: $showsThreadGlobe) {
                ThreadGlobeView(
                    messages: viewModel.messages,
                    histories: viewModel.tokenHistories,
                    contextSize: Int(LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.contextSize)
                )
            }
        }
    }

    /// True once at least one assistant reply in this chat carries a token trace.
    private var hasThreadTrace: Bool {
        viewModel.tokenHistories.values.contains { history in
            history.contains(where: \.isAnalyzed)
        }
    }

    private var exportSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.exportSnapshot != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissExportSheet()
                }
            }
        )
    }

    private var summaryConfirmationBinding: Binding<PendingSummaryConfirmation?> {
        Binding(
            get: { viewModel.pendingSummaryConfirmation },
            set: { newValue in
                if newValue == nil, viewModel.pendingSummaryConfirmation != nil {
                    viewModel.cancelSummaryConfirmation()
                }
            }
        )
    }

    private func mainContent(width: CGFloat) -> some View {
        let hasPendingProposal = viewModel.pendingToolProposal != nil

        return VStack(spacing: 0) {
            header
            messageList(width: width)
                .opacity(hasPendingProposal ? 0.45 : 1)

            if let proposal = viewModel.pendingToolProposal {
                ToolProposalCard(
                    proposal: proposal,
                    onConfirm: {
                        Haptics.success()
                        viewModel.confirmPendingToolProposal()
                    },
                    onCancel: {
                        Haptics.lightTap()
                        viewModel.cancelPendingToolProposal()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            InputBar(
                text: $viewModel.inputText,
                isGenerating: viewModel.isGenerating,
                isInputFocused: $isInputFocused,
                modeSelection: assistantModeBinding,
                onQuickSend: { prompt in
                    viewModel.inputText = prompt
                    viewModel.send()
                },
                onSend: {
                    Haptics.lightTap()
                    viewModel.send()
                },
                onStop: viewModel.stop,
                onSpeechInput: nil
            )
            .opacity(hasPendingProposal ? 0.55 : 1)
        }
        .blur(radius: mainContentBlurRadius)
        .animation(.easeInOut(duration: 0.2), value: viewModel.pendingToolProposal)
        .onChange(of: viewModel.isGenerating) { wasGenerating, isGenerating in
            if wasGenerating, !isGenerating {
                Haptics.success()
            }
        }
    }

    private var mainContentBlurRadius: CGFloat {
        isMenuOpen ? 1.5 : 0
    }

    @ViewBuilder
    private func menuOverlay(width: CGFloat) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(0.32)
            .overlay(Color.black.opacity(0.36))
            .ignoresSafeArea()
            .onTapGesture {
                closeMenu()
            }
            .transition(.opacity)
            .zIndex(1)

        SideMenuDrawer(
            width: width,
            sessions: viewModel.sessions,
            streams: viewModel.streams,
            looseSessions: viewModel.looseChats(),
            activeSessionID: viewModel.activeSessionID,
            isGenerating: viewModel.isGenerating,
            summaryPhase: viewModel.summaryPhase,
            settings: viewModel.settingsSnapshot,
            messageTextSize: $messageTextSize,
            onNewChat: startNewChat,
            onNewChatInStream: { streamID in
                startNewChat(in: streamID)
            },
            onSelectSession: selectSession,
            onDeleteSession: viewModel.deleteSession,
            onTogglePinSession: viewModel.togglePinSession,
            onRenameSession: viewModel.renameSession,
            onCreateStream: viewModel.createStream,
            onRenameStream: viewModel.renameStream,
            onDeleteStream: viewModel.deleteStream,
            onAssignChat: viewModel.assignChat,
            onToggleStreamFavorite: viewModel.toggleStreamFavorite,
            onRemoveChatFromStream: viewModel.removeChatFromStream,
            onOpenChatSummary: viewModel.openChatSummary,
            onOpenStreamSummary: viewModel.openStreamSummary,
            onUpdateChatSummary: viewModel.updateChatSummary,
            onRebuildStreamSummary: viewModel.rebuildStreamSummary,
            onSaveChatSummary: viewModel.saveChatSummary,
            onSaveStreamSummary: viewModel.saveStreamSummary,
            chatsForStream: viewModel.chatsForStream,
            projects: viewModel.projects,
            selectedProjectID: viewModel.selectedProjectID,
            onCreateProject: { title in
                viewModel.createProject(title: title)
            },
            onSelectProject: viewModel.selectProject,
            onRenameProject: { projectID, title in
                viewModel.updateProjectTitle(projectID: projectID, title: title)
            },
            onDeleteProject: { projectID in
                viewModel.deleteProject(projectID: projectID)
            },
            onCreateTask: { title, projectID in
                viewModel.createTask(title: title, projectID: projectID)
            },
            onToggleTask: { taskID, projectID in
                viewModel.toggleTaskCompletion(taskID: taskID, projectID: projectID)
            },
            onDeleteTask: { taskID, projectID in
                viewModel.deleteTask(taskID: taskID, projectID: projectID)
            },
            dueItems: viewModel.todayAndOverdueTasks(),
            onSetProjectDeadline: { projectID, deadline in
                viewModel.setProjectDeadline(projectID: projectID, deadline: deadline)
            },
            recentActivityEvents: viewModel.recentActivityEvents,
            latestContextSnapshot: viewModel.latestContextSnapshot,
            onClose: closeMenu
        )
        .transition(.move(edge: .leading).combined(with: .opacity))
        .zIndex(2)
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 10) {
                Button {
                    toggleMenu()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Capsule())
                .accessibilityLabel("Menu")

                Button {
                    isTuningPresented = true
                    Haptics.lightTap()
                } label: {
                    Text("kodAI")
                        .font(.headline)
                        .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Capsule())
                .accessibilityLabel("Model tuning")
                .accessibilityHint("Adjust how the model writes replies")

                Spacer(minLength: 0)

                Text(viewModel.headerTelemetryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if hasThreadTrace {
                    Button {
                        showsThreadGlobe = true
                        Haptics.lightTap()
                    } label: {
                        Image(systemName: "globe.americas")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 36)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Capsule())
                    .accessibilityLabel("Thread atlas")
                    .accessibilityHint("See the whole conversation as a globe of token continents")
                }

                Button {
                    surpriseHighlighting.toggle()
                    Haptics.lightTap()
                } label: {
                    Image(systemName: "highlighter")
                        .font(.headline)
                        .foregroundStyle(surpriseHighlighting ? Color.orange : .white)
                        .frame(width: 38, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular
                        .tint(surpriseHighlighting ? Color.orange.opacity(0.5) : ChatPalette.elevatedSurface)
                        .interactive(),
                    in: Capsule()
                )
                .accessibilityLabel("Surprise highlighting")
            }

            if let warmupStatus = viewModel.warmupStatus {
                Text(warmupStatus.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(warmupStatus == .ready ? Color.secondary : Color.white.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.2), value: viewModel.warmupStatus)
    }

    private var edgeMenuGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !isMenuOpen else { return }
                guard value.startLocation.x < 28 else { return }
                guard value.translation.width > 64 else { return }

                openMenu()
            }
    }

    private func messageList(width: CGFloat) -> some View {
        let maxBubbleWidth = min(720, width * 0.9)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: compactMessageSpacing ? 6 : 12) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                messageFont: messageTextSize.font,
                                maxBubbleWidth: maxBubbleWidth,
                                reduceMotion: reduceMotion,
                                statusText: statusText(for: message),
                                activeProcessSummary: activeProcessSummary(for: message),
                                isProcessExpanded: expandedProcessMessageIDs.contains(message.id),
                                generationStartDate: message.id == viewModel.activeAssistantMessageID ? viewModel.sendStartedAt : nil,
                                tokenHistory: viewModel.tokenHistories[message.id] ?? [],
                                surpriseHighlighting: surpriseHighlighting,
                                onToggleProcess: {
                                    toggleProcessSummary(for: message.id)
                                },
                                onEditComment: {
                                    commentEditor = MessageCommentEditor(
                                        messageID: message.id,
                                        comment: message.exportComment ?? ""
                                    )
                                }
                            )
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(MessageListAnchor.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                return geometry.contentSize.height - visibleBottom < 96
            } action: { _, isNearBottom in
                isMessageListNearBottom = isNearBottom
            }
            .onChange(of: viewModel.isGenerating) { _, isGenerating in
                guard isGenerating else {
                    guard isMessageListNearBottom else { return }

                    scrollToBottom(with: proxy)
                    return
                }

                scrollToBottom(with: proxy)
            }
            .onChange(of: viewModel.generatedTokenCount) { _, _ in
                guard viewModel.isGenerating, isMessageListNearBottom else { return }

                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard isMessageListNearBottom || viewModel.isGenerating else { return }

                scrollToBottom(with: proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isMessageListNearBottom, !viewModel.messages.isEmpty {
                    Button {
                        scrollToBottom(with: proxy)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(ChatPalette.statusSurface).interactive(), in: Circle())
                    .accessibilityLabel("Scroll to bottom")
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isMessageListNearBottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            if shouldShowFavoriteStreamsPanel {
                FavoriteStreamsPanel(
                    streams: Array(viewModel.favoriteStreams.prefix(5)),
                    onSelect: viewModel.assignCurrentChatToStream
                )
            } else {
                Text("Ask anything — runs fully on-device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
        .padding(20)
    }

    private var assistantModeBinding: Binding<AssistantMode> {
        Binding(
            get: { viewModel.activeAssistantMode },
            set: { viewModel.setActiveAssistantMode($0) }
        )
    }

    private var shouldShowFavoriteStreamsPanel: Bool {
        guard let activeSession = viewModel.activeSession else { return !viewModel.favoriteStreams.isEmpty }
        return activeSession.messages.isEmpty
            && activeSession.streamID == nil
            && !viewModel.favoriteStreams.isEmpty
    }
}

// MARK: - ChatView Helpers

private extension ChatView {
    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(MessageListAnchor.bottom, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(MessageListAnchor.bottom, anchor: .bottom)
        }
    }

    private func toggleMenu() {
        isMenuOpen.toggle()
    }

    private func openMenu() {
        isMenuOpen = true
    }

    private func closeMenu() {
        isMenuOpen = false
    }

    private func startNewChat() {
        viewModel.newChat()
        closeMenu()
        isInputFocused = true
    }

    private func startNewChat(in streamID: Stream.ID) {
        viewModel.newChat(in: streamID)
        closeMenu()
        isInputFocused = true
    }

    private func selectSession(_ session: ChatSession) {
        viewModel.selectSession(session)
        closeMenu()
    }

    private func toggleProcessSummary(for id: ChatMessage.ID) {
        if expandedProcessMessageIDs.contains(id) {
            expandedProcessMessageIDs.remove(id)
        } else {
            expandedProcessMessageIDs.insert(id)
        }
    }

    private func statusText(for message: ChatMessage) -> String? {
        guard message.role == .assistant else { return nil }
        guard message.id == viewModel.activeAssistantMessageID else { return nil }

        if viewModel.summaryPhase == .chat {
            return "Summarizing chat…"
        }

        switch viewModel.phase {
        case .idle, .completed:
            return nil
        case .checkingRuntimeState:
            return "Checking runtime state…"
        case .checkingLocalTime:
            return "Checking local time…"
        case .checkingWeather:
            return "Checking weather…"
        case .usingCachedWeather:
            return "Using cached weather…"
        case .resolving, .initializing, .downloadingModel, .loadingModel, .formattingPrompt, .tokenizing, .prefilling, .decoding:
            return message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Thinking…" : "Responding…"
        case .flushingOutput:
            return "Responding…"
        case .cancelled, .failed:
            return nil
        }
    }

    private func activeProcessSummary(for message: ChatMessage) -> InferenceProcessSummary? {
        guard message.role == .assistant else { return nil }
        guard message.id == viewModel.activeAssistantMessageID else { return nil }
        return viewModel.activeProcessSummary
    }
}
