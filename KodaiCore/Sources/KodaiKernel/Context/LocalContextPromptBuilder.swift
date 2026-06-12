//
//  LocalContextPromptBuilder.swift
//  KodaiKernel
//
//  Shared lightweight local-context prompt assembly. Builds the compact
//  [LOCAL KODAI CONTEXT] block injected per-request into the runtime
//  system prompt (never persisted as a chat message) plus the glass-box
//  ContextBlock values describing what surrounded the turn.
//
//  Foundation-only: apps gather their own local data (selected project,
//  due tasks, assistant mode) and pass it in as portable values; this
//  file owns the formatting and the action-rule wording.
//

import Foundation

/// App-provided picture of the local workspace at send time.
public struct KodaiLocalContextSnapshotValue: Sendable {
    public var selectedProject: KodaiProjectValue?
    /// Overdue + due-today tasks across all projects. Overdue items are
    /// listed before today items in the prompt regardless of input order.
    public var todayAndOverdueTasks: [DueTaskValue]
    public var assistantModeDescription: String?
    public var currentMessageCount: Int?
    public var currentChatTokenEstimate: Int?
    public var injectedReason: String?

    public init(
        selectedProject: KodaiProjectValue? = nil,
        todayAndOverdueTasks: [DueTaskValue] = [],
        assistantModeDescription: String? = nil,
        currentMessageCount: Int? = nil,
        currentChatTokenEstimate: Int? = nil,
        injectedReason: String? = nil
    ) {
        self.selectedProject = selectedProject
        self.todayAndOverdueTasks = todayAndOverdueTasks
        self.assistantModeDescription = assistantModeDescription
        self.currentMessageCount = currentMessageCount
        self.currentChatTokenEstimate = currentChatTokenEstimate
        self.injectedReason = injectedReason
    }
}

public struct KodaiLocalContextPromptOptions: Sendable {
    public var maxProjectTasks: Int
    public var maxDueTasks: Int
    public var includeActionRules: Bool

    public init(
        maxProjectTasks: Int = 8,
        maxDueTasks: Int = 8,
        includeActionRules: Bool = true
    ) {
        self.maxProjectTasks = maxProjectTasks
        self.maxDueTasks = maxDueTasks
        self.includeActionRules = includeActionRules
    }
}

public struct KodaiLocalContextPromptResult: Sendable {
    /// Compact prompt block for the runtime system prompt, or nil when
    /// there is no selected project and no due tasks to inject.
    public let promptBlock: String?
    /// Glass-box display blocks describing the turn's local context.
    public let contextBlocks: [ContextBlock]

    public init(promptBlock: String?, contextBlocks: [ContextBlock]) {
        self.promptBlock = promptBlock
        self.contextBlocks = contextBlocks
    }
}

public enum KodaiLocalContextPromptBuilder {

    public static func build(
        snapshot: KodaiLocalContextSnapshotValue,
        options: KodaiLocalContextPromptOptions = KodaiLocalContextPromptOptions()
    ) -> KodaiLocalContextPromptResult {
        let promptBlock = buildPromptBlock(snapshot: snapshot, options: options)
        let contextBlocks = buildContextBlocks(snapshot: snapshot, promptBlock: promptBlock)
        return KodaiLocalContextPromptResult(promptBlock: promptBlock, contextBlocks: contextBlocks)
    }

    // MARK: - Prompt block

    static func buildPromptBlock(
        snapshot: KodaiLocalContextSnapshotValue,
        options: KodaiLocalContextPromptOptions
    ) -> String? {
        var lines: [String] = []

        if let project = snapshot.selectedProject {
            lines.append("Selected project: \(project.title)")
            if let deadline = project.deadline {
                lines.append("Project deadline: \(deadline.formatted(date: .abbreviated, time: .omitted))")
            }
            let activeTasks = project.incompleteTasks.prefix(max(0, options.maxProjectTasks))
            if !activeTasks.isEmpty {
                lines.append("Active tasks:")
                for task in activeTasks {
                    lines.append("- \(task.title)")
                }
            }
        }

        let overdue = snapshot.todayAndOverdueTasks.filter(\.isOverdue)
        let today = snapshot.todayAndOverdueTasks.filter { !$0.isOverdue }
        let dueList = Array((overdue + today).prefix(max(0, options.maxDueTasks)))
        if !dueList.isEmpty {
            lines.append("Today / overdue:")
            for item in dueList {
                let label = item.isOverdue ? "Overdue" : "Today"
                lines.append("- \(label): \(item.task.title) — \(item.projectTitle)")
            }
        }

        guard !lines.isEmpty else { return nil }

        let body = lines.joined(separator: "\n")
        let rules = options.includeActionRules ? """

        Rules:
        - You may use this local context to answer.
        - Do not claim to create, edit, delete, or complete tasks directly.
        - For actions, suggest slash commands like /task, /done, or /propose task.
        """ : ""
        return """
        [LOCAL KODAI CONTEXT]
        \(body)\(rules)
        [/LOCAL KODAI CONTEXT]
        """
    }

    // MARK: - Glass-box blocks

    static func buildContextBlocks(
        snapshot: KodaiLocalContextSnapshotValue,
        promptBlock: String?
    ) -> [ContextBlock] {
        var blocks: [ContextBlock] = []

        if let mode = snapshot.assistantModeDescription {
            blocks.append(ContextBlock(
                kind: "Assistant mode",
                content: mode,
                tokenEstimate: 0,
                priority: blocks.count
            ))
        }

        if let project = snapshot.selectedProject {
            let activeTaskCount = project.incompleteTasks.count
            blocks.append(ContextBlock(
                kind: "Selected project",
                content: "\(project.title) · \(activeTaskCount) active task\(activeTaskCount == 1 ? "" : "s")",
                tokenEstimate: 0,
                priority: blocks.count,
                sourceID: project.id
            ))
        } else {
            blocks.append(ContextBlock(
                kind: "Selected project",
                content: "None",
                tokenEstimate: 0,
                priority: blocks.count
            ))
        }

        let overdueCount = snapshot.todayAndOverdueTasks.filter(\.isOverdue).count
        let todayCount = snapshot.todayAndOverdueTasks.count - overdueCount
        blocks.append(ContextBlock(
            kind: "Today / overdue",
            content: "\(todayCount) due today, \(overdueCount) overdue",
            tokenEstimate: 0,
            priority: blocks.count
        ))

        if let messageCount = snapshot.currentMessageCount {
            blocks.append(ContextBlock(
                kind: "Current chat",
                content: "\(messageCount) messages",
                tokenEstimate: snapshot.currentChatTokenEstimate ?? 0,
                priority: blocks.count
            ))
        }

        if let promptBlock {
            blocks.append(ContextBlock(
                kind: "Local context",
                content: "Injected into latest prompt · visible to model · not saved as a chat message",
                tokenEstimate: TokenEstimator.estimate(characterCount: promptBlock.count),
                priority: blocks.count
            ))
        } else {
            blocks.append(ContextBlock(
                kind: "Local context",
                content: "Nothing injected — no project or due-task context",
                tokenEstimate: 0,
                priority: blocks.count
            ))
        }

        return blocks
    }
}
