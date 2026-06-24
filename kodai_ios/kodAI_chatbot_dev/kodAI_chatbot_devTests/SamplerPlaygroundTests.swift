//
//  SamplerPlaygroundTests.swift
//  kodAI_chatbot_devTests
//
//  Verifies the live tuning defaults and their bridge to the model config.
//  (The old inference-free reshape visualization was removed; the knobs now
//  feed the real sampler chain in LlamaContextWrapper.)
//

import Foundation
import KodaiKernel
import Testing

@testable import KodAi

struct SamplerKnobsTests {
    private let config = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M

    @Test func defaultMirrorsModelConfig() {
        let knobs = SamplerKnobs.default
        #expect(knobs.temperature == config.temperature)
        #expect(knobs.topP == config.topP)
        #expect(knobs.topK == Int(config.topK))
        #expect(knobs.repeatPenalty == config.repeatPenalty)
        #expect(knobs.maxOutputTokens == Int(config.maxGeneratedTokens))
    }

    @Test func defaultDisablesAdvancedSamplers() {
        let knobs = SamplerKnobs.default
        // Advanced knobs ship off so a fresh chat behaves like the shipped tuning.
        #expect(knobs.minP == 0)
        #expect(knobs.frequencyPenalty == 0)
        #expect(knobs.presencePenalty == 0)
        #expect(knobs.deterministic == false)
        #expect(knobs.seed == nil)
    }

    @Test func minTemperatureFloorsAboveZero() {
        // The temperature slider's lower bound must never reach 0 (avoids a
        // divide-by-zero in the live temperature sampler).
        #expect(SamplerKnobs.minTemperature > 0)
    }
}
