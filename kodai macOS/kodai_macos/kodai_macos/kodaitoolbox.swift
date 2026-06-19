//
//  kodaitoolbox.swift
//  kodai_macos
//
//  Foundation Models tool definitions for Kodai.
//  This file is plumbing-only: tools are wired into the session but do not
//  mutate any app data. No SwiftData writes happen here.
//

import Foundation
import FoundationModels
import KodaiCore

// MARK: - Task creation request

/// Structured argument type for the CreateTaskTool.
/// @Generable satisfies Tool.Arguments : ConvertibleFromGeneratedContent
/// and provides the default parameters schema.
@Generable(description: "A request to propose creating a new task")
struct TaskCreationRequest {
    @Guide(description: "The title of the task, e.g. 'Finish design doc'")
    var title: String

    @Guide(description: "Priority level: low, medium, or high")
    var priority: String

    @Guide(description: "Due date in YYYY-MM-DD format, or empty string if none")
    var dueDate: String
}

@Generable(description: "A request to propose creating a new project")
struct ProjectCreationRequest {
    @Guide(description: "The name of the project, e.g. 'WGU'")
    var title: String
}

// MARK: - Pending tool proposal

struct PendingToolProposal: Identifiable, Equatable {
    let id: UUID
    let kind: PendingToolProposalKind
    let createdAt: Date
    let sourceTurnID: UUID?
}

enum PendingToolProposalKind: Equatable {
    case createTask(CreateTaskProposal)
    case createProject(CreateProjectProposal)
}

struct CreateTaskProposal: Equatable {
    var title: String
    var priority: String
    var dueDate: Date?
    var projectID: UUID?
    var projectName: String?
    var rationale: String?
}

struct CreateProjectProposal: Equatable {
    var title: String
}

struct ToolProposalConfirmationContent: Equatable {
    let heading: String
    let subject: String
    let buttonLabel: String
}

extension PendingToolProposal {
    var confirmationContent: ToolProposalConfirmationContent {
        switch kind {
        case .createTask(let proposal):
            return ToolProposalConfirmationContent(
                heading: "Create task?",
                subject: proposal.title,
                buttonLabel: "Create Task"
            )
        case .createProject(let proposal):
            return ToolProposalConfirmationContent(
                heading: "Create project?",
                subject: "Create \(proposal.title) project",
                buttonLabel: "Create Project"
            )
        }
    }
}

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

// MARK: - Collector

@MainActor
final class ToolProposalCollector {
    var pending: PendingToolProposal?

    func collect(_ proposal: PendingToolProposal) {
        pending = proposal
    }

    func take() -> PendingToolProposal? {
        defer { pending = nil }
        return pending
    }
}

// MARK: - CreateTaskTool

/// Proposes a new task to the user without writing to SwiftData.
/// The model calls this when it detects task-creation intent.
/// The user must confirm before any mutation occurs.
struct CreateTaskTool: Tool {
    typealias Arguments = TaskCreationRequest

    let collector: ToolProposalCollector

    var description: String {
        "Propose creating a new task. Returns a plain-text proposal — does not persist anything. The user confirms before it is created."
    }

    func call(arguments: TaskCreationRequest) async throws -> String {
        let trimmedTitle = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDue = arguments.dueDate.trimmingCharacters(in: .whitespaces)
        let parsedDate = trimmedDue.isEmpty ? nil : TaskDueDateSemantics.parse(trimmedDue)

        let proposal = PendingToolProposal(
            id: UUID(),
            kind: .createTask(CreateTaskProposal(
                title: trimmedTitle,
                priority: arguments.priority,
                dueDate: parsedDate
            )),
            createdAt: Date(),
            sourceTurnID: nil
        )
        await collector.collect(proposal)

        let dueLabel = parsedDate.map {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: $0)
        } ?? "none"
        return "Proposed task: \(trimmedTitle) (priority: \(arguments.priority), due: \(dueLabel)). Awaiting user confirmation."
    }
}

// MARK: - CreateProjectTool

struct CreateProjectTool: Tool {
    typealias Arguments = ProjectCreationRequest

    let collector: ToolProposalCollector

    var description: String {
        "Propose creating a new project. Returns a plain-text proposal and waits for user confirmation before persisting it."
    }

    func call(arguments: ProjectCreationRequest) async throws -> String {
        let trimmedTitle = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposal = PendingToolProposal(
            id: UUID(),
            kind: .createProject(CreateProjectProposal(title: trimmedTitle)),
            createdAt: Date(),
            sourceTurnID: nil
        )
        await collector.collect(proposal)
        return "Proposed project: \(trimmedTitle). Awaiting user confirmation."
    }
}
