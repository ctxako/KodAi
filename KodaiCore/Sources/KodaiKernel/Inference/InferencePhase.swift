import Foundation

public enum InferencePhase: String, Sendable, CaseIterable {
    case resolving
    case initializing
    case tokenizing
    case prefilling
    case decoding
    case completed
    case failed
    case cancelled
}
