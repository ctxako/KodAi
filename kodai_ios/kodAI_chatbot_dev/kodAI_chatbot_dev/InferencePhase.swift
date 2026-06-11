//
//  InferencePhase.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Foundation

enum InferencePhase: String, Codable, Equatable, Sendable {
    case idle
    case checkingRuntimeState
    case checkingLocalTime
    case checkingWeather
    case usingCachedWeather
    case downloadingModel
    case loadingModel
    case formattingPrompt
    case tokenizing
    case prefilling
    case decoding
    case flushingOutput
    case completed
    case cancelled
    case failed
}
