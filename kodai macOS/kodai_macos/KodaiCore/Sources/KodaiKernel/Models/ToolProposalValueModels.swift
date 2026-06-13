//
//  ToolProposalValueModels.swift
//  KodaiKernel
//
//  Shared portable tool proposal vocabulary. Pure Foundation value types —
//  each app owns proposal execution and UI; the kernel only defines the
//  in-memory proposal shapes exchanged between chat and confirmation flows.
//

import Foundation

public enum KodaiToolProposalKind: String, Codable, Sendable {
    case createTask
}

public struct KodaiCreateTaskProposalValue: Equatable, Codable, Sendable {
    public var title: String
    public var details: String?
    public var projectID: UUID?
    public var projectTitle: String?
    public var dueDate: Date?
    public var priority: KodaiTaskPriority

    public init(
        title: String,
        details: String? = nil,
        projectID: UUID? = nil,
        projectTitle: String? = nil,
        dueDate: Date? = nil,
        priority: KodaiTaskPriority = .normal
    ) {
        self.title = title
        self.details = details
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.dueDate = dueDate
        self.priority = priority
    }
}

public struct KodaiPendingToolProposalValue: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let kind: KodaiToolProposalKind
    public var title: String
    public var message: String
    public let createdAt: Date
    public var createTask: KodaiCreateTaskProposalValue?

    public init(
        id: UUID = UUID(),
        kind: KodaiToolProposalKind,
        title: String,
        message: String = "",
        createdAt: Date = Date(),
        createTask: KodaiCreateTaskProposalValue? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.createTask = createTask
    }
}
