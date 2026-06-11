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

    @Query(
        filter: #Predicate<KodaiChatSession> { $0.stream == nil },
        sort: \KodaiChatSession.updatedAt,
        order: .reverse
    )
    private var chatSessions: [KodaiChatSession]

    @Query(sort: \KodaiStream.updatedAt, order: .reverse)
    private var streams: [KodaiStream]

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

    var body: some View {
        ZStack(alignment: .leading) {
            KodaiBackground()

            VStack(spacing: 0) {
                ChatScrollView(messages: viewModel.messages)

                ComposerView(
                    inputText: $viewModel.inputText,
                    selectedMode: $viewModel.selectedMode,
                    composerFocused: $composerFocused,
                    isLoading: viewModel.isLoading,
                    telemetry: viewModel.chatTelemetry,
                    onSend: {
                        viewModel.send(context: modelContext)
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
            if viewModel.selectedChat == nil, let newestChat = chatSessions.first {
                viewModel.selectChat(newestChat)
            }
            viewModel.refreshContextEstimate()
        }
        .onChange(of: chatSessions.map { $0.id }) {
            if viewModel.selectedChat == nil, let newestChat = chatSessions.first {
                viewModel.selectChat(newestChat)
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
            selectedChatID: viewModel.selectedChat?.id,
            telemetryStore: viewModel.telemetryStore,
            onRenameChat: { session, newTitle in
                viewModel.renameChat(session, to: newTitle, context: modelContext)
            },
            onDeleteChat: { session in
                viewModel.deleteChat(
                    session,
                    fallback: chatSessions.first { $0.id != session.id },
                    context: modelContext
                )
            },
            onNewSession: {
                viewModel.createNewChat(context: modelContext)
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
            }
        )
    }
}
