//
//  ContentView.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//

import SwiftUI
import SwiftData
import KodaiCore

struct ContentView: View {
    private enum MainContentRoute: Equatable {
        case chat
        case glassBox
        case stream
        case studio
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage(KodaiTheme.storageKey) private var selectedThemeRawValue = KodaiTheme.blueGradient.rawValue

    // Loose chats: no project, no stream
    @Query(
        filter: #Predicate<KodaiChatSession> { $0.projectID == nil && $0.stream == nil },
        sort: \KodaiChatSession.updatedAt,
        order: .reverse
    )
    private var chatSessions: [KodaiChatSession]

    @Query(sort: \KodaiStream.updatedAt, order: .reverse)
    private var streams: [KodaiStream]

    @Query(sort: \KodaiProject.updatedAt, order: .reverse)
    private var projects: [KodaiProject]

    // Used for auto-select on appear when all chats are in projects
    @Query(sort: \KodaiChatSession.updatedAt, order: .reverse)
    private var allChatSessions: [KodaiChatSession]

    @State private var viewModel = ChatViewModel()
    @State private var studioViewModel = StudioViewModel()
    @State private var sidebarOpen = true
    @State private var mainContentRoute: MainContentRoute = .chat

    @FocusState private var composerFocused: Bool

    private let sidebarLeadingPadding: CGFloat = 8
    private let sidebarContentGap: CGFloat = 8
    private let mainChatLaneMaxWidth: CGFloat = 680

    private var contentLeadingPadding: CGFloat {
        (sidebarOpen ? KodaiSidebar.openWidth : KodaiSidebar.closedWidth)
            + sidebarLeadingPadding
            + sidebarContentGap
    }

    private var activeProject: KodaiProject? {
        guard let projectID = viewModel.selectedChat?.projectID else { return nil }
        return projects.first { $0.id == projectID }
    }

    private var selectedTheme: KodaiTheme {
        KodaiTheme(rawValue: selectedThemeRawValue) ?? .blueGradient
    }

    private var todaysTasks: [KodaiTask] {
        viewModel.todaysTasks(from: projects)
    }

