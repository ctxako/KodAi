//
//  kodaisidebar.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//


import SwiftUI
import KodaiCore

struct KodaiSidebar: View {
    static let openWidth: CGFloat = 200
    static let closedWidth: CGFloat = 66

    @Environment(\.kodaiTheme) private var theme

    @Binding var sidebarOpen: Bool
    @Binding var selectedMode: OutputMode

    let glassBoxSignalState: LiveEntitySignalState
    let glassBoxSelected: Bool
    let estimatedContextPercent: Int

    let chatSessions: [KodaiChatSession]
    let allChatSessions: [KodaiChatSession]
    let streams: [KodaiStream]
    let projects: [KodaiProject]
    let todaysTasks: [KodaiTask]
    let selectedChatID: UUID?
    let telemetryStore: TelemetryStore

    @State private var editingChat: KodaiChatSession?
    @State private var draftChatTitle = ""
    @State private var showingSettings = false
    @State private var breathing = false

    @State private var streamsExpanded = true
    @State private var editingStream: KodaiStream?
    @State private var draftStreamTitle = ""
    @State private var streamPendingDelete: KodaiStream?

    @State private var projectsExpanded = true
    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var editingProject: KodaiProject?
    @State private var draftProjectTitle = ""
    @State private var draftProjectDetails = ""
    @State private var projectPendingDelete: KodaiProject?

    let onRenameChat: (KodaiChatSession, String) -> Void
    let onDeleteChat: (KodaiChatSession) -> Void
    let onOpenGlassBox: () -> Void
    let onOpenStream: () -> Void
    let onOpenStudio: () -> Void
    let onOpenLifeHQ: () -> Void
    let onOpenBriefing: () -> Void
    let onNewSession: (KodaiProject?) -> Void
    let onSelectChat: (KodaiChatSession) -> Void
    let onResetSession: () -> Void
    let onCreateStream: () -> Void
    let onRenameStream: (KodaiStream, String) -> Void
    let onDeleteStream: (KodaiStream, Bool) -> Void
    let onAssignChat: (KodaiChatSession, KodaiStream?) -> Void
    let onCreateProject: () -> Void
    let onRenameProject: (KodaiProject, String, String) -> Void
    let onArchiveProject: (KodaiProject) -> Void
    let onUnarchiveProject: (KodaiProject) -> Void
    let onDeleteProject: (KodaiProject) -> Void
    let onAssignChatToProject: (KodaiChatSession, KodaiProject?) -> Void

    private var activeProject: KodaiProject? {
        guard let selectedChatID,
              let projectID = allChatSessions.first(where: { $0.id == selectedChatID })?.projectID else {
            return nil
        }
        return projects.first { $0.id == projectID }
    }

