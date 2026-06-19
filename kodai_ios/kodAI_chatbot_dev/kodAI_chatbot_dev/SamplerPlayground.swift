//
//  SamplerPlayground.swift
//  kodAI_chatbot_dev
//
//  Glass-box learning tool. The model emits a probability for every token in
//  its vocabulary; the "sampler" is the set of rules that collapse that list
//  into one chosen token. This file is the pure, inference-free core: it takes
//  a captured next-token distribution and re-derives what each knob (temperature,
//  top-p, top-k, repeat penalty) would do to it — no calls back into llama.cpp.
//

import Foundation
import KodaiKernel

/// A single candidate token entering the sampler, carrying its raw
/// (temperature-1, pre-transform) probability straight from the model.
struct SamplerCandidate: Identifiable {
    let tokenID: Int32
    let text: String
    /// Raw model probability at temperature 1, before any sampler transforms.
    let rawProbability: Float

    var id: Int32 { tokenID }

    init(tokenID: Int32, text: String, rawProbability: Float) {
        self.tokenID = tokenID
        self.text = text
        self.rawProbability = rawProbability
    }

    /// Bridges a captured top-k alternative into a playground candidate.
    init(alternative: TokenAlternative) {
        self.tokenID = alternative.tokenID
        self.text = alternative.text
        self.rawProbability = alternative.probability
    }
}

/// One candidate after the knobs have been applied.
struct ReshapedCandidate: Identifiable {
    let tokenID: Int32
    let text: String
    /// The original probability, kept so the UI can show the before/after delta.
    let rawProbability: Float
    /// Probability after temperature + penalty + truncation, renormalized over
    /// the survivors. Zero when the candidate was cut by top-k or top-p.
    let probability: Float
    /// True when top-k or top-p removed this candidate from contention.
    let isCut: Bool
    /// The token greedy decoding would now pick (the surviving argmax).
    let isWinner: Bool
    /// Marked by the user as "already said," so the repeat penalty applies.
    let isSeen: Bool

    var id: Int32 { tokenID }
}

/// The adjustable sampler settings the playground exposes. Defaults are a
/// no-op baseline (temperature 1, no truncation, no penalty) so the candidates
/// open as the model's true distribution and every knob move is a visible delta.
struct SamplerKnobs: Equatable {
    var temperature: Float = 1.0
    var topP: Float = 1.0
    var topK: Int = 40
    var repeatPenalty: Float = 1.0

    static let `default` = SamplerKnobs()
}

/// Pure, inference-free re-sampling. Turns captured top-k probabilities back
/// into pseudo-logits (softmax is shift-invariant, so `log(p)` stands in for the
/// original logits), then applies the knobs in the same spirit as the live
/// sampler chain — penalty → temperature → top-k → top-p — and renormalizes.
enum SamplerPlayground {
    /// Result of reshaping, plus summary stats for the readout.
    struct Outcome {
        let candidates: [ReshapedCandidate]
        /// How many candidates survived top-k and top-p.
        let survivingCount: Int
        /// Shannon entropy (nats) of the reshaped, renormalized distribution.
        let entropy: Float

        var winner: ReshapedCandidate? { candidates.first { $0.isWinner } }
    }

    /// Temperatures below this collapse toward argmax; floors the divisor.
    static let minTemperature: Float = 0.05

    static func reshape(
        _ candidates: [SamplerCandidate],
        knobs: SamplerKnobs,
        seenTokenIDs: Set<Int32> = []
    ) -> Outcome {
        let n = candidates.count
        guard n > 0 else { return Outcome(candidates: [], survivingCount: 0, entropy: 0) }

        let epsilon: Float = 1e-9
        let temperature = max(knobs.temperature, minTemperature)

        // 1. Recover relative logits, apply the repeat penalty to "seen" tokens
        //    (llama.cpp style: positive logits divide, negative logits multiply),
        //    then scale by temperature.
        var logits = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var logit = Foundation.log(max(candidates[i].rawProbability, epsilon))
            if knobs.repeatPenalty != 1, seenTokenIDs.contains(candidates[i].tokenID) {
                logit = logit > 0 ? logit / knobs.repeatPenalty : logit * knobs.repeatPenalty
            }
            logits[i] = logit / temperature
        }

        // 2. Softmax over the candidate set.
        let maxLogit = logits.max() ?? 0
        let exps = logits.map { Foundation.exp($0 - maxLogit) }
        let expSum = max(exps.reduce(0, +), epsilon)
        let probs = exps.map { $0 / expSum }

        // 3. Rank by probability for truncation.
        let order = (0..<n).sorted { probs[$0] > probs[$1] }

        // top-k: keep the k highest.
        let k = max(1, min(knobs.topK, n))
        var kept = Set(order.prefix(k))

        // top-p (nucleus): within the kept set, keep the smallest prefix whose
        // cumulative probability reaches p.
        var cumulative: Float = 0
        var nucleus = Set<Int>()
        for index in order where kept.contains(index) {
            nucleus.insert(index)
            cumulative += probs[index]
            if cumulative >= knobs.topP { break }
        }
        kept = nucleus

