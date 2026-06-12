//
//  WorkspaceValueModels.swift
//  KodaiKernel
//
//  Foundation-only project/task value vocabulary shared across platforms.
//  Persistence layers (SwiftData on macOS, JSON on iOS) adapt to/from
//  these portable values; this file must never import SwiftData.
//

import Foundation

public enum KodaiTaskPriority: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case high
}

public struct KodaiTaskValue: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var details: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var dueDate: Date?
    public var priority: KodaiTaskPriority
    public var isCompleted: Bool
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        details: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueDate: Date? = nil,
        priority: KodaiTaskPriority = .normal,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case details
        case createdAt
        case updatedAt
        case dueDate
        case priority
        case isCompleted
        case completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(KodaiTaskPriority.self, forKey: .priority) ?? .normal
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// A due/overdue task paired with its owning project, for "Today"-style views.
public struct DueTaskValue: Identifiable, Equatable, Sendable {
    public let task: KodaiTaskValue
    public let projectID: UUID
    public let projectTitle: String
    public let isOverdue: Bool

    public var id: UUID { task.id }

    public init(task: KodaiTaskValue, projectID: UUID, projectTitle: String, isOverdue: Bool) {
        self.task = task
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.isOverdue = isOverdue
    }
}

public struct KodaiProjectValue: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var details: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var deadline: Date?
    public var tasks: [KodaiTaskValue]

    public var incompleteTasks: [KodaiTaskValue] {
        tasks.filter { !$0.isCompleted }
    }

    public var completedTasks: [KodaiTaskValue] {
        tasks.filter { $0.isCompleted }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        details: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deadline: Date? = nil,
        tasks: [KodaiTaskValue] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deadline = deadline
        self.tasks = tasks
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case details
        case createdAt
        case updatedAt
        case deadline
        case tasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        tasks = try container.decodeIfPresent([KodaiTaskValue].self, forKey: .tasks) ?? []
    }
}
