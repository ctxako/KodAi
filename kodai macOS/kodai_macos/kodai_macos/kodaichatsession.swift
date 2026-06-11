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

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatMessage.session)
    var messages: [KodaiChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        stream: KodaiStream? = nil,
        project: KodaiProject? = nil,
        messages: [KodaiChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stream = stream
        self.project = project
        self.messages = messages
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

    init(
        id: UUID = UUID(),
        title: String = "New project",
        details: String = "",
        status: ProjectStatus = .active,
        summary: String? = nil,
        summaryUpdatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessions: [KodaiChatSession] = []
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
    }
}