        // 4. Renormalize the survivors and tag the winner.
        let survivorMass = max(kept.reduce(Float(0)) { $0 + probs[$1] }, epsilon)
        let winnerIndex = order.first { kept.contains($0) }

        var entropy: Float = 0
        var reshaped: [ReshapedCandidate] = []
        reshaped.reserveCapacity(n)
        for i in 0..<n {
            let isKept = kept.contains(i)
            let probability = isKept ? probs[i] / survivorMass : 0
            if probability > 0 { entropy -= probability * Foundation.log(probability) }
            reshaped.append(
                ReshapedCandidate(
                    tokenID: candidates[i].tokenID,
                    text: candidates[i].text,
                    rawProbability: candidates[i].rawProbability,
                    probability: probability,
                    isCut: !isKept,
                    isWinner: i == winnerIndex,
                    isSeen: seenTokenIDs.contains(candidates[i].tokenID)
                )
            )
        }

        // Survivors first (by probability), cut candidates after (by raw rank),
        // so the bar list reads top-to-bottom as the sampler "sees" it.
        reshaped.sort {
            if $0.isCut != $1.isCut { return !$0.isCut }
            if $0.probability != $1.probability { return $0.probability > $1.probability }
            return $0.rawProbability > $1.rawProbability
        }

        return Outcome(candidates: reshaped, survivingCount: kept.count, entropy: entropy)
    }
}

// MARK: - Built-in example

extension SamplerPlayground {
    /// The sentence the example distribution is "continuing," shown for context.
    static let exampleContext = "I went to the store to buy some"

    /// A medium-entropy next-token distribution with a believable long tail, so
    /// temperature, top-p, and top-k all produce visible effects. Probabilities
    /// are raw (temperature-1) and intentionally sum below 1 — the missing mass
    /// is the rest of the vocabulary, exactly like a real captured top-k.
    static let exampleCandidates: [SamplerCandidate] = [
        SamplerCandidate(tokenID: 1, text: " groceries", rawProbability: 0.22),
        SamplerCandidate(tokenID: 2, text: " milk", rawProbability: 0.18),
        SamplerCandidate(tokenID: 3, text: " food", rawProbability: 0.14),
        SamplerCandidate(tokenID: 4, text: " bread", rawProbability: 0.11),
        SamplerCandidate(tokenID: 5, text: " snacks", rawProbability: 0.08),
        SamplerCandidate(tokenID: 6, text: " water", rawProbability: 0.06),
        SamplerCandidate(tokenID: 7, text: " coffee", rawProbability: 0.05),
        SamplerCandidate(tokenID: 8, text: " fruit", rawProbability: 0.04),
        SamplerCandidate(tokenID: 9, text: " things", rawProbability: 0.03),
        SamplerCandidate(tokenID: 10, text: " eggs", rawProbability: 0.025),
    ]
}

// MARK: - Knob explanations

/// One "ⓘ" explainer: a plain-language description of what a knob does, shown in
/// a small sheet when the user taps the info button next to it.
struct KnobInfo: Identifiable {
    let id = UUID()
    let title: String
    let body: String

    static let temperature = KnobInfo(
        title: "Temperature",
        body: """
        Flattens or sharpens the whole distribution.

        Low (0.2) makes the model almost always take its favorite — safe but \
        repetitive. High (1.5) gives the long shots a real chance — creative but \
        chaotic. At the floor it's nearly deterministic: always the top token.

        Watch the bars: lower temperature pulls probability toward the leader; \
        higher temperature spreads it out across the field.
        """
    )

    static let topP = KnobInfo(
        title: "Top-P (nucleus)",
        body: """
        Keeps only enough of the top candidates for their probabilities to add \
        up to P, then throws the rest away.

        At 0.9 the model keeps adding tokens from the top until they sum to 90% \
        of the mass — few when it's confident, many when it's unsure. It adapts \
        to the shape of the distribution instead of using a fixed count.

        Drag it down and watch the tail get cut off, then the survivors \
        renormalize to fill the bar.
        """
    )

    static let topK = KnobInfo(
        title: "Top-K",
        body: """
        A blunt cap: only the K most likely tokens stay in the running, \
        everything else is discarded before sampling.

        top-K = 1 is greedy decoding (always the single best token). Larger \
        values let more of the field compete. Unlike top-P this ignores how the \
        probability is shaped — it just counts.
        """
    )

    static let repeatPenalty = KnobInfo(
        title: "Repeat penalty",
        body: """
        Pushes down tokens the model has already used recently, to stop it \
        looping ("the the the").

        It only acts on tokens already in the text, so it does nothing here \
        until you tap a candidate above to mark it as already-said. Then raise \
        the penalty and watch that token's bar shrink, often handing the win to \
        a different word.
        """
    )
}
