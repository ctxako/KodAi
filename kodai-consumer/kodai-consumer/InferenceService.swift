//
//  InferenceService.swift
//  kodai-consumer
//
//  Thin wrapper over the shared on-device LFM2 runtime (KodaiRuntime).
//  Phase 0 scope: prove streaming generation. Later phases layer the
//  agentic loop, tool rendering, and result feedback on top of this.
//

import Foundation
import KodaiKernel
import KodaiRuntime

actor InferenceService {
    private let runtime: LocalModelRuntime

    init() {
        runtime = LocalModelRuntime(
            configuration: Self.consumerConfiguration,
            modelFileResolver: ConsumerModelFileResolver()
        )
    }

    /// The kernel default context (2,048) can't hold the ~1,900-token system
    /// prompt plus a multi-step chain — steps would die on promptTooLong.
    /// Tier-sized context keeps the KV cache honest on 4 GB devices.
    static var consumerConfiguration: LocalModelConfiguration {
        let base = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M
        return LocalModelConfiguration(
            modelResourceName: base.modelResourceName,
            modelResourceExtension: base.modelResourceExtension,
            shortDisplayName: base.shortDisplayName,
            contextSize: DeviceTier.current.contextSize,
            maxGeneratedTokens: base.maxGeneratedTokens,
            temperature: base.temperature,
            topP: base.topP,
            topK: base.topK,
            batchSize: base.batchSize,
            repeatPenalty: base.repeatPenalty,
            downloadURL: base.downloadURL
        )
    }

    /// Stream a single completion for the given messages + system prompt.
    func generate(
        messages: [KodaiRuntimeMessage],
        systemPrompt: String,
        samplerKnobs: SamplerKnobs,
        assistantPrimer: String? = nil
    ) async -> AsyncThrowingStream<InferenceEvent, Error> {
        await runtime.generate(
            messages: messages,
            systemPrompt: systemPrompt,
            samplerKnobs: samplerKnobs,
            assistantPrimer: assistantPrimer
        )
    }

    /// Load + warm the model ahead of the first request for a smooth first token.
    func prewarm(onStatus: @Sendable (WarmupStatus) -> Void) async {
        await runtime.prewarm(onStatus: onStatus)
    }

    func cancel() async {
        await runtime.cancel()
    }
}
