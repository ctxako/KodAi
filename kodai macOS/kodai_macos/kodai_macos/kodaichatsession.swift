//
//  kodaichatsession.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/10/26.
//

import Foundation
import SwiftData

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

    @Relationship(deleteRule: .cascade, inverse: \KodaiChatMessage.session)
    var messages: [KodaiChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [KodaiChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}
