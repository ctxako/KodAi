import Foundation

public enum InferenceEvent: @unchecked Sendable {
    case phase(InferencePhase)
    case warmup(WarmupStatus)
    case diagnostic(String)
    case token(String, generatedTokenCount: Int)
    case completed(InferenceResult)
    case done(GenerationFinishReason)
    case cancelled
    case error(any Error)
}
