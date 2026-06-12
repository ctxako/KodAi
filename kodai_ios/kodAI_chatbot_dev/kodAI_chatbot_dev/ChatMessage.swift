//
//  ChatMessage.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Foundation
import KodaiKernel

struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    let text: String
    let createdAt: Date
    let processSummary: InferenceProcessSummary?
    let exportComment: String?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        processSummary: InferenceProcessSummary? = nil,
        exportComment: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.processSummary = processSummary
        self.exportComment = exportComment
    }
}

struct InferenceProcessSummary: Equatable, Codable, Sendable {
    let finalPhase: InferencePhase
    let generatedTokenCount: Int
    let elapsedSeconds: TimeInterval?
    let modelName: String?
    let failureMessage: String?
    let phasesReached: [InferencePhase]
    let diagnostics: [String]

    enum CodingKeys: String, CodingKey {
        case finalPhase
        case generatedTokenCount
        case elapsedSeconds
        case modelName
        case failureMessage
        case phasesReached
        case diagnostics
    }

    init(
        finalPhase: InferencePhase,
        generatedTokenCount: Int,
        elapsedSeconds: TimeInterval?,
        modelName: String?,
        failureMessage: String?,
        phasesReached: [InferencePhase],
        diagnostics: [String] = []
    ) {
        self.finalPhase = finalPhase
        self.generatedTokenCount = generatedTokenCount
        self.elapsedSeconds = elapsedSeconds
        self.modelName = modelName
        self.failureMessage = failureMessage
        self.phasesReached = phasesReached
        self.diagnostics = diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finalPhase = try container.decode(InferencePhase.self, forKey: .finalPhase)
        generatedTokenCount = try container.decode(Int.self, forKey: .generatedTokenCount)
        elapsedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
        phasesReached = try container.decodeIfPresent([InferencePhase].self, forKey: .phasesReached) ?? []
        diagnostics = try container.decodeIfPresent([String].self, forKey: .diagnostics) ?? []
    }
}
