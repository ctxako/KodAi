//
//  streamview.swift
//  kodai_macos
//

import SwiftUI
import KodaiCore

struct StreamView: View {
    let projects: [KodaiProject]
    let onCreateProject: () -> Void
    let onCreateTask: (KodaiProject, String, String, TaskPriority, Date?) -> Void
    let onToggleTask: (KodaiTask) -> Void
    let onDeleteTask: (KodaiTask) -> Void
    let onSelectProject: (KodaiProject) -> Void
    let onClose: () -> Void

    @Environment(\.kodaiTheme) private var theme

    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskPriority: TaskPriority = .medium
    @State private var newTaskDueDate: Date? = nil
    @State private var showNewTaskDatePicker = false
    @State private var selectedProjectID: UUID? = nil
    @State private var hoveredTaskID: UUID? = nil
    @FocusState private var addTaskFocused: Bool

    private var activeProjects: [KodaiProject] {
        projects.filter { $0.status == .active }
    }

    private var archivedProjects: [KodaiProject] {
        projects.filter { $0.status == .archived }
    }

    private var activeTasks: [KodaiTask] {
        activeProjects
            .flatMap { $0.tasks ?? [] }
            .filter { !$0.isCompleted }
            .sorted {
                if $0.priority.sortOrder != $1.priority.sortOrder {
                    return $0.priority.sortOrder < $1.priority.sortOrder
                }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
    }

    private var recentCompleted: [KodaiTask] {
        projects
            .flatMap { $0.tasks ?? [] }
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
            .prefix(10)
            .map { $0 }
    }

    private var selectedProject: KodaiProject? {
        guard let id = selectedProjectID else {
            return activeProjects.first
        }
        return activeProjects.first { $0.id == id } ?? activeProjects.first
    }

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let completedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            streamHeader
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    activeTasksSection
                    activeProjectsSection
                    completedSection
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: showAddTask) { _, showing in
            if showing { addTaskFocused = true }
        }
    }

    // MARK: – Header

    private var streamHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryAccent)

            Text("Stream")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)

            Spacer()

            Button {
                onCreateProject()
            } label: {
                Label("New Project", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    showAddTask.toggle()
                }
            } label: {
                Label("New Task", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }

    // MARK: – Active Tasks

    private var activeTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Active Tasks", icon: "checkmark.circle", count: activeTasks.count)

            if showAddTask {
                addTaskCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if activeTasks.isEmpty && !showAddTask {
                emptyState(
                    icon: "checkmark.circle.trianglebadge.exclamationmark",
                    title: "No active tasks",
                    detail: "Tasks created in chat or here appear in this section."
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(activeTasks, id: \.id) { task in
                        streamTaskRow(task)
                    }
                }
                .padding(.vertical, 4)
                .background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func streamTaskRow(_ task: KodaiTask) -> some View {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let overdue = task.dueDate.map { $0 < startOfToday } ?? false

        return HStack(spacing: 10) {
            Button {
                onToggleTask(task)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                if let projectTitle = task.project?.title {
                    Text(projectTitle)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer()

            priorityBadge(task.priority)

            if let dueDate = task.dueDate {
                dueDateBadge(dueDate, overdue: overdue)
            }

            if hoveredTaskID == task.id {
                Button {
                    onDeleteTask(task)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hoveredTaskID == task.id ? .white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hoveredTaskID = $0 ? task.id : nil }
    }

    // MARK: – Add Task Card

    private var addTaskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Task title", text: $newTaskTitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.9))
                    .focused($addTaskFocused)
                    .onSubmit { commitAddTask() }

                priorityPicker

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        showNewTaskDatePicker.toggle()
                        if !showNewTaskDatePicker { newTaskDueDate = nil }
                        else if newTaskDueDate == nil { newTaskDueDate = Calendar.current.startOfDay(for: Date()) }
                    }
                } label: {
                    Image(systemName: newTaskDueDate != nil ? "calendar.badge.checkmark" : "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(newTaskDueDate != nil ? .blue.opacity(0.85) : .white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                if activeProjects.count > 1 {
                    Menu {
                        ForEach(activeProjects, id: \.id) { project in
                            Button(project.title) { selectedProjectID = project.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(selectedProject?.title ?? "Select project")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if let project = activeProjects.first {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(project.title)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }

                if showNewTaskDatePicker {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { newTaskDueDate ?? Calendar.current.startOfDay(for: Date()) },
                            set: { newTaskDueDate = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorScheme(.dark)

                    Button {
                        newTaskDueDate = nil
                        showNewTaskDatePicker = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Add") { commitAddTask() }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .buttonStyle(.plain)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedProject == nil)

                Button("Cancel") { cancelAddTask() }
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var priorityPicker: some View {
        Menu {
            Button("High") { newTaskPriority = .high }
            Button("Medium") { newTaskPriority = .medium }
            Button("Low") { newTaskPriority = .low }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(priorityColor(newTaskPriority))
                    .frame(width: 6, height: 6)
                Text(newTaskPriority.rawValue.prefix(1).uppercased())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: – Active Projects

    private var activeProjectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Active Projects", icon: "folder.fill", count: activeProjects.count)

            if activeProjects.isEmpty {
                emptyState(
                    icon: "folder.badge.questionmark",
                    title: "No projects yet",
                    detail: "Create a project from chat with /project or use the button above."
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(activeProjects, id: \.id) { project in
                        streamProjectCard(project)
                    }
                }
            }
        }
    }

    private func streamProjectCard(_ project: KodaiProject) -> some View {
        let openTasks = (project.tasks ?? []).filter { !$0.isCompleted }
        let completedTasks = (project.tasks ?? []).filter { $0.isCompleted }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let overdueCount = openTasks.filter { ($0.dueDate ?? .distantFuture) < startOfToday }.count

        return Button {
            onSelectProject(project)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryAccent.opacity(0.7))

                    Text(project.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    Spacer()

                    if let deadline = project.deadline {
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8))
                            Text(Self.dueDateFormatter.string(from: deadline))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(deadline < Date() ? .red.opacity(0.8) : .orange.opacity(0.7))
                    }
                }

                if let summary = project.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "circle")
                            .font(.system(size: 9))
                        Text("\(openTasks.count) open")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.45))

                    if completedTasks.count > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("\(completedTasks.count) done")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.3))
                    }

                    if overdueCount > 0 {
                        Text("\(overdueCount) overdue")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.7))
                    }

                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: – Completed

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Recently Completed", icon: "checkmark.circle.fill", count: recentCompleted.count)

            if recentCompleted.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "No completed tasks yet",
                    detail: "Completed tasks from any project appear here."
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(recentCompleted, id: \.id) { task in
                        completedTaskRow(task)
                    }
                }
                .padding(.vertical, 4)
                .background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func completedTaskRow(_ task: KodaiTask) -> some View {
        HStack(spacing: 10) {
            Button {
                onToggleTask(task)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .strikethrough(color: .white.opacity(0.2))
                .lineLimit(1)

            if let projectTitle = task.project?.title {
                Text(projectTitle)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()

            if let completedAt = task.completedAt {
                Text(Self.completedFormatter.string(from: completedAt))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: – Shared Components

    private func sectionHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.2))

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))

            Text(detail)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func priorityBadge(_ priority: TaskPriority) -> some View {
        let (label, color) = priorityDisplay(priority)
        return Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 14, height: 13)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func dueDateBadge(_ dueDate: Date, overdue: Bool) -> some View {
        let label = overdue ? overdueLabel(dueDate) : Self.dueDateFormatter.string(from: dueDate)
        let color: Color = overdue ? .red : .white.opacity(0.45)

        return Text(label)
            .font(.system(size: 9, weight: overdue ? .semibold : .regular, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(overdue ? Color.red.opacity(0.12) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    // MARK: – Helpers

    private func priorityColor(_ p: TaskPriority) -> Color {
        priorityDisplay(p).1
    }

    private func priorityDisplay(_ p: TaskPriority) -> (String, Color) {
        switch p {
        case .high:   return ("H", .red)
        case .medium: return ("M", .orange)
        case .low:    return ("L", .blue)
        }
    }

    private func overdueLabel(_ dueDate: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
        if days <= 0 { return "overdue" }
        if days == 1 { return "1d overdue" }
        return "\(days)d overdue"
    }

    private func commitAddTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let project = selectedProject else { return }
        onCreateTask(project, title, "", newTaskPriority, newTaskDueDate)
        newTaskTitle = ""
        newTaskPriority = .medium
        newTaskDueDate = nil
        showNewTaskDatePicker = false
        showAddTask = false
    }

    private func cancelAddTask() {
        newTaskTitle = ""
        newTaskPriority = .medium
        newTaskDueDate = nil
        showNewTaskDatePicker = false
        showAddTask = false
    }
}
