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

// MARK: - CreateTaskTool

/// Proposes a new task to the user without writing to SwiftData.
/// The model calls this when it detects task-creation intent.
/// The user must confirm with /task to actually create the task.
struct CreateTaskTool: Tool {
    typealias Arguments = TaskCreationRequest

    // Tool.name defaults to the type name ("CreateTaskTool"); no override needed.

    var description: String {
        "Propose creating a new task. Returns a plain-text proposal — does not persist anything. The user confirms with /task."
    }

    // Tool.parameters is provided automatically because Arguments: Generable.

    func call(arguments: TaskCreationRequest) async throws -> String {
        let due = arguments.dueDate.trimmingCharacters(in: .whitespaces).isEmpty
            ? "none"
            : arguments.dueDate
        return "I suggest creating task: \(arguments.title) (priority: \(arguments.priority), due: \(due)). Use /task to confirm."
    }
}
