import Foundation

public enum InferenceEvent: @unchecked Sendable {
    case phase(InferencePhase)
    case token(String)
    case completed(InferenceResult)
    case cancelled
    case error(any Error)
}