    private func sessions(in project: KodaiProject) -> [KodaiChatSession] {
        allChatSessions.filter { $0.projectID == project.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: sidebarOpen ? 7 : 12) {
            sidebarHeader

            if sidebarOpen {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        KodaiSidebarGlassBox(
                            signalState: glassBoxSignalState,
                            isSelected: glassBoxSelected,
                            onOpen: onOpenGlassBox
                        )
                        .frame(maxWidth: .infinity)

                        sidebarRow("Stream", icon: "bolt.horizontal.fill") {
                            onOpenStream()
                        }

                        sidebarRow("Studio", icon: "chart.bar.xaxis") {
                            onOpenStudio()
                        }

                        sidebarRow("Life HQ", icon: "flame.fill") {
                            onOpenLifeHQ()
                        }

                        sidebarRow("Briefing", icon: "sun.horizon.fill") {
                            onOpenBriefing()
                        }

                        sidebarRow("New thread", icon: "plus") {
                            onNewSession(activeProject)
                        }

                        todaySectionView
                        projectsSection
                        streamsSection
                        chatHistorySection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollClipDisabled()
                .scrollBounceBehavior(.basedOnSize)
            } else {
                sidebarRow("New thread", icon: "plus") {
                    onNewSession(activeProject)
                }

                if !todaysTasks.isEmpty {
                    todayCollapsedBadge
                }

                Spacer()
            }

            sidebarFooter
        }
        .padding(.horizontal, sidebarOpen ? 4 : 12)
        .padding(.vertical, sidebarOpen ? 8 : 12)
        .frame(width: sidebarOpen ? Self.openWidth : Self.closedWidth)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.glassSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.glassBorder.opacity(0.65), lineWidth: 0.75)
        }
        .padding(.leading, 8)
        .padding(.vertical, 10)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sidebarOpen)
        .confirmationDialog(
            "Delete \"\(streamPendingDelete?.title ?? "stream")\"?",
            isPresented: Binding(
                get: { streamPendingDelete != nil },
                set: { if !$0 { streamPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Keep threads") {
                if let stream = streamPendingDelete { onDeleteStream(stream, true) }
                streamPendingDelete = nil
            }
            Button("Delete everything", role: .destructive) {
                if let stream = streamPendingDelete { onDeleteStream(stream, false) }
                streamPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { streamPendingDelete = nil }
        }
        .confirmationDialog(
            "Delete \"\(projectPendingDelete?.title ?? "project")\"?",
            isPresented: Binding(
                get: { projectPendingDelete != nil },
                set: { if !$0 { projectPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete project and all chats", role: .destructive) {
                if let project = projectPendingDelete { onDeleteProject(project) }
                projectPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { projectPendingDelete = nil }
        }
    }

    // MARK: – Today

    private var todaySectionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .opacity(0.18)
                .padding(.vertical, 2)

            Text("Today")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            todayTasksContent
        }
    }

    @ViewBuilder
    private var todayTasksContent: some View {
        if todaysTasks.isEmpty {
            if projects.contains(where: { $0.status == .active }) {
                Text("Nothing due today")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.32))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        } else if todaysTasks.count <= 5 {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(todaysTasks, id: \.id) { task in
                    todayTaskRow(task)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(todaysTasks, id: \.id) { task in
                    todayTaskRow(task)
                }
            }
        }
    }

    private var todayCollapsedBadge: some View {
        let hasOverdue = todaysTasks.contains {
            guard let due = $0.dueDate else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }
        return ZStack(alignment: .topTrailing) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.065))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(todaysTasks.count > 9 ? "9+" : "\(todaysTasks.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(hasOverdue ? Color.red.opacity(0.75) : Color.white.opacity(0.45))
                .clipShape(Capsule())
                .offset(x: 6, y: -4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                sidebarOpen = true
            }
        }
    }

    private func todayTaskRow(_ task: KodaiTask) -> some View {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let overdue = task.dueDate.map { $0 < startOfToday } ?? false

        return Button {
            selectTodayTask(task)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(overdue ? Color.red.opacity(0.55) : Color.white.opacity(0.2))
                    .frame(width: 3, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(overdue ? 0.88 : 0.76))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let projTitle = task.project?.title {
                            Text(projTitle)
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.36))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(taskDueLabel(task, startOfToday: startOfToday))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(overdue ? Color.red.opacity(0.68) : Color.white.opacity(0.40))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func taskDueLabel(_ task: KodaiTask, startOfToday: Date) -> String {
        guard let due = task.dueDate else { return "" }
        if due < startOfToday {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: due),
                to: startOfToday
            ).day ?? 0
            if days == 1 { return "yesterday" }
            if days > 1 { return "\(days)d overdue" }
            return "overdue"
        }
        return "today"
    }

    private func selectTodayTask(_ task: KodaiTask) {
        guard let project = task.project else { return }
        let sorted = sessions(in: project).sorted { $0.updatedAt > $1.updatedAt }
        if let latest = sorted.first {
            onSelectChat(latest)
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                projectsExpanded = true
                expandedProjectIDs.insert(project.id)
            }
        }
    }

    // MARK: – Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.18)
                .padding(.vertical, 3)

            HStack(spacing: 4) {
                Text("Projects")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onCreateProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        projectsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: projectsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            if projectsExpanded {
                let active = projects.filter { $0.status != .archived }
                let archived = projects.filter { $0.status == .archived }

                if projects.isEmpty {
                    Text("No projects yet")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(active, id: \.id) { project in
                            projectRow(project)
                        }
                        if !archived.isEmpty {
                            ForEach(archived, id: \.id) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
            }
        }
    }

    private func projectRow(_ project: KodaiProject) -> some View {
        let isExpanded = expandedProjectIDs.contains(project.id)
        let hasActiveChat = sessions(in: project).contains { $0.id == selectedChatID }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let overdueCount = (project.tasks ?? []).filter {
            !$0.isCompleted && ($0.dueDate.map { $0 < startOfToday } ?? false)
        }.count

        return VStack(alignment: .leading, spacing: 2) {
            // Project header row
            HStack(spacing: 8) {
                Image(systemName: hasActiveChat ? "folder.fill" : "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasActiveChat ? .white.opacity(0.9) : .white.opacity(0.55))
                    .frame(width: 16)

                Text(project.title)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(hasActiveChat ? .white.opacity(0.92) : .white.opacity(0.68))
                    .lineLimit(1)

                if project.status == .archived {
                    Text("archived")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if overdueCount > 0 {
                    Text("\(overdueCount) overdue")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red.opacity(0.75))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(hasActiveChat ? .white.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    if expandedProjectIDs.contains(project.id) {
                        expandedProjectIDs.remove(project.id)
                    } else {
                        expandedProjectIDs.insert(project.id)
                    }
                }
                let sorted = sessions(in: project).sorted { $0.updatedAt > $1.updatedAt }
                if let latest = sorted.first {
                    onSelectChat(latest)
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    beginEditingProject(project)
                }
            )
            .contextMenu {
                Button("Rename") { beginEditingProject(project) }
                Button("New chat in project") { onNewSession(project) }
                Divider()
                if project.status == .archived {
                    Button("Unarchive") { onUnarchiveProject(project) }
                } else {
                    Button("Archive") { onArchiveProject(project) }
                }
                Button(role: .destructive) {
                    projectPendingDelete = project
                } label: {
                    Text("Delete")
                }
            }
            .popover(isPresented: projectEditPopoverBinding(for: project)) {
                projectEditPopover(for: project)
            }

            // Expanded chats list
            if isExpanded {
                let sorted = sessions(in: project).sorted { $0.updatedAt > $1.updatedAt }
                ForEach(sorted, id: \.id) { session in
                    projectChatRow(session)
                        .padding(.leading, 16)
                }
            }
        }
    }

    private func projectChatRow(_ session: KodaiChatSession) -> some View {
        let isActive = selectedChatID == session.id
        return HStack(spacing: 8) {
            Circle()
                .fill(isActive ? .white.opacity(0.72) : .clear)
                .stroke(.white.opacity(0.2), lineWidth: 1)
                .frame(width: 5, height: 5)

            Text(session.title)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(isActive ? .white.opacity(0.92) : .white.opacity(0.6))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(isActive ? .white.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onSelectChat(session) }
        .contextMenu {
            Button("Rename") { beginEditing(session) }
            Button(role: .destructive) { onDeleteChat(session) } label: { Text("Delete") }
        }
        .popover(isPresented: editPopoverBinding(for: session)) {
            chatEditPopover(for: session)
        }
    }

    private func beginEditingProject(_ project: KodaiProject) {
        editingProject = project
        draftProjectTitle = project.title
        draftProjectDetails = project.details
    }

    private func closeEditingProject() {
        editingProject = nil
        draftProjectTitle = ""
        draftProjectDetails = ""
    }

    private func projectEditPopoverBinding(for project: KodaiProject) -> Binding<Bool> {
        Binding(
            get: { editingProject?.id == project.id },
            set: { if !$0 { closeEditingProject() } }
        )
    }

    private func projectEditPopover(for project: KodaiProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit project")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            TextField("Project name", text: $draftProjectTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Details (optional)", text: $draftProjectDetails, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3)

            HStack {
                Button("Cancel") { closeEditingProject() }
                Spacer()
                Button("Save") {
                    onRenameProject(project, draftProjectTitle, draftProjectDetails)
                    closeEditingProject()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            if project.status == .archived {
                Button { onUnarchiveProject(project); closeEditingProject() } label: {
                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button { onArchiveProject(project); closeEditingProject() } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }

            Button(role: .destructive) {
                closeEditingProject()
                projectPendingDelete = project
            } label: {
                Label("Delete project", systemImage: "trash")
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: – Streams

    private var streamsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.18)
                .padding(.vertical, 3)

            HStack(spacing: 4) {
                Text("Streams")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onCreateStream()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        streamsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: streamsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            if streamsExpanded {
                if streams.isEmpty {
                    Text("No streams yet")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(streams, id: \.id) { stream in
                            streamRow(stream)
                        }
                    }
                }
            }
        }
        .onAppear {
            // Empty section starts collapsed; the header's + stays reachable
            // for creating the first stream, and a manual expand sticks.
            if streams.isEmpty {
                streamsExpanded = false
            }
        }
    }

    private func streamRow(_ stream: KodaiStream) -> some View {
        let isActive = stream.sessions.contains { $0.id == selectedChatID }

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "rectangle.stack.fill" : "rectangle.stack")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? .white.opacity(0.9) : .white.opacity(0.55))
                .frame(width: 16)

            Text(stream.title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(isActive ? .white.opacity(0.92) : .white.opacity(0.68))
                .lineLimit(1)

            Spacer()

            Text("\(stream.sessions.count)")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(isActive ? .white.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            let sorted = stream.sessions.sorted { $0.updatedAt > $1.updatedAt }
            if let latest = sorted.first {
                onSelectChat(latest)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                beginEditingStream(stream)
            }
        )
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let sessionID = UUID(uuidString: uuidString),
                  let session = findSession(by: sessionID) else {
                return false
            }
            onAssignChat(session, stream)
            return true
        }
        .contextMenu {
            Button("Rename") { beginEditingStream(stream) }
            Button(role: .destructive) { streamPendingDelete = stream } label: { Text("Delete") }
        }
        .popover(isPresented: streamEditPopoverBinding(for: stream)) {
            streamEditPopover(for: stream)
        }
    }

    private func beginEditingStream(_ stream: KodaiStream) {
        editingStream = stream
        draftStreamTitle = stream.title
    }

    private func closeEditingStream() {
        editingStream = nil
        draftStreamTitle = ""
    }

    private func streamEditPopoverBinding(for stream: KodaiStream) -> Binding<Bool> {
        Binding(
            get: { editingStream?.id == stream.id },
            set: { if !$0 { closeEditingStream() } }
        )
    }

    private func streamEditPopover(for stream: KodaiStream) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit stream")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            TextField("Stream name", text: $draftStreamTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { closeEditingStream() }
                Spacer()
                Button("Rename") {
                    onRenameStream(stream, draftStreamTitle)
                    closeEditingStream()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            Button(role: .destructive) {
                closeEditingStream()
                streamPendingDelete = stream
            } label: {
                Label("Delete stream", systemImage: "trash")
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    // MARK: – Loose Chats

    private var chatHistorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.18)
                .padding(.vertical, 3)

            Text("Loose Chats")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            if chatSessions.isEmpty {
                Text("No loose chats")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 8)
                    .frame(height: 30)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(chatSessions, id: \.id) { session in
                        sidebarChat(session)
                    }
                }
            }
        }
    }

    // MARK: – Chrome

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
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

            if sidebarOpen {
                ZStack(alignment: .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .blur(radius: 24)
                        .opacity(breathing ? 0.13 : 0.0)
                        .allowsHitTesting(false)

                    VStack(alignment: .center, spacing: 2) {
                        Text("KodAi")
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .foregroundStyle(theme.primaryText)

                        Text("Local dev assistant")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()
            }
        }
        .frame(height: sidebarOpen ? 44 : 42)
        .onChange(of: glassBoxSignalState.isActive) { _, loading in
            if loading {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.8)) {
                    breathing = false
                }
            }
        }
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
        .accessibilityIdentifier("settings.open")
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            KodaiSettingsView(
                selectedMode: $selectedMode,
                telemetryStore: telemetryStore,
                onResetSession: {
                    onResetSession()
                    showingSettings = false
                }
            )
        }
    }

    // MARK: – Chat rows

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
            get: { editingChat?.id == session.id },
            set: { if !$0 { closeEditing() } }
        )
    }

    private func chatEditPopover(for session: KodaiChatSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit chat")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            TextField("Chat name", text: $draftChatTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { closeEditing() }
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
        let isActiveThread = selectedChatID == session.id
        let dotPulsing = isActiveThread && glassBoxSignalState.isActive

        return HStack(spacing: 10) {
            Circle()
                .fill(isActiveThread ? .white.opacity(dotPulsing && breathing ? 1.0 : 0.72) : .clear)
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .frame(width: 6, height: 6)
                .scaleEffect(dotPulsing ? (breathing ? 1.4 : 1.0) : 1.0)

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
        .draggable(session.id.uuidString)
        .onTapGesture {
            onSelectChat(session)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                beginEditing(session)
            }
        )
        .contextMenu {
            Button("Rename") { beginEditing(session) }

            if !streams.isEmpty {
                Menu("Move to Stream") {
                    ForEach(streams, id: \.id) { stream in
                        Button(stream.title) { onAssignChat(session, stream) }
                    }
                }
            }

            if !projects.isEmpty {
                Menu("Assign to Project") {
                    ForEach(projects.filter { $0.status != .archived }, id: \.id) { project in
                        Button(project.title) { onAssignChatToProject(session, project) }
                    }
                }
            }

            Button(role: .destructive) { onDeleteChat(session) } label: { Text("Delete") }
        }
        .popover(isPresented: editPopoverBinding(for: session)) {
            chatEditPopover(for: session)
        }
    }

    // MARK: – Helpers

    private func findSession(by id: UUID) -> KodaiChatSession? {
        chatSessions.first { $0.id == id }
    }

    private func modeIcon(for mode: OutputMode) -> String {
        switch mode {
        case .chat:       return "bubble.left.and.bubble.right"
        case .organize:   return "tray.full"
        case .summarize:  return "text.alignleft"
        case .checklist:  return "checklist"
        case .debug:      return "ladybug"
        }
    }
}

