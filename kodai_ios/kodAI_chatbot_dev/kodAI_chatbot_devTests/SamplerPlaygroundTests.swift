//
//  SamplerPlaygroundTests.swift
//  kodAI_chatbot_devTests
//
//  Verifies the inference-free re-sampling math the playground visualizes.
//

import Foundation
import Testing

@testable import KodAi

struct SamplerPlaygroundTests {
    private let candidates: [SamplerCandidate] = [
        SamplerCandidate(tokenID: 1, text: " a", rawProbability: 0.50),
        SamplerCandidate(tokenID: 2, text: " b", rawProbability: 0.25),
        SamplerCandidate(tokenID: 3, text: " c", rawProbability: 0.15),
        SamplerCandidate(tokenID: 4, text: " d", rawProbability: 0.10),
    ]

    @Test func neutralKnobsRenormalizeWithoutCutting() {
        let outcome = SamplerPlayground.reshape(candidates, knobs: .default)
        #expect(outcome.survivingCount == candidates.count)
        #expect(outcome.candidates.allSatisfy { !$0.isCut })
        let total = outcome.candidates.reduce(Float(0)) { $0 + $1.probability }
        #expect(abs(total - 1) < 0.0001)
        // The leader wins and bars stay in rank order.
        #expect(outcome.winner?.tokenID == 1)
    }

    @Test func lowTemperatureConcentratesOnLeader() {
        var hot = SamplerKnobs.default
        hot.temperature = 1.0
        var cold = SamplerKnobs.default
        cold.temperature = 0.1

        let leaderHot = SamplerPlayground.reshape(candidates, knobs: hot).winner!.probability
        let leaderCold = SamplerPlayground.reshape(candidates, knobs: cold).winner!.probability
        #expect(leaderCold > leaderHot)
        #expect(leaderCold > 0.9)
    }

    @Test func topKKeepsOnlyKCandidates() {
        var knobs = SamplerKnobs.default
        knobs.topK = 2
        let outcome = SamplerPlayground.reshape(candidates, knobs: knobs)
        #expect(outcome.survivingCount == 2)
        #expect(outcome.candidates.filter { !$0.isCut }.count == 2)
        // Survivors renormalize to a full distribution.
        let total = outcome.candidates.reduce(Float(0)) { $0 + $1.probability }
        #expect(abs(total - 1) < 0.0001)
    }

    @Test func topPCutsTheTail() {
        var knobs = SamplerKnobs.default
        knobs.topP = 0.7 // 0.50 + 0.25 = 0.75 ≥ 0.70 → first two survive.
        let outcome = SamplerPlayground.reshape(candidates, knobs: knobs)
        #expect(outcome.survivingCount == 2)
        let survivors = Set(outcome.candidates.filter { !$0.isCut }.map(\.tokenID))
        #expect(survivors == [1, 2])
    }

    @Test func repeatPenaltyOnlyActsOnSeenTokens() {
        var knobs = SamplerKnobs.default
        knobs.repeatPenalty = 1.8

        let unpenalized = SamplerPlayground.reshape(candidates, knobs: knobs)
        #expect(unpenalized.winner?.tokenID == 1) // no token marked seen → no effect

        let penalized = SamplerPlayground.reshape(candidates, knobs: knobs, seenTokenIDs: [1])
        let leaderBefore = unpenalized.candidates.first { $0.tokenID == 1 }!.probability
        let leaderAfter = penalized.candidates.first { $0.tokenID == 1 }!.probability
        #expect(leaderAfter < leaderBefore) // marked token gets pushed down
    }

    @Test func emptyDistributionIsSafe() {
        let outcome = SamplerPlayground.reshape([], knobs: .default)
        #expect(outcome.candidates.isEmpty)
        #expect(outcome.survivingCount == 0)
        #expect(outcome.winner == nil)
    }
}
