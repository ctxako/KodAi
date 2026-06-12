//
//  ContextVisibilityModels.swift
//  kodAI_chatbot_dev
//
//  Lightweight in-memory context snapshot for glass-box visibility.
//  Describes what local context surrounded the latest model turn —
//  it does not change the prompt. Blocks are shared KodaiKernel
//  ContextBlock values; this wrapper only adds UI-side identity,
//  timestamp, and reason.
//

import Foundation
import KodaiKernel

struct ContextSnapshotLite: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let reason: String
    let blocks: [ContextBlock]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        reason: String,
        blocks: [ContextBlock]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.blocks = blocks
    }
}