private struct KodaiSidebarGlassBox: View {
    @Environment(\.kodaiTheme) private var theme

    let signalState: LiveEntitySignalState
    let isSelected: Bool
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Glass Box")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .stroke(theme.primaryText.opacity(0.72), lineWidth: 1)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle()
                                    .fill(theme.primaryText.opacity(0.62))
                                    .frame(width: 3, height: 3)
                            }

                        Text(signalState.status.rawValue)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                WorkloadBloomView(
                    signalState: signalState
                )
                .scaleEffect(0.72)
                .frame(height: 76)
                .frame(maxWidth: .infinity)

                HStack(spacing: 5) {
                    Text("Local")
                    Circle()
                        .fill(theme.secondaryText.opacity(0.45))
                        .frame(width: 2.5, height: 2.5)
                    Text("Ready")
                    Circle()
                        .fill(theme.secondaryText.opacity(0.45))
                        .frame(width: 2.5, height: 2.5)
                    Text("On-device")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.72))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 184, height: 132, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.glassSurface)
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.primaryAccent.opacity(0.055))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    theme.primaryAccent.opacity(isSelected ? 0.34 : (isHovering ? 0.16 : 0.06)),
                    lineWidth: isSelected ? 1 : 0.75
                )
        }
        .opacity(isHovering && !isSelected ? 0.96 : 1)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityIdentifier("glassBox.sidebar")
        .accessibilityLabel("Glass Box")
        .accessibilityHint("Opens local model visibility")
    }
}
