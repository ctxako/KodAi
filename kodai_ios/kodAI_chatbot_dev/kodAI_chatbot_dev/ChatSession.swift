//
//  ChatSession.swift
//  kodAI_chatbot_dev
//
//  Created by Codex on 6/7/26.
//

import Foundation

struct ChatSession: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var isPinned: Bool
    var streamID: UUID?
    var summary: String?
    var assistantMode: AssistantMode

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        isPinned: Bool = false,
        streamID: UUID? = nil,
        summary: String? = nil,
        assistantMode: AssistantMode = .default
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
        self.streamID = streamID
        self.summary = summary
        self.assistantMode = assistantMode
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case messages
        case isPinned
        case streamID
        case summary
        case assistantMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        streamID = try container.decodeIfPresent(UUID.self, forKey: .streamID)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        assistantMode = try container.decodeIfPresent(AssistantMode.self, forKey: .assistantMode) ?? .default
    }
}

struct Stream: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var chatIDs: [ChatSession.ID]
    var isFavorite: Bool
    var summary: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        chatIDs: [ChatSession.ID] = [],
        isFavorite: Bool = false,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chatIDs = chatIDs
        self.isFavorite = isFavorite
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case chatIDs
        case isFavorite
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        chatIDs = try container.decode([ChatSession.ID].self, forKey: .chatIDs)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }
}
