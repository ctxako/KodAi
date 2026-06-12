//
//  ToolProposalModels.swift
//  kodAI_chatbot_dev
//
//  Lightweight iOS-local tool proposal models. In-memory only for now —
//  the assistant (or a deterministic test path) proposes an action and the
//  user confirms or cancels it. Designed to be bridged to model-generated
//  proposals in a later phase.
//

import Foundation

enum ToolProposalKindLite: String, Codable, Sendable {
    case createTask
}

struct CreateTaskProposalLite: Equatable, Codable, Sendable {
    var title: String
    var details: String?
    var projectID: UUID?
    var projectTitle: String?
    var dueDate: Date?
    var priority: TaskPriorityLite

    init(
        title: String,
        details: String? = nil,
        projectID: UUID? = nil,
        projectTitle: String? = nil,
        dueDate: Date? = nil,
        priority: TaskPriorityLite = .normal
    ) {
        self.title = title
        self.details = details
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.dueDate = dueDate
        self.priority = priority
    }
}

struct PendingToolProposalLite: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let kind: ToolProposalKindLite
    var title: String
    var message: String?
    let createdAt: Date
    var createTask: CreateTaskProposalLite?

    init(
        id: UUID = UUID(),
        kind: ToolProposalKindLite,
        title: String,
        message: String? = nil,
        createdAt: Date = Date(),
        createTask: CreateTaskProposalLite? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.createTask = createTask
    }
}
