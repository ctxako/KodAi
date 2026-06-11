//
//  kodaiprojectheader.swift
//  kodai_macos
//

import SwiftUI
import KodaiCore

struct KodaiProjectHeader: View {
    let project: KodaiProject
    let session: KodaiChatSession?
    let isGenerating: Bool
    let onUpdateSummary: (String) -> Void
    let onGenerateSummary: () -> Void
    let onCreateTask: (String, String, TaskPriority) -> Void
    let onToggleTask: (KodaiTask) -> Void
    let onDeleteTask: (KodaiTask) -> Void
    let onRenameTask: (KodaiTask, String) -> Void

    @State private var editingSummary = false
    @State private var summaryDraft = ""
    @FocusState private var summaryFocused: Bool

    @State private var tasksExpanded = true
    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskPriority: TaskPriority = .medium
    @State private var hoveredTaskID: UUID? = nil
    @State private var editingTaskID: UUID? = nil
    @State private var editingTaskTitle = ""
    @FocusState private var addTaskFocused: Bool
    @FocusState private var renameTaskFocused: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let completedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private var lastActivity: Date {
        session?.updatedAt ?? project.updatedAt
    }

    private var isSummaryStale: Bool {
        let msgs = session?.messages ?? []
        guard !msgs.isEmpty else { return false }
        guard let updatedAt = project.summaryUpdatedAt else {
            return msgs.count > 10
        }
        return msgs.filter { $0.createdAt > updatedAt }.count > 10
    }

    private var statusColor: Color {
        switch project.status {
        case .active:   return .green
        case .paused:   return .orange
        case .archived: return .gray
        }
    }

    private var openTaskCount: Int {
        project.tasks.filter { !$0.isCompleted }.count
    }

    private var sortedTasks: [KodaiTask] {
        let active = project.tasks
            .filter { !$0.isCompleted }
            .sorted { taskPriorityOrder($0.priority) < taskPriorityOrder($1.priority) }
        let done = project.tasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        return active + done
    }

    private var markdownExport: String {
        var lines: [String] = []
        lines.append("# \(project.title)")
        lines.append("")

        if let summary = project.summary, !summary.isEmpty {
            lines.append("## Summary")
            lines.append(summary)
            lines.append("")
        }

        let active = sortedTasks.filter { !$0.isCompleted }
        if !active.isEmpty {
            lines.append("## Active Tasks")
            for task in active {
                lines.append("- [ ] \(task.title) (\(task.priority.rawValue))")
            }
            lines.append("")
        }

        let done = sortedTasks.filter { $0.isCompleted }
        if !done.isEmpty {
            lines.append("## Completed Tasks")
            for task in done {
                let dateStr = task.completedAt.map { Self.completedFormatter.string(from: $0) } ?? ""
                lines.append("- [x] \(task.title)\(dateStr.isEmpty ? "" : " — \(dateStr)")")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .padding(.horizontal, 16)
                .padding(.top, 10)

            summaryRow
                .padding(.horizontal, 16)
                .padding(.top, 4)

            taskSection
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
        .onChange(of: editingSummary) { _, editing in
            if editing { summaryFocused = true }
        }
        .onChange(of: showAddTask) { _, showing in
            if showing { addTaskFocused = true }
        }
        .onChange(of: editingTaskID) { _, id in
            if id != nil { renameTaskFocused = true }
        }
    }

    // MARK: – Title row

    private var titleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(project.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            statusBadge

            Spacer()

            Text(Self.dateFormatter.string(from: lastActivity))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))

            openTasksChip

            ShareLink(
                item: markdownExport,
                subject: Text(project.title)
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help("Export project as markdown")
        }
    }

