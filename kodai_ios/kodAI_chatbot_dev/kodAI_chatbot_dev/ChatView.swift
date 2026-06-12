//
//  ChatView.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import KodaiKernel
import SwiftUI
import UIKit

private enum ChatPalette {
    static let mainCanvas = Color(red: 0.055, green: 0.061, blue: 0.071)
    static let canvasGlow = Color(red: 0.104, green: 0.145, blue: 0.188)
    static let elevatedSurface = Color(red: 0.094, green: 0.106, blue: 0.122)
    static let assistantBubble = Color(red: 0.133, green: 0.149, blue: 0.169)
    static let accentBlue = Color(red: 0.184, green: 0.490, blue: 0.965)
    static let userBubble = Color(red: 0.110, green: 0.330, blue: 0.680)
    static let glassStroke = Color.white.opacity(0.16)
    static let statusSurface = Color(red: 0.176, green: 0.196, blue: 0.224)
    static let inputField = Color(red: 0.125, green: 0.141, blue: 0.161)
}

private enum MessageListAnchor {
    static let bottom = "message-list-bottom"
}

private enum PrefKey {
    static let messageTextSize = "pref.messageTextSize"
    static let reduceMotion = "pref.reduceMotion"
    static let haptics = "pref.haptics"
    static let compactMessageSpacing = "pref.compactMessageSpacing"
}

private enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.haptics) as? Bool ?? true
    }

    static func lightTap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private enum MessageTextSize: String, CaseIterable, Identifiable {
    case small
    case regular
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .regular:
            return "Default"
        case .large:
            return "Large"
        case .extraLarge:
            return "XL"
        }
    }

    var font: Font {
        switch self {
        case .small:
            return .callout
        case .regular:
            return .body
        case .large:
            return .title3
        case .extraLarge:
            return .title2
        }
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var expandedProcessMessageIDs: Set<ChatMessage.ID> = []
    @State private var isMenuOpen = false
    @State private var commentEditor: MessageCommentEditor?
    @AppStorage(PrefKey.messageTextSize) private var messageTextSize: MessageTextSize = .small
    @AppStorage(PrefKey.reduceMotion) private var reduceMotion = false
    @AppStorage(PrefKey.compactMessageSpacing) private var compactMessageSpacing = false
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
                modelName: viewModel.settingsSnapshot.shortDisplayName,
                onNewChat: inputBarNewChatAction,
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

    private var inputBarNewChatAction: (() -> Void)? {
        guard !isInputFocused else {
            return nil
        }

        return startNewChat
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

                Text("kodAI")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text(viewModel.headerTelemetryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        let maxBubbleWidth = min(560, width * 0.78)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compactMessageSpacing ? 6 : 12) {
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

                scrollToBottom(with: proxy)
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

            AssistantModeSelector(selection: assistantModeBinding)
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

private struct SideMenuDrawer: View {
    private enum DrawerMode {
        case chats
        case settings
        case glassBox
        case streamDetail(Stream.ID)
        case projectDetail(KodaiProjectLite.ID)
    }

    let width: CGFloat
    let sessions: [ChatSession]
    let streams: [Stream]
    let looseSessions: [ChatSession]
    let activeSessionID: UUID?
    let isGenerating: Bool
    let summaryPhase: SummaryPhase?
    let settings: SettingsSnapshot
    @Binding var messageTextSize: MessageTextSize
    let onNewChat: () -> Void
    let onNewChatInStream: (Stream.ID) -> Void
    let onSelectSession: (ChatSession) -> Void
    let onDeleteSession: (ChatSession) -> Void
    let onTogglePinSession: (ChatSession) -> Void
    let onRenameSession: (ChatSession.ID, String) -> Void
    let onCreateStream: (String) -> Stream
    let onRenameStream: (Stream.ID, String) -> Void
    let onDeleteStream: (Stream.ID, Bool) -> Void
    let onAssignChat: (ChatSession.ID, Stream.ID) -> Void
    let onToggleStreamFavorite: (Stream.ID) -> Void
    let onRemoveChatFromStream: (ChatSession.ID) -> Void
    let onOpenChatSummary: (ChatSession.ID) -> Void
    let onOpenStreamSummary: (Stream.ID) -> Void
    let onUpdateChatSummary: (ChatSession.ID) -> Void
    let onRebuildStreamSummary: (Stream.ID) -> Void
    let onSaveChatSummary: (ChatSession.ID, String) -> Void
    let onSaveStreamSummary: (Stream.ID, String) -> Void
    let chatsForStream: (Stream.ID) -> [ChatSession]
    let projects: [KodaiProjectLite]
    let selectedProjectID: UUID?
    let onCreateProject: (String) -> Void
    let onSelectProject: (UUID?) -> Void
    let onRenameProject: (UUID, String) -> Void
    let onDeleteProject: (UUID) -> Void
    let onCreateTask: (String, UUID) -> Void
    let onToggleTask: (UUID, UUID) -> Void
    let onDeleteTask: (UUID, UUID) -> Void
    let dueItems: [DueTaskItem]
    let onSetProjectDeadline: (UUID, Date?) -> Void
    let recentActivityEvents: [ActivityEventLite]
    let latestContextSnapshot: ContextSnapshotLite?
    let onClose: () -> Void

    private let log = AppLog(category: "StreamUI")
    @State private var drawerMode: DrawerMode = .chats
    @State private var isCreatingStream = false
    @State private var newStreamTitle = ""
    @State private var streamToRename: Stream?
    @State private var renameStreamTitle = ""
    @State private var streamToDelete: Stream?
    @State private var chatToMove: ChatSession?
    @State private var summaryEditor: SummaryEditor?
    @State private var isCreatingProject = false
    @State private var newProjectTitle = ""
    @State private var projectToRename: KodaiProjectLite?
    @State private var renameProjectTitle = ""
    @State private var projectToDelete: KodaiProjectLite?
    @State private var isCreatingTask = false
    @State private var newTaskTitle = ""
    @State private var isEditingDeadline = false
    @State private var expandedStreamSummaryIDs: Set<Stream.ID> = []
    @State private var sessionToRename: ChatSession?
    @State private var renameSessionTitle = ""
    @AppStorage(PrefKey.reduceMotion) private var reduceMotion = false
    @AppStorage(PrefKey.haptics) private var haptics = true
    @AppStorage(PrefKey.compactMessageSpacing) private var compactMessageSpacing = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch drawerMode {
            case .chats:
                chatsContent
                    .transition(drawerContentTransition)
            case .settings:
                settingsContent
                    .transition(drawerContentTransition)
            case .glassBox:
                glassBoxContent
                    .transition(drawerContentTransition)
            case .streamDetail(let streamID):
                streamDetailContent(streamID: streamID)
                    .transition(drawerContentTransition)
            case .projectDetail(let projectID):
                projectDetailContent(projectID: projectID)
                    .transition(drawerContentTransition)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ChatPalette.mainCanvas.opacity(0.92))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ChatPalette.glassStroke.opacity(0.72), lineWidth: 0.55)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .alert("New Stream", isPresented: $isCreatingStream) {
            TextField("Title", text: $newStreamTitle)

            Button("Create") {
                onCreateStream(newStreamTitle)
                newStreamTitle = ""
            }

            Button("Cancel", role: .cancel) {
                newStreamTitle = ""
            }
        }
        .alert("Rename Stream", isPresented: Binding(
            get: { streamToRename != nil },
            set: { isPresented in
                if !isPresented {
                    streamToRename = nil
                    renameStreamTitle = ""
                }
            }
        )) {
            TextField("Title", text: $renameStreamTitle)

            Button("Rename") {
                if let streamToRename {
                    onRenameStream(streamToRename.id, renameStreamTitle)
                }
                streamToRename = nil
                renameStreamTitle = ""
            }

            Button("Cancel", role: .cancel) {
                streamToRename = nil
                renameStreamTitle = ""
            }
        }
        .alert("Rename Chat", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { isPresented in
                if !isPresented {
                    sessionToRename = nil
                    renameSessionTitle = ""
                }
            }
        )) {
            TextField("Title", text: $renameSessionTitle)

            Button("Rename") {
                if let sessionToRename {
                    onRenameSession(sessionToRename.id, renameSessionTitle)
                }
                sessionToRename = nil
                renameSessionTitle = ""
            }

            Button("Cancel", role: .cancel) {
                sessionToRename = nil
                renameSessionTitle = ""
            }
        }
        .alert("New Project", isPresented: $isCreatingProject) {
            TextField("Title", text: $newProjectTitle)

            Button("Create") {
                onCreateProject(newProjectTitle)
                newProjectTitle = ""
            }

            Button("Cancel", role: .cancel) {
                newProjectTitle = ""
            }
        }
        .alert("Rename Project", isPresented: Binding(
            get: { projectToRename != nil },
            set: { isPresented in
                if !isPresented {
                    projectToRename = nil
                    renameProjectTitle = ""
                }
            }
        )) {
            TextField("Title", text: $renameProjectTitle)

            Button("Rename") {
                if let projectToRename {
                    onRenameProject(projectToRename.id, renameProjectTitle)
                }
                projectToRename = nil
                renameProjectTitle = ""
            }

            Button("Cancel", role: .cancel) {
                projectToRename = nil
                renameProjectTitle = ""
            }
        }
        .alert("New Task", isPresented: $isCreatingTask) {
            TextField("Title", text: $newTaskTitle)

            Button("Add") {
                if case .projectDetail(let projectID) = drawerMode {
                    onCreateTask(newTaskTitle, projectID)
                }
                newTaskTitle = ""
            }

            Button("Cancel", role: .cancel) {
                newTaskTitle = ""
            }
        }
        .confirmationDialog("Delete Project", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    projectToDelete = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Delete Project and Tasks", role: .destructive) {
                if let projectToDelete {
                    log.event("delete project selected id=\(projectToDelete.id)")
                    onDeleteProject(projectToDelete.id)
                    if case .projectDetail(let projectID) = drawerMode, projectID == projectToDelete.id {
                        drawerMode = .chats
                    }
                }
                projectToDelete = nil
            }

            Button("Cancel", role: .cancel) {
                projectToDelete = nil
            }
        }
        .confirmationDialog("Move to Stream", isPresented: Binding(
            get: { chatToMove != nil },
            set: { isPresented in
                if !isPresented {
                    chatToMove = nil
                }
            }
        ), titleVisibility: .visible) {
            if streams.isEmpty {
                Button("No Streams Available") {}
                    .disabled(true)
            } else {
                ForEach(streams) { stream in
                    Button(stream.title) {
                        if let chatToMove {
                            onAssignChat(chatToMove.id, stream.id)
                        }
                        chatToMove = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                chatToMove = nil
            }
        }
        .confirmationDialog("Delete Stream", isPresented: Binding(
            get: { streamToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    streamToDelete = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Delete Stream Only / Keep Chats") {
                if let streamToDelete {
                    log.event("delete stream option selected keep chats id=\(streamToDelete.id)")
                    onDeleteStream(streamToDelete.id, false)
                    if case .streamDetail(let streamID) = drawerMode, streamID == streamToDelete.id {
                        drawerMode = .chats
                    }
                }
                streamToDelete = nil
            }

            Button("Delete Stream and Chats", role: .destructive) {
                if let streamToDelete {
                    log.event("delete stream option selected delete chats id=\(streamToDelete.id)")
                    onDeleteStream(streamToDelete.id, true)
                    if case .streamDetail(let streamID) = drawerMode, streamID == streamToDelete.id {
                        drawerMode = .chats
                    }
                }
                streamToDelete = nil
            }

            Button("Cancel", role: .cancel) {
                streamToDelete = nil
            }
        }
        .sheet(item: $summaryEditor) { editor in
            SummaryEditorSheet(
                title: editor.title,
                initialSummary: editor.summary,
                isUpdating: summaryPhase != nil,
                onUpdate: editor.updateTitle.map { _ in
                    { updateSummary(editor) }
                },
                updateTitle: editor.updateTitle,
                onSave: { summary in
                    saveSummary(editor, summary: summary)
                    summaryEditor = nil
                }
            )
        }
    }

    private var chatsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("kodAI")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()
            }

            VStack(spacing: 6) {
                List {
                    Section {
                        if dueItems.isEmpty {
                            DrawerEmptyRow(text: "Nothing due today")
                                .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(dueItems) { item in
                                TodayTaskRow(item: item) {
                                    log.event("today task selected taskID=\(item.task.id) projectID=\(item.projectID)")
                                    onSelectProject(item.projectID)
                                    withAnimation(.smooth(duration: 0.22)) {
                                        drawerMode = .projectDetail(item.projectID)
                                    }
                                }
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        Text("Today")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.72))
                    }

                    Section {
                        if streams.isEmpty {
                            DrawerEmptyRow(text: "No Streams")
                                .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(streams) { stream in
                                StreamRow(
                                    stream: stream,
                                    chatCount: chatsForStream(stream.id).count,
                                    isSelected: isShowingStream(stream.id),
                                    onSelect: {
                                        log.event("stream selected id=\(stream.id)")
                                        withAnimation(.smooth(duration: 0.22)) {
                                            drawerMode = .streamDetail(stream.id)
                                        }
                                    },
                                    onToggleFavorite: {
                                        onToggleStreamFavorite(stream.id)
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        openStreamSummary(stream)
                                    } label: {
                                        Label("Summary", systemImage: "doc.text")
                                    }

                                    Button {
                                        onRebuildStreamSummary(stream.id)
                                    } label: {
                                        Label("Update Summary", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .disabled(isGenerating)

                                    Button {
                                        streamToRename = stream
                                        renameStreamTitle = stream.title
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        streamToDelete = stream
                                    } label: {
                                        Label("Delete Stream", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        DrawerSectionHeader(title: "Streams") {
                            log.event("stream create tapped")
                            newStreamTitle = ""
                            isCreatingStream = true
                        }
                    }

                    Section {
                        if projects.isEmpty {
                            DrawerEmptyRow(text: "No projects yet")
                                .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(projects) { project in
                                ProjectRow(
                                    project: project,
                                    isSelected: project.id == selectedProjectID,
                                    onSelect: {
                                        log.event("project selected id=\(project.id)")
                                        onSelectProject(project.id)
                                        withAnimation(.smooth(duration: 0.22)) {
                                            drawerMode = .projectDetail(project.id)
                                        }
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        onSelectProject(project.id)
                                        withAnimation(.smooth(duration: 0.22)) {
                                            drawerMode = .projectDetail(project.id)
                                        }
                                        newTaskTitle = ""
                                        isCreatingTask = true
                                    } label: {
                                        Label("Add Task", systemImage: "plus.circle")
                                    }

                                    Button {
                                        projectToRename = project
                                        renameProjectTitle = project.title
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        projectToDelete = project
                                    } label: {
                                        Label("Delete Project", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        DrawerSectionHeader(title: "Projects") {
                            log.event("project create tapped")
                            newProjectTitle = ""
                            isCreatingProject = true
                        }
                    }

                    Section {
                        if looseSessions.isEmpty {
                            DrawerEmptyRow(text: "No loose chats")
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(looseSessions) { session in
                                ChatSessionRow(
                                    session: session,
                                    isActive: session.id == activeSessionID,
                                    isGenerating: isGenerating,
                                    onSelect: {
                                        onSelectSession(session)
                                    }
                                )
                                .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    Button {
                                        openChatSummary(session)
                                    } label: {
                                        Label("Summary", systemImage: "doc.text")
                                    }

                                    Button {
                                        onUpdateChatSummary(session.id)
                                    } label: {
                                        Label("Update Summary", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .disabled(isGenerating)

                                    Button {
                                        sessionToRename = session
                                        renameSessionTitle = session.title
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .disabled(isGenerating)

                                    Button {
                                        log.event("move to stream tapped chatID=\(session.id)")
                                        chatToMove = session
                                    } label: {
                                        Label("Move to Stream", systemImage: "folder")
                                    }
                                    .disabled(isGenerating || streams.isEmpty)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        onTogglePinSession(session)
                                    } label: {
                                        Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
                                    }
                                    .tint(ChatPalette.accentBlue)
                                    .disabled(isGenerating)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        onDeleteSession(session)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(isGenerating)
                                }
                            }
                        }
                    } header: {
                        Text("Chats")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.72))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    drawerMode = .glassBox
                }
            } label: {
                Label("Glass Box", systemImage: "cube.transparent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .drawerGlassRow(verticalPadding: 7)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    drawerMode = .settings
                }
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .drawerGlassRow(verticalPadding: 7)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func streamDetailContent(streamID: Stream.ID) -> some View {
        if let stream = streams.first(where: { $0.id == streamID }) {
            let streamChats = chatsForStream(streamID)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        log.event("stream back tapped id=\(streamID)")
                        returnToChatsFromStream()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
                    .accessibilityLabel("Back")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stream.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("\(streamChats.count) \(streamChats.count == 1 ? "chat" : "chats")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Button {
                    log.event("stream new chat tapped id=\(streamID)")
                    onNewChatInStream(streamID)
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .drawerGlassRow(verticalPadding: 7)
                }
                .buttonStyle(.plain)

                Button {
                    log.event("stream summary action tapped id=\(streamID)")
                    onRebuildStreamSummary(streamID)
                    expandedStreamSummaryIDs.insert(streamID)
                } label: {
                    Label(stream.summary == nil ? "Create Stream Summary" : "Update Stream Summary", systemImage: "text.badge.checkmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .drawerGlassRow(verticalPadding: 7)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)

                if summaryPhase == .stream {
                    Text("Summarizing stream...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }

                if let summary = stream.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    DisclosureGroup(isExpanded: streamSummaryExpandedBinding(for: streamID)) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    } label: {
                        Label("Stream Summary", systemImage: "doc.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .tint(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)
                }

                List {
                    if streamChats.isEmpty {
                        DrawerEmptyRow(text: "No chats in this Stream")
                            .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(streamChats) { session in
                            ChatSessionRow(
                                session: session,
                                isActive: session.id == activeSessionID,
                                isGenerating: isGenerating,
                                onSelect: {
                                    onSelectSession(session)
                                }
                            )
                            .contextMenu {
                                Button {
                                    openChatSummary(session)
                                } label: {
                                    Label("Summary", systemImage: "doc.text")
                                }

                                Button {
                                    onUpdateChatSummary(session.id)
                                } label: {
                                    Label("Update Summary", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .disabled(isGenerating)

                                Button {
                                    sessionToRename = session
                                    renameSessionTitle = session.title
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .disabled(isGenerating)

                                Button {
                                    log.event("remove from stream tapped chatID=\(session.id) streamID=\(streamID)")
                                    onRemoveChatFromStream(session.id)
                                } label: {
                                    Label("Remove from Stream", systemImage: "tray.and.arrow.up")
                                }
                                .disabled(isGenerating)
                            }
                            .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .simultaneousGesture(streamDetailBackGesture)
        } else {
            chatsContent
        }
    }

    @ViewBuilder
    private func projectDetailContent(projectID: KodaiProjectLite.ID) -> some View {
        if let project = projects.first(where: { $0.id == projectID }) {
            let incompleteTasks = project.incompleteTasks
            let completedTasks = project.completedTasks

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        log.event("project back tapped id=\(projectID)")
                        withAnimation(.smooth(duration: 0.22)) {
                            drawerMode = .chats
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
                    .accessibilityLabel("Back")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("\(incompleteTasks.count) open · \(completedTasks.count) done")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let deadline = project.deadline {
                            Text("Deadline: \(deadline.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                Button {
                    log.event("project new task tapped id=\(projectID)")
                    newTaskTitle = ""
                    isCreatingTask = true
                } label: {
                    Label("New Task", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .drawerGlassRow(verticalPadding: 7)
                }
                .buttonStyle(.plain)

                Button {
                    log.event("project deadline tapped id=\(projectID)")
                    isEditingDeadline = true
                } label: {
                    Label(project.deadline == nil ? "Set Deadline" : "Edit Deadline", systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .drawerGlassRow(verticalPadding: 7)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isEditingDeadline) {
                    ProjectDeadlineSheet(initialDeadline: project.deadline) { deadline in
                        onSetProjectDeadline(projectID, deadline)
                    }
                }

                List {
                    Section {
                        if incompleteTasks.isEmpty {
                            DrawerEmptyRow(text: "No tasks yet — tap + or use /task")
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(incompleteTasks) { task in
                                ProjectTaskRow(
                                    task: task,
                                    onToggle: {
                                        Haptics.lightTap()
                                        onToggleTask(task.id, project.id)
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        onToggleTask(task.id, project.id)
                                    } label: {
                                        Label("Complete", systemImage: "checkmark.circle")
                                    }

                                    Button(role: .destructive) {
                                        onDeleteTask(task.id, project.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        onDeleteTask(task.id, project.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        Text("Tasks")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.72))
                    }

                    if !completedTasks.isEmpty {
                        Section {
                            ForEach(completedTasks) { task in
                                ProjectTaskRow(
                                    task: task,
                                    onToggle: {
                                        Haptics.lightTap()
                                        onToggleTask(task.id, project.id)
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        onToggleTask(task.id, project.id)
                                    } label: {
                                        Label("Uncomplete", systemImage: "arrow.uturn.backward.circle")
                                    }

                                    Button(role: .destructive) {
                                        onDeleteTask(task.id, project.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        onDeleteTask(task.id, project.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(.init(top: 3, leading: 0, bottom: 3, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text("Completed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary.opacity(0.72))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            chatsContent
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        drawerMode = .chats
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
                .accessibilityLabel("Back")

                Text("Settings")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSection(title: "Model / Runtime") {
                        settingsValueRow(title: "Model name", value: settings.modelName, systemImage: "cpu")
                        settingsValueRow(title: "Context size", value: formattedInteger(settings.contextSize), systemImage: "rectangle.expand.vertical")
                        settingsValueRow(title: "Max output tokens", value: optionalInteger(settings.maxOutputTokens), systemImage: "arrow.up.forward")
                        settingsValueRow(title: "Temperature", value: optionalDecimal(settings.temperature), systemImage: "thermometer.medium")
                        settingsValueRow(title: "Top P", value: optionalDecimal(settings.topP), systemImage: "slider.horizontal.3")
                        settingsValueRow(title: "Repeat penalty", value: optionalDecimal(settings.repeatPenalty), systemImage: "repeat")
                        settingsValueRow(title: "Current phase", value: settings.currentPhase ?? "Unavailable", systemImage: "waveform.path.ecg")
                        settingsValueRow(title: "Backend", value: settings.backendName ?? "Unavailable", systemImage: "memorychip")
                    }

                    settingsSection(title: "Analytics") {
                        settingsValueRow(title: "Lifetime tokens generated", value: optionalInteger(settings.lifetimeGeneratedTokens), systemImage: "number")
                        settingsValueRow(title: "Lifetime prompt tokens", value: optionalInteger(settings.lifetimePromptTokens), systemImage: "text.badge.plus")
                        settingsValueRow(title: "Lifetime assistant tokens", value: optionalInteger(settings.lifetimeAssistantTokens), systemImage: "text.bubble")
                        settingsValueRow(title: "Current chat estimate", value: formattedInteger(settings.currentChatTokenEstimate), systemImage: "gauge.with.dots.needle.50percent")
                        settingsValueRow(title: "Context usage", value: settings.contextUsagePercentage, systemImage: "chart.pie")
                        settingsValueRow(title: "Total chats", value: formattedInteger(settings.totalChats), systemImage: "bubble.left.and.bubble.right")
                        settingsValueRow(title: "Total streams", value: formattedInteger(settings.totalStreams), systemImage: "folder")
                        settingsValueRow(title: "Total messages", value: formattedInteger(settings.totalMessages), systemImage: "text.bubble")
                        settingsValueRow(title: "Avg tokens / response", value: optionalDecimal(settings.averageTokensPerResponse), systemImage: "divide")
                        settingsValueRow(title: "Last generation speed", value: optionalSpeed(settings.lastGenerationSpeed), systemImage: "speedometer")
                        settingsValueRow(title: "Last duration", value: optionalDuration(settings.lastGenerationDuration), systemImage: "timer")
                    }

                    settingsSection(title: "Developer") {
                        settingsValueRow(title: "Show phase timeline", value: "Coming soon", systemImage: "timeline.selection")
                        settingsValueRow(title: "Show token counters", value: "Coming soon", systemImage: "number")
                        settingsValueRow(title: "Show generation speed", value: "Coming soon", systemImage: "speedometer")
                        settingsValueRow(title: "Show model/runtime details", value: "Coming soon", systemImage: "info.circle")
                        settingsValueRow(title: "Verbose logs", value: "Coming soon", systemImage: "terminal")
                        settingsValueRow(title: "Export current chat", value: "Use /export", systemImage: "square.and.arrow.up")
                        settingsValueRow(title: "Runtime diagnostics", value: settings.backendName ?? "Unavailable", systemImage: "stethoscope")
                    }

                    settingsSection(title: "Accessibility") {
                        settingsToggleRow(title: "Reduce motion", isOn: $reduceMotion, systemImage: "figure.walk.motion")
                        settingsPickerRow(title: "Chat text size", selection: $messageTextSize, systemImage: "textformat.size")
                        settingsValueRow(title: "High contrast bubbles", value: "Coming soon", systemImage: "circle.lefthalf.filled")
                        settingsToggleRow(title: "Haptics", isOn: $haptics, systemImage: "iphone.radiowaves.left.and.right")
                        settingsValueRow(title: "Keep input controls reachable", value: "Coming soon", systemImage: "keyboard")
                        settingsToggleRow(title: "Compact message spacing", isOn: $compactMessageSpacing, systemImage: "rectangle.compress.vertical")
                    }

                    settingsSection(title: "Appearance") {
                        settingsValueRow(title: "Theme", value: "System · Coming soon", systemImage: "circle.lefthalf.filled")
                        settingsValueRow(title: "Glass intensity", value: "Default · Coming soon", systemImage: "sparkles")
                        settingsValueRow(title: "Message density", value: "Default · Coming soon", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }

                    settingsSection(title: "About") {
                        settingsValueRow(title: "App name", value: appName, systemImage: "app")
                        settingsValueRow(title: "Version", value: appVersionText, systemImage: "number.square")
                        settingsValueRow(title: "Privacy", value: "Local-only", systemImage: "lock")
                        settingsValueRow(title: "Runtime safety", value: "On-device model", systemImage: "shield")
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var glassBoxContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        drawerMode = .chats
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
                .accessibilityLabel("Back")

                Text("Glass Box")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSection(title: "Latest Context") {
                        if let snapshot = latestContextSnapshot {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.reason)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                Text(snapshot.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .drawerGlassRow(verticalPadding: 7)

                            ForEach(snapshot.blocks, id: \.kind) { block in
                                settingsValueRow(
                                    title: block.kind,
                                    value: block.tokenEstimate > 0 ? "\(block.content) · ~\(block.tokenEstimate) tok" : block.content,
                                    systemImage: "square.stack.3d.up"
                                )
                            }
                        } else {
                            DrawerEmptyRow(text: "No context snapshot yet — send a message")
                        }
                    }

                    settingsSection(title: "Recent Activity") {
                        if recentActivityEvents.isEmpty {
                            DrawerEmptyRow(text: "No local activity yet")
                        } else {
                            ForEach(recentActivityEvents.prefix(30)) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: event.kind.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.white.opacity(0.88))

                                        if let detail = event.detail, !detail.isEmpty {
                                            Text(detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }

                                        Text("\(event.source.displayName) · \(event.createdAt.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary.opacity(0.7))
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .drawerGlassRow(verticalPadding: 6)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var drawerContentTransition: AnyTransition {
        switch drawerMode {
        case .chats:
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .settings, .glassBox:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .streamDetail, .projectDetail:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
    }

    private func isShowingStream(_ id: Stream.ID) -> Bool {
        if case .streamDetail(let streamID) = drawerMode {
            return streamID == id
        }
        return false
    }

    private var streamDetailBackGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let startedAtLeftEdge = value.startLocation.x <= 24
                let movedRightEnough = value.translation.width >= 76
                let mostlyHorizontal = abs(value.translation.height) <= 36

                guard startedAtLeftEdge, movedRightEnough, mostlyHorizontal else {
                    return
                }

                log.event("stream back edge swipe")
                returnToChatsFromStream()
            }
    }

    private func returnToChatsFromStream() {
        withAnimation(.smooth(duration: 0.22)) {
            drawerMode = .chats
        }
    }

    private func streamSummaryExpandedBinding(for streamID: Stream.ID) -> Binding<Bool> {
        Binding(
            get: {
                expandedStreamSummaryIDs.contains(streamID)
            },
            set: { isExpanded in
                if isExpanded {
                    expandedStreamSummaryIDs.insert(streamID)
                } else {
                    expandedStreamSummaryIDs.remove(streamID)
                }
            }
        )
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.72))

            VStack(spacing: 2) {
                content()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 16)
        }
    }

    private func settingsValueRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }

    private func settingsNavigationRow(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>, systemImage: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
        .toggleStyle(.switch)
        .tint(ChatPalette.accentBlue)
        .padding(.vertical, 4)
    }

    private func assistantModePickerRow(selection: Binding<AssistantMode>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text("Assistant Mode")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }

            Picker("Assistant Mode", selection: selection) {
                ForEach(AssistantMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
    }

    private func settingsPickerRow(
        title: String,
        selection: Binding<MessageTextSize>,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }

            Picker(title, selection: selection) {
                ForEach(MessageTextSize.allCases) { size in
                    Text(size.title)
                        .tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "kodAI"
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        default:
            return "Unavailable"
        }
    }

    private func formattedInteger(_ value: Int) -> String {
        value.formatted()
    }

    private func optionalInteger(_ value: Int?) -> String {
        value.map { formattedInteger($0) } ?? "Unavailable"
    }

    private func optionalDecimal(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "Unavailable"
    }

    private func optionalSpeed(_ value: Double?) -> String {
        value.map { String(format: "%.1f tok/s", $0) } ?? "Unavailable"
    }

    private func optionalDuration(_ value: TimeInterval?) -> String {
        guard let value else { return "Unavailable" }
        return "\(max(1, Int(value.rounded())))s"
    }

    private func openChatSummary(_ session: ChatSession) {
        onOpenChatSummary(session.id)
        summaryEditor = SummaryEditor(
            title: "Chat Summary",
            summary: session.summary ?? "",
            updateTitle: session.streamID == nil ? "Update Summary" : "Save to Stream",
            target: .chat(session.id)
        )
    }

    private func openStreamSummary(_ stream: Stream) {
        onOpenStreamSummary(stream.id)
        summaryEditor = SummaryEditor(
            title: "Stream Summary",
            summary: stream.summary ?? "",
            updateTitle: "Update Summary",
            target: .stream(stream.id)
        )
    }

    private func updateSummary(_ editor: SummaryEditor) {
        switch editor.target {
        case .chat(let chatID):
            onUpdateChatSummary(chatID)
        case .stream(let streamID):
            onRebuildStreamSummary(streamID)
        }
    }

    private func saveSummary(_ editor: SummaryEditor, summary: String) {
        switch editor.target {
        case .chat(let chatID):
            onSaveChatSummary(chatID, summary)
        case .stream(let streamID):
            onSaveStreamSummary(streamID, summary)
        }
    }
}

private struct SummaryEditor: Identifiable {
    enum Target {
        case chat(ChatSession.ID)
        case stream(Stream.ID)
    }

    let id = UUID()
    let title: String
    let summary: String
    let updateTitle: String?
    let target: Target
}

private struct DrawerSectionHeader: View {
    let title: String
    let onCreate: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onCreate()
            } label: {
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
            .accessibilityLabel("Add \(title)")
        }
    }
}

private struct DrawerEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .drawerGlassRow(isDimmed: true)
    }
}

private struct SummaryPhaseLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassPanel(tint: ChatPalette.statusSurface, cornerRadius: 14)
    }
}

private struct SummaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialSummary: String
    let isUpdating: Bool
    let onUpdate: (() -> Void)?
    let updateTitle: String?
    let onSave: (String) -> Void

    @State private var summary: String

    init(
        title: String,
        initialSummary: String,
        isUpdating: Bool,
        onUpdate: (() -> Void)?,
        updateTitle: String?,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.initialSummary = initialSummary
        self.isUpdating = isUpdating
        self.onUpdate = onUpdate
        self.updateTitle = updateTitle
        self.onSave = onSave
        _summary = State(initialValue: initialSummary)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(alignment: .leading, spacing: 14) {
                    TextEditor(text: $summary)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(summary.isEmpty ? Color.secondary : Color.white)
                        .padding(12)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if summary.isEmpty {
                                Text("No summary yet.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 16)

                    if let onUpdate, let updateTitle {
                        Button {
                            onUpdate()
                        } label: {
                            HStack {
                                if isUpdating {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }

                                Text(updateTitle)
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdating)
                    }
                }
                .padding(18)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(summary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct SummaryCompactionSheet: View {
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var summary: String

    init(
        initialSummary: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _summary = State(initialValue: initialSummary)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                TextEditor(text: $summary)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(summary.isEmpty ? Color.secondary : Color.white)
                    .padding(12)
                    .frame(minHeight: 260)
                    .overlay(alignment: .topLeading) {
                        if summary.isEmpty {
                            Text("No summary yet.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 16)
                    .padding(18)
            }
            .navigationTitle("Confirm Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm(summary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct ProjectRow: View {
    let project: KodaiProjectLite
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? ChatPalette.accentBlue.opacity(0.72) : Color.clear)
                    .frame(width: 4, height: 4)

                Image(systemName: isSelected ? "checklist.checked" : "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? ChatPalette.accentBlue.opacity(0.92) : .secondary.opacity(0.78))

                Text(project.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if openCount > 0 {
                    Text("\(openCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ChatPalette.accentBlue.opacity(0.42), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.48))
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .drawerGlassRow(isSelected: isSelected)
    }

    private var openCount: Int {
        project.incompleteTasks.count
    }
}

private struct ProjectTaskRow: View {
    let task: KodaiTaskLite
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggle()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(task.isCompleted ? ChatPalette.accentBlue.opacity(0.9) : .secondary.opacity(0.62))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark task incomplete" : "Mark task complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundStyle(task.isCompleted ? .secondary : Color.white)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .lineLimit(2)

                if let dueDate = task.dueDate, !task.isCompleted {
                    Text(dueLabel(for: dueDate))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(dueColor(for: dueDate))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .drawerGlassRow(isDimmed: task.isCompleted)
    }

    private func dueLabel(for dueDate: Date) -> String {
        let calendar = Calendar.current
        let formatted = dueDate.formatted(.dateTime.month(.abbreviated).day())
        if dueDate < calendar.startOfDay(for: Date()) {
            return "Overdue · \(formatted)"
        }
        if calendar.isDateInToday(dueDate) {
            return "Today"
        }
        return formatted
    }

    private func dueColor(for dueDate: Date) -> Color {
        let calendar = Calendar.current
        if dueDate < calendar.startOfDay(for: Date()) {
            return .red.opacity(0.82)
        }
        if calendar.isDateInToday(dueDate) {
            return ChatPalette.accentBlue.opacity(0.92)
        }
        return Color.secondary
    }
}

private struct TodayTaskRow: View {
    let item: DueTaskItem
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isOverdue ? "exclamationmark.circle" : "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isOverdue ? Color.red.opacity(0.85) : ChatPalette.accentBlue.opacity(0.92))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(item.isOverdue ? "Overdue · \(item.projectTitle)" : item.projectTitle)
                        .font(.caption2)
                        .foregroundStyle(item.isOverdue ? Color.red.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.48))
            }
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .drawerGlassRow()
    }
}

private struct ProjectDeadlineSheet: View {
    let initialDeadline: Date?
    let onSave: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var deadline = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    .datePickerStyle(.graphical)

                if initialDeadline != nil {
                    Button("Clear Deadline", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Project Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Calendar.current.startOfDay(for: deadline))
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let initialDeadline {
                    deadline = initialDeadline
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StreamRow: View {
    let stream: Stream
    let chatCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isSelected ? ChatPalette.accentBlue.opacity(0.72) : Color.clear)
                        .frame(width: 4, height: 4)

                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? ChatPalette.accentBlue.opacity(0.92) : .secondary.opacity(0.78))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stream.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("\(chatCount) \(chatCount == 1 ? "chat" : "chats")")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.48))
                }
                .frame(minHeight: 46)
            }
            .buttonStyle(.plain)

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: stream.isFavorite ? "star.fill" : "star")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stream.isFavorite ? ChatPalette.accentBlue.opacity(0.9) : .secondary.opacity(0.56))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stream.isFavorite ? "Remove favorite" : "Mark favorite")
        }
        .drawerGlassRow(isSelected: isSelected)
    }
}

private struct FavoriteStreamsPanel: View {
    let streams: [Stream]
    let onSelect: (Stream.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start in a Stream")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 4) {
                ForEach(streams) { stream in
                    Button {
                        onSelect(stream.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ChatPalette.accentBlue.opacity(0.9))
                                .frame(width: 18)

                            Text(stream.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer(minLength: 12)

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary.opacity(0.52))
                        }
                        .frame(minHeight: 38)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassPanel(tint: ChatPalette.inputField.opacity(0.72), cornerRadius: 12)
                }
            }
        }
        .frame(maxWidth: 280)
    }
}

private struct AssistantModeSelector: View {
    @Binding var selection: AssistantMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Assistant Mode", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Assistant Mode", selection: $selection) {
                ForEach(AssistantMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: 280)
    }
}

private struct ChatSessionRow: View {
    let session: ChatSession
    let isActive: Bool
    let isGenerating: Bool
    let onSelect: () -> Void

    var body: some View {
        rowButton
            .drawerGlassRow(isSelected: isActive, isDimmed: isEmptyDraft && !isActive)
            .opacity(isGenerating && !isActive ? 0.65 : 1)
    }

    private var rowButton: some View {
        Button {
            onSelect()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? ChatPalette.accentBlue.opacity(0.68) : Color.clear)
                .frame(width: 4, height: 4)

            Image(systemName: isActive ? "message.fill" : "message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? ChatPalette.accentBlue.opacity(0.92) : .secondary.opacity(0.78))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isEmptyDraft ? Color.secondary : Color.white)
                    .lineLimit(1)

                Text(compactRelativeTimestamp(for: session.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(ChatPalette.accentBlue.opacity(0.86))
            }
        }
        .frame(minHeight: 42)
    }

    private var isEmptyDraft: Bool {
        session.title == "New Chat" && session.messages.isEmpty
    }

    private func compactRelativeTimestamp(for date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))

        if elapsed < 60 {
            return "Now"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        return "\(hours / 24)d"
    }
}

private struct MessageCommentEditor: Identifiable {
    let messageID: ChatMessage.ID
    let comment: String

    var id: ChatMessage.ID { messageID }
}

private struct MessageCommentEditorSheet: View {
    let editor: MessageCommentEditor
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var comment: String

    init(
        editor: MessageCommentEditor,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.editor = editor
        self.onCancel = onCancel
        self.onSave = onSave
        _comment = State(initialValue: editor.comment)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Export Comment")
                        .font(.headline)
                        .foregroundStyle(.white)

                    TextEditor(text: $comment)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)

                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.72))

                        Spacer()

                        Button("Save") {
                            onSave(comment)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(ChatPalette.accentBlue)
                    }
                }
                .padding(18)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let messageFont: Font
    let maxBubbleWidth: CGFloat
    let reduceMotion: Bool
    let statusText: String?
    let activeProcessSummary: InferenceProcessSummary?
    let isProcessExpanded: Bool
    let generationStartDate: Date?
    let onToggleProcess: () -> Void
    let onEditComment: () -> Void

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant {
                if let statusText {
                    if activeProcessSummary != nil,
                       message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ThinkingDotsView(isAnimated: !reduceMotion)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
                    }
                    processStatusView(statusText, summary: activeProcessSummary, isLive: true, generationStartDate: generationStartDate)
                } else if let processSummary = message.processSummary {
                    processStatusView(processSummary.compactText, summary: processSummary, isLive: false, generationStartDate: nil)
                }
            }

            Text(message.text.isEmpty ? " " : message.text)
                .font(messageFont)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .messageBubbleGlass(tint: bubbleTint, isUser: message.role == .user)
            .frame(maxWidth: maxBubbleWidth, alignment: message.role == .user ? .trailing : .leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    onEditComment()
                } label: {
                    Label(
                        message.exportComment == nil ? "Add Comment" : "Edit Comment",
                        systemImage: "text.bubble"
                    )
                }

                Divider()

                Button {
                    SpeechService.shared.speak(message.text)
                } label: {
                    Label("Read Aloud", systemImage: "speaker.wave.2")
                }

                if SpeechService.shared.isSpeaking {
                    Button {
                        SpeechService.shared.stop()
                    } label: {
                        Label("Stop Reading", systemImage: "speaker.slash")
                    }
                }

                Divider()

                Button {} label: {
                    Label(
                        message.createdAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                }
                .disabled(true)
            }
    }

    private var bubbleTint: Color {
        message.role == .user ? ChatPalette.userBubble : ChatPalette.assistantBubble
    }

    private func processStatusView(_ text: String, summary: InferenceProcessSummary?, isLive: Bool, generationStartDate: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onToggleProcess()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isProcessExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isProcessExpanded)

                    if isLive, let startDate = generationStartDate {
                        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                            let elapsed = max(1, Int(context.date.timeIntervalSince(startDate)))
                            let label = message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Thinking… \(elapsed)s"
                                : "Responding… \(elapsed)s"
                            Text(label)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.easeInOut(duration: 0.4), value: elapsed)
                        }
                    } else {
                        Text(text)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .frame(height: 18)
            }
            .buttonStyle(.plain)

            if isProcessExpanded, let summary {
                VStack(alignment: .leading, spacing: 3) {
                    if isLive {
                        if let currentPhase = summary.phasesReached.last {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                    .phaseAnimator([0.3, 1.0]) { view, opacity in
                                        view.opacity(opacity)
                                    } animation: { _ in .easeInOut(duration: 0.6) }

                                Text(currentPhase.displayName)
                                    .id(currentPhase)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            .animation(.spring(duration: 0.25), value: currentPhase)
                        }
                    } else {
                        Text("\(summary.phaseHeading): \(summary.finalPhase.displayName)")

                        if !summary.phasesReached.isEmpty {
                            Text("Phase timeline: \(summary.phasesReached.map(\.displayName).joined(separator: " -> "))")
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !summary.diagnostics.isEmpty {
                            Text("Diagnostics: \(summary.diagnostics.joined(separator: "; "))")
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Total generated tokens: \(summary.generatedTokenCount)")

                        if let tokensPerSecondText = summary.tokensPerSecondText {
                            Text("tok/s: \(tokensPerSecondText)")
                        }

                        if let elapsedText = summary.elapsedText {
                            Text("Duration: \(elapsedText)")
                        }

                        if let modelName = summary.modelName {
                            Text("Model: \(modelName)")
                        }

                        if let failureMessage = summary.failureMessage {
                            Text("Error: \(failureMessage)")
                                .lineLimit(2)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
            }
        }
    }
}

private struct ThinkingDotsView: View {
    let isAnimated: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                BouncingDot(delay: Double(i) * 0.15, isAnimated: isAnimated)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BouncingDot: View {
    let delay: Double
    let isAnimated: Bool
    @State private var isUp = false

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: 7, height: 7)
            .offset(y: isUp ? -5 : 0)
            .onAppear {
                guard isAnimated else { return }
                withAnimation(
                    .easeInOut(duration: 0.45)
                    .delay(delay)
                    .repeatForever(autoreverses: true)
                ) {
                    isUp = true
                }
            }
    }
}

struct InputBar: View {
    @Binding var text: String

    let isGenerating: Bool
    let isInputFocused: FocusState<Bool>.Binding
    let modelName: String
    let onNewChat: (() -> Void)?
    let onSend: () -> Void
    let onStop: () -> Void
    let onSpeechInput: (() -> Void)?

    private var canSend: Bool {
        !isGenerating && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowCommandPicker: Bool {
        guard text.hasPrefix("/"), !isGenerating else { return false }
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return true }
        let commandPart = String(first).lowercased()
        if parts.count > 1 {
            return SlashCommand.all.contains { $0.name == commandPart && $0.acceptsArgument }
                ? false
                : true
        }
        return true
    }

    private var filteredCommands: [SlashCommand] {
        let query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count > 1 else { return SlashCommand.all }
        return SlashCommand.all.filter { $0.name.lowercased().hasPrefix(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowCommandPicker {
                commandPicker
                    .transition(.opacity)
            }

            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 20)
                .disabled(isGenerating)
                .focused(isInputFocused)
                .onSubmit(sendIfPossible)

            HStack(spacing: 10) {
                if let onNewChat {
                    Button { onNewChat() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
                    .accessibilityLabel("New chat")
                    .transition(.scale.combined(with: .opacity))
                }

                Text(modelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 20)

                Spacer()

                if isGenerating {
                    Button { onStop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .accessibilityLabel("Stop generating")
                    .transition(.scale.combined(with: .opacity))
                } else if !canSend, let onSpeechInput {
                    Button { onSpeechInput() } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(ChatPalette.elevatedSurface).interactive(), in: Circle())
                    .accessibilityLabel("Dictate message")
                } else {
                    Button { sendIfPossible() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(ChatPalette.accentBlue)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.45)
                    .accessibilityLabel("Send message")
                }
            }
            .animation(.smooth(duration: 0.18), value: canSend)
            .animation(.smooth(duration: 0.18), value: isGenerating)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    private var commandPicker: some View {
        VStack(spacing: 0) {
            if filteredCommands.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "slash.circle")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))

                    Text("No commands")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ForEach(filteredCommands) { command in
                    Button {
                        text = command.name
                        isInputFocused.wrappedValue = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(command.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 84, alignment: .leading)

                            Text(command.description)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if command.id != filteredCommands.last?.id {
                        Divider()
                            .background(ChatPalette.glassStroke)
                            .padding(.leading, 90)
                    }
                }
            }
        }
        .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 14)
    }

    private func sendIfPossible() {
        guard canSend else { return }
        isInputFocused.wrappedValue = false
        onSend()
    }
}

private struct ExportChatSheet: View {
    let snapshot: ChatExportSnapshot
    let onCancel: () -> Void

    @State private var title: String
    @State private var description = ""
    @State private var includeComments = true
    @State private var errorMessage: String?
    @State private var shareItem: ExportShareItem?

    private let log = AppLog(category: "Export")

    init(snapshot: ChatExportSnapshot, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onCancel = onCancel
        _title = State(initialValue: Self.defaultTitle(for: snapshot))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Export Chat")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)

                    TextEditor(text: $description)
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 110)
                        .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 14)
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Description")
                                    .foregroundStyle(.white.opacity(0.42))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    Text("Chat Contents")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Toggle("Include comments", isOn: $includeComments)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .tint(ChatPalette.accentBlue)

                    chatPreview

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.72))

                        Spacer()

                        Button("Save/Export") {
                            saveAndShare()
                        }
                        .buttonStyle(.glassProminent)
                        .tint(ChatPalette.accentBlue)
                    }
                }
                .padding(18)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.fileURL])
            }
        }
    }

    private var chatPreview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if snapshot.messages.isEmpty {
                    Text("No messages yet.")
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    ForEach(snapshot.messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.role.previewTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))

                            Text(message.text.isEmpty ? " " : message.text)
                                .font(.callout)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)

                            if includeComments,
                               let exportComment = message.exportComment,
                               !exportComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("// Comment: \(exportComment)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.68))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(minHeight: 160, maxHeight: 260)
        .liquidGlassPanel(tint: ChatPalette.assistantBubble, cornerRadius: 14)
    }

    private func saveAndShare() {
        do {
            let result = try ChatExportService.export(
                title: title,
                description: description,
                snapshot: snapshot,
                includeComments: includeComments
            )
            _ = result.markdown
            log.event("share sheet presented")
            shareItem = ExportShareItem(fileURL: result.fileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Export failed. Please try again."
            log.event("export failed error=\(error.localizedDescription)")
        }
    }

    private static func defaultTitle(for snapshot: ChatExportSnapshot) -> String {
        guard let chatTitle = snapshot.chatTitle,
              !chatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              chatTitle != "New Chat" else {
            return "Exported Chat"
        }

        return chatTitle
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension ChatRole {
    var previewTitle: String {
        switch self {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        }
    }
}

private struct ToolProposalCard: View {
    let proposal: PendingToolProposalLite
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatPalette.accentBlue)
                Text(proposal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            if let createTask = proposal.createTask {
                VStack(alignment: .leading, spacing: 4) {
                    Text(createTask.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    if let details = createTask.details, !details.isEmpty {
                        Text(details)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if let projectTitle = createTask.projectTitle {
                            Label(projectTitle, systemImage: "folder")
                        }
                        if let dueDate = createTask.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                        if createTask.priority != .normal {
                            Label(createTask.priority.rawValue.capitalized, systemImage: "flag")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                }
            }

            HStack(spacing: 10) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(ChatPalette.accentBlue)
            }
        }
        .padding(14)
        .liquidGlassPanel(tint: ChatPalette.elevatedSurface, cornerRadius: 18)
    }
}

private struct LiquidGlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                ChatPalette.canvasGlow.opacity(0.60),
                ChatPalette.mainCanvas,
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct LiquidGlassPanel: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(tint.opacity(0.62), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular.tint(tint.opacity(0.62)), in: shape)
            .overlay {
                shape.stroke(ChatPalette.glassStroke, lineWidth: 0.7)
            }
    }
}

private struct DrawerGlassRow: ViewModifier {
    let isSelected: Bool
    let isDimmed: Bool
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let tint = isSelected ? ChatPalette.statusSurface : ChatPalette.inputField
        let fillOpacity = isSelected ? 0.28 : 0.14
        let strokeOpacity = isSelected ? 0.09 : 0.04

        content
            .padding(.horizontal, 10)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(fillOpacity), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular.tint(tint.opacity(fillOpacity)), in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.45)
            }
            .opacity(isDimmed ? 0.58 : 1)
    }
}

private extension View {
    func liquidGlassPanel(tint: Color, cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassPanel(tint: tint, cornerRadius: cornerRadius))
    }

    func drawerGlassRow(
        isSelected: Bool = false,
        isDimmed: Bool = false,
        verticalPadding: CGFloat = 8
    ) -> some View {
        modifier(DrawerGlassRow(isSelected: isSelected, isDimmed: isDimmed, verticalPadding: verticalPadding))
    }

    func messageBubbleGlass(tint: Color, isUser: Bool) -> some View {
        modifier(MessageBubbleGlass(tint: tint, isUser: isUser))
    }
}

private struct MessageBubbleGlass: ViewModifier {
    let tint: Color
    let isUser: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let tintOpacity = isUser ? 0.56 : 0.24

        content
            .background(tint.opacity(tintOpacity), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(isUser ? 0.08 : 0.10), lineWidth: 0.45)
            }
            .shadow(color: Color.black.opacity(isUser ? 0.14 : 0.18), radius: 10, x: 0, y: 6)
    }
}

private extension ChatView {
    private func scrollToBottom(with proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.16)) {
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

private extension InferenceProcessSummary {
    var compactText: String {
        "Thought for \(elapsedText ?? "1s")"
    }

    var elapsedText: String? {
        guard let elapsedSeconds else { return nil }

        let roundedSeconds = max(1, Int(elapsedSeconds.rounded()))
        return "\(roundedSeconds)s"
    }

    var tokensPerSecondText: String? {
        guard generatedTokenCount > 0 else { return nil }
        guard let elapsedSeconds, elapsedSeconds > 0 else { return nil }

        return String(format: "%.1f", Double(generatedTokenCount) / elapsedSeconds)
    }

    var phaseHeading: String {
        switch finalPhase {
        case .completed, .cancelled, .failed:
            return "Final phase"
        default:
            return "Current phase"
        }
    }
}

private extension InferencePhase {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .resolving, .initializing:
            return "Initializing"
        case .checkingRuntimeState:
            return "Checking runtime state"
        case .checkingLocalTime:
            return "Checking local time"
        case .checkingWeather:
            return "Checking weather"
        case .usingCachedWeather:
            return "Using cached weather"
        case .downloadingModel:
            return "Initializing"
        case .loadingModel:
            return "Initializing"
        case .formattingPrompt:
            return "Thinking"
        case .tokenizing:
            return "Processing"
        case .prefilling:
            return "Reasoning"
        case .decoding:
            return "Responding"
        case .flushingOutput:
            return "Responding"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

private extension WarmupStatus {
    var displayName: String {
        switch self {
        case .initializingRuntime:
            return "Pre-heating · starting engine"
        case .allocatingContext:
            return "Pre-heating · allocating memory"
        case .mappingWeights:
            return "Pre-heating · loading weights"
        case .compilingMetal:
            return "Pre-heating · compiling shaders"
        case .warmingTokenizer:
            return "Pre-heating · warming tokenizer"
        case .ready:
            return "Model ready"
        }
    }
}
