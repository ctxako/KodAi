//
//  kodaisidebar.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//


import SwiftUI

struct KodaiSidebar: View {
    @Binding var sidebarOpen: Bool
    @Binding var selectedMode: OutputMode

    let estimatedContextPercent: Int
    let lastAssistantMessage: String

    let chatSessions: [KodaiChatSession]
    let selectedChatID: UUID?
    
    @State private var editingChat: KodaiChatSession?
    @State private var draftChatTitle = ""
    @State private var showingSettings = false

    let onRenameChat: (KodaiChatSession, String) -> Void
    let onDeleteChat: (KodaiChatSession) -> Void

    let onNewSession: () -> Void
    let onCopyLatest: () -> Void
    let onSelectChat: (KodaiChatSession) -> Void
    let onResetSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sidebarChromeControls

            if sidebarOpen {
                sidebarBrandHeader
            }

            if sidebarOpen {
                Divider()
                    .opacity(0.25)
                    .padding(.vertical, 4)
            }

            sidebarRow("New thread", icon: "plus") {
                onNewSession()
            }

            sidebarRow("Copy latest", icon: "doc.on.doc") {
                onCopyLatest()
            }
            .disabled(lastAssistantMessage.isEmpty)
            .opacity(lastAssistantMessage.isEmpty ? 0.45 : 1)

            if sidebarOpen {
                chatHistorySection
            }

            Spacer()

            sidebarFooter
        }
        .padding(12)
        .frame(width: sidebarOpen ? 266 : 66)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .padding(.leading, 10)
        .padding(.vertical, 10)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)
    }

    private var sidebarChromeControls: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    sidebarOpen.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Spacer()

            if sidebarOpen {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.top, 8)
    }

    private var sidebarBrandHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Kodai")
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            Text("Local dev assistant")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(OutputMode.allCases, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .padding(.top, 8)
    }

    private var chatHistorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.25)
                .padding(.vertical, 6)

            Text("Threads")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            if chatSessions.isEmpty {
                Text("No chats yet")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 8)
                    .frame(height: 30)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(chatSessions, id: \.id) { session in
                            sidebarChat(session)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
    }

    private func modeButton(_ mode: OutputMode) -> some View {
        Button {
            selectedMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(systemName: modeIcon(for: mode))
                    .font(.system(size: 14, weight: .semibold))

                Text(mode.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(selectedMode == mode ? .white : .white.opacity(0.70))
            .background(selectedMode == mode ? .white.opacity(0.16) : .white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selectedMode == mode ? .white.opacity(0.20) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var sidebarIconOnlyMode: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                sidebarOpen = true
            }
        } label: {
            Image(systemName: modeIcon(for: selectedMode))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sidebarFooter: some View {
        Button {
            showingSettings.toggle()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text("U")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }

                if sidebarOpen {
                    Text("User")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            KodaiSettingsView(
                selectedMode: $selectedMode,
                onResetSession: {
                    onResetSession()
                    showingSettings = false
                }
            )
        }
    }
    
    
    
    private func beginEditing(_ session: KodaiChatSession) {
        editingChat = session
        draftChatTitle = session.title
    }

    private func closeEditing() {
        editingChat = nil
        draftChatTitle = ""
    }

    private func editPopoverBinding(for session: KodaiChatSession) -> Binding<Bool> {
        Binding(
            get: {
                editingChat?.id == session.id
            },
            set: { isPresented in
                if !isPresented {
                    closeEditing()
                }
            }
        )
    }

    private func chatEditPopover(for session: KodaiChatSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit chat")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            TextField("Chat name", text: $draftChatTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    closeEditing()
                }

                Spacer()

                Button("Rename") {
                    onRenameChat(session, draftChatTitle)
                    closeEditing()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            Button(role: .destructive) {
                onDeleteChat(session)
                closeEditing()
            } label: {
                Label("Delete chat", systemImage: "trash")
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func sidebarRow(
        _ title: String,
        icon: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)

                if sidebarOpen {
                    Text(title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(.white.opacity(0.84))
            .padding(.horizontal, sidebarOpen ? 8 : 0)
            .frame(width: sidebarOpen ? nil : 34)
            .frame(height: 34)
            .background(.white.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sidebarChat(_ session: KodaiChatSession) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(selectedChatID == session.id ? .white.opacity(0.72) : .clear)
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .frame(width: 6, height: 6)

            Text(session.title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(selectedChatID == session.id ? .white.opacity(0.92) : .white.opacity(0.68))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(selectedChatID == session.id ? .white.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectChat(session)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                beginEditing(session)
            }
        )
        .contextMenu {
            Button("Rename") {
                beginEditing(session)
            }

            Button(role: .destructive) {
                onDeleteChat(session)
            } label: {
                Text("Delete")
            }
        }
        .popover(isPresented: editPopoverBinding(for: session)) {
            chatEditPopover(for: session)
        }
    }

    private func modeIcon(for mode: OutputMode) -> String {
        switch mode {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .organize:
            return "tray.full"
        case .summarize:
            return "text.alignleft"
        case .checklist:
            return "checklist"
        case .debug:
            return "ladybug"
        }
    }
}