    // MARK: – Summary row

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 6) {
            if editingSummary {
                TextField(
                    "Summarize this project…",
                    text: $summaryDraft,
                    axis: .vertical
                )
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($summaryFocused)
                .onSubmit { commitSummary() }

                Button("Save") { commitSummary() }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
            } else {
                Text(project.summary ?? "No summary — tap to add")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(project.summary == nil ? .white.opacity(0.3) : .white.opacity(0.65))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditingSummary() }

                if isSummaryStale {
                    Label("stale", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.8))
                        .labelStyle(.titleAndIcon)
                }

                Button {
                    onGenerateSummary()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.45))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .help("Generate project summary with AI")
            }
        }
    }

    // MARK: – Task section

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            taskSectionHeader
                .padding(.top, 8)

            if tasksExpanded {
                if showAddTask {
                    addTaskRow
                }

                if sortedTasks.isEmpty && !showAddTask {
                    Text("No tasks yet")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.vertical, 4)
                } else if !sortedTasks.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(sortedTasks, id: \.id) { task in
                                taskRow(task)
                            }
                        }
                    }
                    .frame(maxHeight: 156)
                }
            }
        }
    }

    private var taskSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            Text("Tasks")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))

            if openTaskCount > 0 {
                Text("\(openTaskCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                showAddTask.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    tasksExpanded.toggle()
                }
            } label: {
                Image(systemName: tasksExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
    }

    private var addTaskRow: some View {
        HStack(spacing: 8) {
            TextField("Task title", text: $newTaskTitle)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .textFieldStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .focused($addTaskFocused)
                .onSubmit { commitAddTask() }

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
                .padding(.vertical, 3)
                .background(.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)

            Button("Add") { commitAddTask() }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .buttonStyle(.plain)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel") { cancelAddTask() }
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func taskRow(_ task: KodaiTask) -> some View {
        HStack(spacing: 8) {
            Button {
                onToggleTask(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted ? .white.opacity(0.4) : .white.opacity(0.6))
            }
            .buttonStyle(.plain)

            if editingTaskID == task.id {
                TextField("", text: $editingTaskTitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white.opacity(0.9))
                    .focused($renameTaskFocused)
                    .onSubmit { commitTaskRename(task) }
            } else {
                Text(task.title)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(task.isCompleted ? .white.opacity(0.3) : .white.opacity(0.8))
                    .strikethrough(task.isCompleted, color: .white.opacity(0.3))
                    .lineLimit(1)
            }

            if !task.isCompleted {
                priorityBadge(task.priority)
            } else if let completedAt = task.completedAt {
                Text(Self.completedFormatter.string(from: completedAt))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Spacer()

            Button {
                onDeleteTask(task)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .opacity(hoveredTaskID == task.id ? 1 : 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hoveredTaskID = $0 ? task.id : nil }
        .contextMenu {
            Button(task.isCompleted ? "Mark incomplete" : "Mark complete") {
                onToggleTask(task)
            }
            Button("Rename") { beginTaskRename(task) }
            Divider()
            Button(role: .destructive) { onDeleteTask(task) } label: {
                Text("Delete")
            }
        }
    }

    // MARK: – Chips and badges

    private var statusBadge: some View {
        Text(project.status.rawValue)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var openTasksChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
            Text("\(openTaskCount)")
                .font(.system(size: 11, weight: .regular, design: .rounded))
        }
        .foregroundStyle(openTaskCount > 0 ? .white.opacity(0.55) : .white.opacity(0.3))
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

    private func taskPriorityOrder(_ p: TaskPriority) -> Int {
        switch p {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    private func beginEditingSummary() {
        summaryDraft = project.summary ?? ""
        editingSummary = true
    }

    private func commitSummary() {
        onUpdateSummary(summaryDraft)
        editingSummary = false
    }

    private func beginTaskRename(_ task: KodaiTask) {
        editingTaskTitle = task.title
        editingTaskID = task.id
        renameTaskFocused = true
    }

    private func commitTaskRename(_ task: KodaiTask) {
        let clean = editingTaskTitle.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { onRenameTask(task, clean) }
        editingTaskID = nil
        editingTaskTitle = ""
    }

    private func commitAddTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        onCreateTask(title, "", newTaskPriority)
        newTaskTitle = ""
        newTaskPriority = .medium
        showAddTask = false
    }

    private func cancelAddTask() {
        newTaskTitle = ""
        newTaskPriority = .medium
        showAddTask = false
    }
}
