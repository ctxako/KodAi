//
//  kodaichatsession.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//

import Foundation
import SwiftData
import KodaiCore

@Model
final class KodaiChatMessage {
    var id: UUID
    var role: String
    var content: String
    var createdAt: Date
    var session: KodaiChatSession?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.session = session
    }
}

@Model
final class KodaiChatSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var stream: KodaiStream?
    var project: KodaiProject?
    var summarizedThroughMessageID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatMessage.session)
    var messages: [KodaiChatMessage]

    @Relationship(deleteRule: .cascade, inverse: \KodaiSummary.session)
    var summaries: [KodaiSummary]

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        stream: KodaiStream? = nil,
        project: KodaiProject? = nil,
        messages: [KodaiChatMessage] = [],
        summarizedThroughMessageID: UUID? = nil,
        summaries: [KodaiSummary] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stream = stream
        self.project = project
        self.messages = messages
        self.summarizedThroughMessageID = summarizedThroughMessageID
        self.summaries = summaries
    }
}

@Model
final class KodaiStream {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \KodaiChatSession.stream)
    var sessions: [KodaiChatSession]

    init(
        id: UUID = UUID(),
        title: String = "New stream",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [KodaiChatSession] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = sessions
    }
}

@Model
final class KodaiProject {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var status: ProjectStatus
    var summary: String?
    var summaryUpdatedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatSession.project)
    var sessions: [KodaiChatSession]

    @Relationship(deleteRule: .cascade, inverse: \KodaiTask.project)
    var tasks: [KodaiTask]

    init(
        id: UUID = UUID(),
        title: String = "New project",
        details: String = "",
        status: ProjectStatus = .active,
        summary: String? = nil,
        summaryUpdatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [KodaiChatSession] = [],
        tasks: [KodaiTask] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.summary = summary
        self.summaryUpdatedAt = summaryUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = sessions
        self.tasks = tasks
    }
}

@Model
final class KodaiTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var priority: TaskPriority
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var project: KodaiProject?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
    }
}

@Model
final class KodaiSummary {
    @Attribute(.unique) var id: UUID
    var kind: SummaryKind
    var content: String
    var previousContent: String?
    var tokenCount: Int
    var createdAt: Date
    var session: KodaiChatSession?
    var project: KodaiProject?

    init(
        id: UUID = UUID(),
        kind: SummaryKind,
        content: String,
        previousContent: String? = nil,
        createdAt: Date = .now,
        session: KodaiChatSession? = nil,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.previousContent = previousContent
        self.tokenCount = max(1, Int(ceil(Double(content.count) / 4.0)))
        self.createdAt = createdAt
        self.session = session
        self.project = project
    }
}
