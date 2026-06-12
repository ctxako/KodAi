//
//  ContextVisibilityModels.swift
//  kodAI_chatbot_dev
//
//  Lightweight in-memory context snapshot for glass-box visibility.
//  Describes what local context surrounded the latest model turn —
//  it does not change the prompt and is not the macOS ContextManifest.
//

import Foundation

struct ContextBlockLite: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String
    let estimatedTokens: Int?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        estimatedTokens: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.estimatedTokens = estimatedTokens
    }
}

struct ContextSnapshotLite: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let reason: String
    let blocks: [ContextBlockLite]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        reason: String,
        blocks: [ContextBlockLite]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.blocks = blocks
    }
}
