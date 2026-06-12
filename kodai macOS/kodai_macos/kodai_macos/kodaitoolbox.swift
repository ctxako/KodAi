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

// MARK: - Pending tool proposal

struct PendingToolProposal: Identifiable, Equatable {
    let id: UUID
    let kind: PendingToolProposalKind
    let createdAt: Date
    let sourceTurnID: UUID?
}

enum PendingToolProposalKind: Equatable {
    case createTask(CreateTaskProposal)
}

struct CreateTaskProposal: Equatable {
    var title: String
    var priority: String
    var dueDate: Date?
    var projectID: UUID?
    var projectName: String?
    var rationale: String?
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

        var parsedDate: Date?
        if !trimmedDue.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            for fmt in ["yyyy-MM-dd", "MMM d", "MMM dd"] {
                formatter.dateFormat = fmt
                if let d = formatter.date(from: trimmedDue) {
                    if !fmt.contains("y") {
                        var comps = Calendar.current.dateComponents([.month, .day], from: d)
                        comps.year = Calendar.current.component(.year, from: Date())
                        parsedDate = Calendar.current.date(from: comps)
                    } else {
                        parsedDate = d
                    }
                    break
                }
            }
        }

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