    private var glassBoxSignalState: LiveEntitySignalState {
        let status: LiveEntitySignalState.Status
        if viewModel.isWaitingForFirstToken {
            status = .thinking
        } else if viewModel.isLoading {
            status = .responding
        } else {
            status = .idle
        }

        return LiveEntitySignalState(
            status: status,
            contextPercent: viewModel.estimatedContextPercent,
            tasksDueCount: todaysTasks.count,
            selectedProjectName: activeProject?.title,
            memoryReady: viewModel.selectedChat != nil,
            toolActionReady: viewModel.pendingToolProposal == nil && !viewModel.isSummarizing
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            KodaiBackground()

            Group {
                switch mainContentRoute {
                case .chat:
                    chatContent
                case .glassBox:
                    GlassBoxView(
                        signalState: glassBoxSignalState,
                        latestTurn: viewModel.turnRecords.values.max(by: { $0.createdAt < $1.createdAt }),
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                mainContentRoute = .chat
                            }
                        }
                    )
                case .stream:
                    streamContent
                case .studio:
                    StudioView(
                        viewModel: studioViewModel,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                mainContentRoute = .chat
                            }
                        }
                    )
                }
            }
            .padding(.leading, contentLeadingPadding)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)

            sidebar
        }
        .environment(\.kodaiTheme, selectedTheme.palette)
        .tint(selectedTheme.palette.primaryAccent)
        .preferredColorScheme(.dark)
        .frame(minWidth: 950, minHeight: 650)
        .onAppear {
            viewModel.cleanupEmptySessions(context: modelContext)
            if let newest = allChatSessions.first {
                viewModel.selectChat(newest, context: modelContext)
            } else {
                viewModel.createNewChat(context: modelContext)
            }
            viewModel.refreshContextEstimate()
        }
        .onChange(of: allChatSessions.map { $0.id }) {
            if viewModel.selectedChat == nil, let newest = allChatSessions.first {
                viewModel.selectChat(newest, context: modelContext)
            }
        }
        .onChange(of: viewModel.inputText) {
            guard !viewModel.isLoading else { return }
            viewModel.refreshContextEstimate(pendingInput: viewModel.inputText)
        }
        .onChange(of: viewModel.selectedMode) {
            viewModel.refreshContextEstimate(pendingInput: viewModel.inputText)
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if let project = activeProject {
                KodaiProjectHeader(
                    project: project,
                    session: viewModel.selectedChat,
                    isGenerating: viewModel.isSummarizing,
                    onUpdateSummary: { summary in
                        viewModel.updateProjectSummary(project, summary: summary, context: modelContext)
                    },
                    onGenerateSummary: {
                        viewModel.generateProjectSummary(project, context: modelContext)
                    },
                    onCreateTask: { title, notes, priority, dueDate in
                        viewModel.createTask(in: project, title: title, notes: notes, priority: priority, dueDate: dueDate, context: modelContext)
                    },
                    onToggleTask: { task in
                        viewModel.toggleTask(task, context: modelContext)
                    },
                    onDeleteTask: { task in
                        viewModel.deleteTask(task, context: modelContext)
                    },
                    onRenameTask: { task, title in
                        viewModel.renameTask(task, title: title, context: modelContext)
                    },
                    onUpdateTaskDueDate: { task, dueDate in
                        viewModel.updateTaskDueDate(task, dueDate: dueDate, context: modelContext)
                    },
                    onUpdateProjectDeadline: { deadline in
                        viewModel.updateProjectDeadline(project, deadline: deadline, context: modelContext)
                    }
                )
            }

            ChatScrollView(messages: viewModel.messages, turnRecords: viewModel.turnRecords)
                .frame(maxWidth: mainChatLaneMaxWidth)
                .frame(maxWidth: .infinity)

            if let proposal = viewModel.pendingToolProposal {
                ToolProposalConfirmationCard(
                    proposal: proposal,
                    onConfirm: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            viewModel.confirmProposal(context: modelContext, projects: projects)
                        }
                    },
                    onCancel: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            viewModel.cancelProposal(context: modelContext)
                        }
                    }
                )
                .padding(.horizontal)
                .padding(.bottom, 4)
                .frame(maxWidth: mainChatLaneMaxWidth)
                .frame(maxWidth: .infinity)
            }

            KodaiComposerBar(
                inputText: $viewModel.inputText,
                composerFocused: $composerFocused,
                isLoading: viewModel.isLoading,
                isSummarizing: viewModel.isSummarizing,
                telemetry: viewModel.chatTelemetry,
                onSend: {
                    viewModel.send(context: modelContext, projects: projects)
                },
                onStop: {
                    viewModel.stopGeneration()
                }
            )
            .frame(maxWidth: mainChatLaneMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var streamContent: some View {
        StreamView(
            projects: projects,
            onCreateProject: {
                let project = viewModel.createProject(context: modelContext)
                viewModel.createNewChat(context: modelContext, project: project)
                withAnimation(.easeInOut(duration: 0.18)) {
                    mainContentRoute = .chat
                }
            },
            onCreateTask: { project, title, notes, priority, dueDate in
                viewModel.createTask(in: project, title: title, notes: notes, priority: priority, dueDate: dueDate, context: modelContext)
            },
            onToggleTask: { task in
                viewModel.toggleTask(task, context: modelContext)
            },
            onDeleteTask: { task in
                viewModel.deleteTask(task, context: modelContext)
            },
            onSelectProject: { project in
                let sorted = allChatSessions
                    .filter { $0.projectID == project.id }
                    .sorted { $0.updatedAt > $1.updatedAt }
                if let latest = sorted.first {
                    viewModel.selectChat(latest, context: modelContext)
                } else {
                    viewModel.createNewChat(context: modelContext, project: project)
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    mainContentRoute = .chat
                }
            },
            onClose: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mainContentRoute = .chat
                }
            }
        )
    }

    private var sidebar: some View {
        KodaiSidebar(
            sidebarOpen: $sidebarOpen,
            selectedMode: $viewModel.selectedMode,
            glassBoxSignalState: glassBoxSignalState,
            glassBoxSelected: mainContentRoute == .glassBox,
            estimatedContextPercent: viewModel.estimatedContextPercent,
            chatSessions: chatSessions,
            allChatSessions: allChatSessions,
            streams: streams,
            projects: projects,
            todaysTasks: todaysTasks,
            selectedChatID: viewModel.selectedChat?.id,
            telemetryStore: viewModel.telemetryStore,
            onRenameChat: { session, newTitle in
                viewModel.renameChat(session, to: newTitle, context: modelContext)
            },
            onDeleteChat: { session in
                viewModel.deleteChat(
                    session,
                    fallback: allChatSessions.first { $0.id != session.id },
                    context: modelContext
                )
            },
            onOpenGlassBox: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mainContentRoute = .glassBox
                }
            },
            onOpenStream: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mainContentRoute = .stream
                }
            },
            onOpenStudio: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mainContentRoute = .studio
                }
            },
            onNewSession: { project in
                mainContentRoute = .chat
                viewModel.createNewChat(context: modelContext, project: project)
            },
            onSelectChat: { session in
                mainContentRoute = .chat
                viewModel.selectChat(session, context: modelContext)
            },
            onResetSession: {
                viewModel.resetSession()
            },
            onCreateStream: {
                viewModel.createStream(context: modelContext)
            },
            onRenameStream: { stream, newTitle in
                viewModel.renameStream(stream, to: newTitle, context: modelContext)
            },
            onDeleteStream: { stream, keepChats in
                viewModel.deleteStream(stream, keepChats: keepChats, context: modelContext)
            },
            onAssignChat: { session, stream in
                viewModel.assignChat(session, to: stream, context: modelContext)
            },
            onCreateProject: {
                viewModel.createProject(context: modelContext)
            },
            onRenameProject: { project, title, details in
                viewModel.renameProject(project, title: title, details: details, context: modelContext)
            },
            onArchiveProject: { project in
                viewModel.archiveProject(project, context: modelContext)
            },
            onUnarchiveProject: { project in
                viewModel.unarchiveProject(project, context: modelContext)
            },
            onDeleteProject: { project in
                viewModel.deleteProject(project, context: modelContext)
            },
            onAssignChatToProject: { session, project in
                viewModel.assignChatToProject(session, project: project, context: modelContext)
            }
        )
    }
}
