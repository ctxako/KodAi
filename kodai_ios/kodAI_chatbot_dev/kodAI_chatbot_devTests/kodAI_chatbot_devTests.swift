//
//  kodAI_chatbot_devTests.swift
//  kodAI_chatbot_devTests
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import KodaiKernel
import Testing
@testable import KodAi

struct kodAI_chatbot_devTests {

    @Test func example() async throws {
    }

    @Test func tokenSnapshotKeepsDecisionPiecePairedWithItsDistribution() {
        let alternatives = [
            TokenAlternative(tokenID: 11, text: " skills", probability: 0.82, isSelected: true),
            TokenAlternative(tokenID: 12, text: " abilities", probability: 0.13, isSelected: false),
        ]
        let decision = TokenDecision(
            step: 7,
            tokenID: 11,
            text: " skills",
            distribution: TokenDistribution(
                alternatives: alternatives,
                selectedProbability: 0.82,
                entropy: 0.70,
                margin: 0.69
            )
        )

        var snapshot = TokenSnapshot(decision: decision)
        snapshot.appendVisibleText("visible output")

        #expect(snapshot.step == 7)
        #expect(snapshot.text == " skills")
        #expect(snapshot.visibleText == "visible output")
        #expect(snapshot.alternatives.first(where: \.isSelected)?.text == snapshot.text)
        #expect(snapshot.selectedProbability == 0.82)
    }

    @Test func tokenSnapshotReportsDifferenceFromRawArgmaxWithoutAssumingCause() {
        let snapshot = TokenSnapshot(
            decision: TokenDecision(
                step: 0,
                tokenID: 12,
                text: " emitted",
                distribution: TokenDistribution(
                    alternatives: [
                        TokenAlternative(tokenID: 11, text: " raw", probability: 0.62, isSelected: false),
                        TokenAlternative(tokenID: 12, text: " emitted", probability: 0.24, isSelected: true),
                    ],
                    selectedProbability: 0.24,
                    entropy: 1.1,
                    margin: 0.38
                )
            )
        )

        #expect(snapshot.differsFromRawArgmax)
        #expect(snapshot.rawArgmaxAlternative?.text == " raw")
    }

    @Test func globeContinentLabelsContextSizingAsAnEstimate() {
        let user = ChatMessage(role: .user, text: "12345678")
        let assistant = ChatMessage(role: .assistant, text: "response")
        let first = TokenSnapshot(
            decision: TokenDecision(
                step: 0,
                tokenID: 11,
                text: " one",
                distribution: TokenDistribution(
                    alternatives: [
                        TokenAlternative(tokenID: 11, text: " one", probability: 0.8, isSelected: true),
                        TokenAlternative(tokenID: 12, text: " two", probability: 0.1, isSelected: false),
                    ],
                    selectedProbability: 0.8,
                    entropy: 0.7,
                    margin: 0.7
                )
            )
        )
        let second = TokenSnapshot(
            decision: TokenDecision(
                step: 1,
                tokenID: 22,
                text: " selected",
                distribution: TokenDistribution(
                    alternatives: [
                        TokenAlternative(tokenID: 21, text: " raw", probability: 0.5, isSelected: false),
                        TokenAlternative(tokenID: 22, text: " selected", probability: 0.3, isSelected: true),
                    ],
                    selectedProbability: 0.3,
                    entropy: 1.2,
                    margin: 0.2
                )
            )
        )

        let continents = GlobeContinent.build(
            messages: [user, assistant],
            histories: [assistant.id: [first, second]],
            contextSize: 100
        )

        #expect(continents.count == 1)
        #expect(abs(continents[0].estimatedContextShare - 0.04) < 0.0001)
        #expect(abs(continents[0].avgRawProbability - 0.55) < 0.0001)
        #expect(continents[0].rawArgmaxDifferenceCount == 1)
    }

}
