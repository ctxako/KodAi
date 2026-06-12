//
//  ProjectTaskModels.swift
//  kodAI_chatbot_dev
//
//  Lightweight iOS-local project/task models. Codable structs persisted as
//  JSON, intentionally not SwiftData — designed to be bridged into KodaiCore
//  in a later phase.
//

import Foundation

enum TaskPriorityLite: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case high
}

struct KodaiTaskLite: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var details: String?
    let createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
    var priority: TaskPriorityLite
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        details: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueDate: Date? = nil,
        priority: TaskPriorityLite = .normal,
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(TaskPriorityLite.self, forKey: .priority) ?? .normal
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// A due/overdue task paired with its owning project, for the Today view.
struct DueTaskItem: Identifiable, Equatable, Sendable {
    let task: KodaiTaskLite
    let projectID: UUID
    let projectTitle: String
    let isOverdue: Bool

    var id: UUID { task.id }
}

struct KodaiProjectLite: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var details: String?
    let createdAt: Date
    var updatedAt: Date
    var deadline: Date?
    var tasks: [KodaiTaskLite]

    var incompleteTasks: [KodaiTaskLite] {
        tasks.filter { !$0.isCompleted }
    }

    var completedTasks: [KodaiTaskLite] {
        tasks.filter { $0.isCompleted }
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deadline: Date? = nil,
        tasks: [KodaiTaskLite] = []
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        tasks = try container.decodeIfPresent([KodaiTaskLite].self, forKey: .tasks) ?? []
    }
}
