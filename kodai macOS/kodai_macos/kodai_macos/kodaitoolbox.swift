//
//  kodaitoolbox.swift
//  kodai_macos
//
//  Foundation Models tool definitions for Kodai. Tools execute for real:
//  a mutating call suspends on ConfirmBroker until the user approves the
//  inline card, then WorkspaceToolExecutor performs the SwiftData write and
//  the model receives the true outcome as a structured ToolResult, so it can
//  continue the chain or report honestly.
//

import Foundation
import FoundationModels
import KodaiCore

// MARK: - Tool argument types

/// @Generable satisfies Tool.Arguments : ConvertibleFromGeneratedContent
/// and provides the default parameters schema.
@Generable(description: "A request to create a new task")
struct TaskCreationRequest {
    @Guide(description: "The title of the task, e.g. 'Finish design doc'")
    var title: String

    @Guide(description: "Priority level: low, medium, or high")
    var priority: String

    @Guide(description: "Due date in YYYY-MM-DD format, or empty string if none")
    var dueDate: String
}

@Generable(description: "A request to create a new project")
struct ProjectCreationRequest {
    @Guide(description: "The name of the project, e.g. 'WGU'")
    var title: String
}

// MARK: - Due date semantics

enum TaskDueDateSemantics {
    nonisolated static func normalized(_ date: Date, calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    nonisolated static func parse(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let parsed = KodaiSlashCommandParser.parseDueValue(
            sanitizedDateToken(raw),
            now: now,
            calendar: calendar
        ) else {
            return nil
        }
        return normalized(parsed, calendar: calendar)
    }

    nonisolated static func correctionDate(
        from input: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let lowercased = input.lowercased()
        let isExplicitCorrection =
            lowercased.hasPrefix("no") ||
            lowercased.contains("wrong date") ||
            lowercased.contains("make it due")
        guard isExplicitCorrection,
              lowercased.contains("due") || lowercased.contains("wrong date") else {
            return nil
        }

        let cleaned = lowercased.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "/" {
                return character
            }
            return " "
        }
        let tokens = String(cleaned).split(whereSeparator: \.isWhitespace).map(String.init)

        for token in tokens.reversed() {
            if let date = parse(token, now: now, calendar: calendar) {
                return date
            }
        }

        guard tokens.count >= 2 else { return nil }
        for index in stride(from: tokens.count - 2, through: 0, by: -1) {
            let candidate = tokens[index] + sanitizedDateToken(tokens[index + 1])
            if let date = parse(candidate, now: now, calendar: calendar) {
                return date
            }
        }
        return nil
    }

    nonisolated private static func sanitizedDateToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["th", "st", "nd", "rd"] where trimmed.hasSuffix(suffix) {
            let withoutSuffix = String(trimmed.dropLast(suffix.count))
            if Int(withoutSuffix) != nil {
                return withoutSuffix
            }
        }
        return trimmed
    }
}

// MARK: - Workspace tool executor

/// Runs workspace (SwiftData) tool calls behind the confirm gate. The actual
/// write closures are bound by ChatViewModel at the start of each turn — they
/// capture that turn's ModelContext and project list — and cleared after, so
/// a tool can never write through a stale context.
@MainActor
final class WorkspaceToolExecutor {
    static let createTaskToolID = "task_create"
    static let createProjectToolID = "project_create"

    let broker: ConfirmBroker

    var onActivity: ((ToolActivity) -> Void)?
    var performCreateTask: ((_ title: String, _ priority: TaskPriority, _ dueDate: Date?) -> ToolResult)?
    var performCreateProject: ((_ title: String) -> ToolResult)?

    init(broker: ConfirmBroker) {
        self.broker = broker
    }

    func clearTurnBindings() {
        onActivity = nil
        performCreateTask = nil
        performCreateProject = nil
    }

    func createTask(title: String, priority: String, dueDate rawDueDate: String) async -> ToolResult {
        let toolID = Self.createTaskToolID
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return .failure(tool: toolID, error: "missing task title")
        }
        guard let perform = performCreateTask else {
            return .failure(tool: toolID, error: "workspace unavailable")
        }

        let priorityValue = TaskPriority(rawValue: priority.lowercased()) ?? .medium
        let cleanDue = rawDueDate.trimmingCharacters(in: .whitespaces)
        let parsedDue = cleanDue.isEmpty ? nil : TaskDueDateSemantics.parse(cleanDue)

        var details = [ToolConfirmationRequest.Detail(icon: "flag", text: priorityValue.rawValue)]
        if let due = parsedDue {
            details.append(ToolConfirmationRequest.Detail(icon: "calendar", text: Self.mediumDate(due)))
        }

        onActivity?(ToolActivity(tool: toolID, phase: .awaitingConfirmation, detail: cleanTitle))
        let approved = await broker.request(ToolConfirmationRequest(
            heading: "Create task?",
            subject: cleanTitle,
            details: details,
            confirmLabel: "Create Task"
        ))
        guard approved else {
            onActivity?(ToolActivity(tool: toolID, phase: .cancelled, detail: cleanTitle))
            return .failure(tool: toolID, error: "cancelled_by_user")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .executing, detail: cleanTitle))
        let result = perform(cleanTitle, priorityValue, parsedDue)
        onActivity?(ToolActivity(
            tool: toolID,
            phase: result.status == .ok ? .succeeded : .failed,
            detail: cleanTitle
        ))
        return result
    }

    func createProject(title: String) async -> ToolResult {
        let toolID = Self.createProjectToolID
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !cleanTitle.isEmpty else {
            return .failure(tool: toolID, error: "missing project name")
        }
        guard let perform = performCreateProject else {
            return .failure(tool: toolID, error: "workspace unavailable")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .awaitingConfirmation, detail: cleanTitle))
        let approved = await broker.request(ToolConfirmationRequest(
            heading: "Create project?",
            subject: cleanTitle,
            details: [],
            confirmLabel: "Create Project"
        ))
        guard approved else {
            onActivity?(ToolActivity(tool: toolID, phase: .cancelled, detail: cleanTitle))
            return .failure(tool: toolID, error: "cancelled_by_user")
        }

        onActivity?(ToolActivity(tool: toolID, phase: .executing, detail: cleanTitle))
        let result = perform(cleanTitle)
        onActivity?(ToolActivity(
            tool: toolID,
            phase: result.status == .ok ? .succeeded : .failed,
            detail: cleanTitle
        ))
        return result
    }

    private static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Foundation Models tools

struct CreateTaskTool: Tool {
    typealias Arguments = TaskCreationRequest

    let executor: WorkspaceToolExecutor

    var name: String { "createTask" }

    var description: String {
        "Create a new task in the user's current project. The user approves it before it is saved. The returned JSON is the real outcome — report it truthfully."
    }

    func call(arguments: TaskCreationRequest) async throws -> String {
        await executor.createTask(
            title: arguments.title,
            priority: arguments.priority,
            dueDate: arguments.dueDate
        ).asContextJSON()
    }
}

struct CreateProjectTool: Tool {
    typealias Arguments = ProjectCreationRequest

    let executor: WorkspaceToolExecutor

    var name: String { "createProject" }

    var description: String {
        "Create a new project for the user. The user approves it before it is saved. The returned JSON is the real outcome — report it truthfully."
    }

    func call(arguments: ProjectCreationRequest) async throws -> String {
        await executor.createProject(title: arguments.title).asContextJSON()
    }
}
