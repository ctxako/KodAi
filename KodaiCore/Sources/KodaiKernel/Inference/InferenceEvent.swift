import Foundation

public struct TokenAlternative: Sendable {
    public let tokenID: Int32
    public let text: String
    public let probability: Float
    public let isSelected: Bool

    public init(tokenID: Int32, text: String, probability: Float, isSelected: Bool) {
        self.tokenID = tokenID
        self.text = text
        self.probability = probability
        self.isSelected = isSelected
    }
}

/// The model's next-token distribution at one decode step, captured for
/// interpretation. `alternatives` is the top-k; the scalar stats are computed
/// over the full vocabulary at the logit source. Probabilities are the raw
/// model distribution (temperature 1, before the sampler's transforms).
public struct TokenDistribution: Sendable {
    public let alternatives: [TokenAlternative]
    /// True probability of the actually-sampled token, even if it falls
    /// outside the top-k (so it is never mis-reported as fully confident).
    public let selectedProbability: Float
    /// Shannon entropy of the full-vocab distribution, in nats.
    public let entropy: Float
    /// Gap between the top-1 and top-2 probabilities (decision decisiveness).
    public let margin: Float

    public init(
        alternatives: [TokenAlternative],
        selectedProbability: Float,
        entropy: Float,
        margin: Float
    ) {
        self.alternatives = alternatives
        self.selectedProbability = selectedProbability
        self.entropy = entropy
        self.margin = margin
    }

    public static let empty = TokenDistribution(
        alternatives: [],
        selectedProbability: 0,
        entropy: 0,
        margin: 0
    )
}

/// One sampled-token decision captured before UTF-8 assembly and textual stop
/// filtering. Keeping this separate from visible text deltas prevents delayed
/// output from being paired with the wrong next-token distribution.
public struct TokenDecision: Sendable {
    public let step: Int
    public let tokenID: Int32
    public let text: String
    public let distribution: TokenDistribution

    public init(step: Int, tokenID: Int32, text: String, distribution: TokenDistribution) {
        self.step = step
        self.tokenID = tokenID
        self.text = text
        self.distribution = distribution
    }
}

public enum InferenceEvent: @unchecked Sendable {
    case phase(InferencePhase)
    case warmup(WarmupStatus)
    case diagnostic(String)
    case token(String, generatedTokenCount: Int)
    case tokenDecision(TokenDecision)
    /// A tool call's lifecycle progress while an agentic turn runs.
    case toolActivity(ToolActivity)
    case completed(InferenceResult)
    case done(GenerationFinishReason)
    case cancelled
    case error(any Error)
}
