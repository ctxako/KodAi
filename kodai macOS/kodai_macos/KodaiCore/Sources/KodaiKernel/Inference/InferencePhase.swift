import Foundation

public enum InferencePhase: String, Codable, Sendable, CaseIterable {
    case idle
    case resolving
    case initializing
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
    case failed
    case cancelled
}
