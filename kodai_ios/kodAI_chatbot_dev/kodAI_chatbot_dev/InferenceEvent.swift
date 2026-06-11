//
//  InferenceEvent.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Foundation

enum InferenceEvent: Equatable, Sendable {
    case phase(InferencePhase)
    case warmup(WarmupStatus)
    case diagnostic(String)
    case token(String, generatedTokenCount: Int)
    case done(LlamaGenerationFinishReason)
    case cancelled
}

enum WarmupStatus: String, Equatable, Sendable {
    case initializingRuntime
    case allocatingContext
    case mappingWeights
    case compilingMetal
    case warmingTokenizer
    case ready
}
