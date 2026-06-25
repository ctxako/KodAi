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
        runtime = LocalModelRuntime(modelFileResolver: ConsumerModelFileResolver())
    }

    /// Stream a single completion for the given messages + system prompt.
    func generate(
        messages: [KodaiRuntimeMessage],
        systemPrompt: String,
        samplerKnobs: SamplerKnobs
    ) async -> AsyncThrowingStream<InferenceEvent, Error> {
        await runtime.generate(
            messages: messages,
            systemPrompt: systemPrompt,
            samplerKnobs: samplerKnobs
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
