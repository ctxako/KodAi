import Foundation

public struct InferenceResult: Sendable {
    public let fullText: String
    public let promptTokensEst: Int
    public let outputTokensEst: Int
    public let duration: TimeInterval
    public let tokensPerSecond: Double?

    public init(
        fullText: String,
        promptTokensEst: Int,
        outputTokensEst: Int,
        duration: TimeInterval,
        tokensPerSecond: Double?
    ) {
        self.fullText = fullText
        self.promptTokensEst = promptTokensEst
        self.outputTokensEst = outputTokensEst
        self.duration = duration
        self.tokensPerSecond = tokensPerSecond
    }
}
