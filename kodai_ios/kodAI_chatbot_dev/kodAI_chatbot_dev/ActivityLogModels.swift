//
//  ActivityLogModels.swift
//  kodAI_chatbot_dev
//
//  Lightweight iOS-local activity events for glass-box visibility.
//  In-memory only for this phase — intentionally not SwiftData and not
//  the full macOS ledger/TurnRecord system.
//

import Foundation

enum ActivityKindLite: String, Codable, Sendable {
    case projectCreated
    case projectRenamed
    case projectDeleted
    case taskCreated
    case taskCompleted
    case taskReopened
    case taskDeleted
    case projectDeadlineChanged
    case toolProposalCreated
    case toolProposalConfirmed
    case toolProposalCancelled
    case slashCommandHandled

    var systemImage: String {
        switch self {
        case .projectCreated, .projectRenamed, .projectDeleted:
            return "folder"
        case .taskCreated, .taskCompleted, .taskReopened, .taskDeleted:
            return "checkmark.circle"
        case .projectDeadlineChanged:
            return "calendar"
        case .toolProposalCreated, .toolProposalConfirmed, .toolProposalCancelled:
            return "wand.and.stars"
        case .slashCommandHandled:
            return "terminal"
        }
    }
}

enum ActivitySourceLite: String, Codable, Sendable {
    case user
    case slashCommand
    case proposal
    case system

    var displayName: String {
        switch self {
        case .user:
            return "User"
        case .slashCommand:
            return "Slash command"
        case .proposal:
            return "Proposal"
        case .system:
            return "System"
        }
    }
}

struct ActivityEventLite: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let kind: ActivityKindLite
    let title: String
    let detail: String?
    let createdAt: Date
    let projectID: UUID?
    let taskID: UUID?
    let source: ActivitySourceLite

    init(
        id: UUID = UUID(),
        kind: ActivityKindLite,
        title: String,
        detail: String? = nil,
        createdAt: Date = Date(),
        projectID: UUID? = nil,
        taskID: UUID? = nil,
        source: ActivitySourceLite = .user
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
        self.projectID = projectID
        self.taskID = taskID
        self.source = source
    }
}
