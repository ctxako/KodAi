//
//  ContentView.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // Loose chats: no project, no stream
    @Query(
        filter: #Predicate<KodaiChatSession> { $0.project == nil && $0.stream == nil },
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
    @State private var sidebarOpen = true

    @FocusState private var composerFocused: Bool

    private let sidebarOpenWidth: CGFloat = 266
    private let sidebarClosedWidth: CGFloat = 66
    private let sidebarLeadingPadding: CGFloat = 10
    private let sidebarContentGap: CGFloat = 10

    private var contentLeadingPadding: CGFloat {
        (sidebarOpen ? sidebarOpenWidth : sidebarClosedWidth)
            + sidebarLeadingPadding
            + sidebarContentGap
    }

    private var activeProject: KodaiProject? {
        viewModel.selectedChat?.project
    }

    var body: some View {
        ZStack(alignment: .leading) {
            KodaiBackground()

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
                }

                ComposerView(
                    inputText: $viewModel.inputText,
                    selectedMode: $viewModel.selectedMode,
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
            }
            .padding(.leading, contentLeadingPadding)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)

            sidebar
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 950, minHeight: 650)
        .onAppear {
            viewModel.createNewChat(context: modelContext)
            viewModel.refreshContextEstimate()
        }
        .onChange(of: allChatSessions.map { $0.id }) {
            if viewModel.selectedChat == nil, let newest = allChatSessions.first {
                viewModel.selectChat(newest)
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

    private var sidebar: some View {
        KodaiSidebar(
            sidebarOpen: $sidebarOpen,
            selectedMode: $viewModel.selectedMode,
            isLoading: viewModel.isLoading,
            estimatedContextPercent: viewModel.estimatedContextPercent,
            chatSessions: chatSessions,
            streams: streams,
            projects: projects,
            todaysTasks: viewModel.todaysTasks(from: projects),
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
            onNewSession: { project in
                viewModel.createNewChat(context: modelContext, project: project)
            },
            onSelectChat: { session in
                viewModel.selectChat(session)
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
