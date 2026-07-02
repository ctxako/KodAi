//
//  RuntimeAgentModel.swift
//  kodai-consumer
//
//  Runs one model turn by streaming a completion. Reliable tool-calling is
//  layered: LFM2's native trained format (see SystemPromptBuilder), a fixed
//  low-temperature tool-turn profile, and a GBNF grammar over the tool catalog
//  that makes malformed calls unsampleable. Surfaces high-level state and the
//  live token stream for the UI, and exposes cancel() so a stuck turn can be
//  torn down.
//

import Foundation
import KodaiKernel

/// High-level model state surfaced to the UI.
enum ModelStatus: Equatable {
    case downloading
    case loading(String)
    case thinking
}

final class RuntimeAgentModel: AgentModel {
    /// Primed into the assistant turn to force a native LFM2 tool call (the
    /// canonical value lives in KodaiKernel's ConsumerToolRouting). Without it the
    /// 1.2B refuses/narrates on most requests; priming `<|tool_call_start|>` puts
    /// the model *inside* a call so it emits `[tool(args)]`. ~40% → ~100% valid.
    static let toolCallPrimer = ConsumerToolRouting.toolCallPrimer

    /// GBNF over the tool catalog — built once; nil (unconstrained) only if
    /// the catalog fails to decode, which the grammar tests make structural.
    static let toolCallGrammar = ToolCallGrammar.gbnf()

    let inference = InferenceService()

    var onStatus: ((ModelStatus) -> Void)?
    var onToken: ((String) -> Void)?

    func complete(systemPrompt: String, messages: [AgentMessage]) async throws -> String {
        let runtimeMessages: [KodaiRuntimeMessage] = messages.map { message in
            switch message.role {
            case .user:
                return KodaiRuntimeMessage(role: .user, text: message.text)
            case .assistant:
                return KodaiRuntimeMessage(role: .assistant, text: message.text)
            case .tool:
                return KodaiRuntimeMessage(role: .user, text: "[TOOL RESULT] " + message.text)
            }
        }

        // Fixed tool-turn profile: low temperature for near-deterministic
        // routing, a short cap because one tool call is all we want per turn.
        var knobs = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.defaultSamplerKnobs
        knobs.temperature = 0.3
        knobs.maxOutputTokens = 200
        knobs.grammar = Self.toolCallGrammar

        let stream = await inference.generate(
            messages: runtimeMessages,
            systemPrompt: systemPrompt,
            samplerKnobs: knobs,
            assistantPrimer: Self.toolCallPrimer
        )

        var output = ""
        var startedThinking = false
        for try await event in stream {
            switch event {
            case let .token(chunk, _):
                if !startedThinking {
                    startedThinking = true
                    onStatus?(.thinking)
                }
                output += chunk
                onToken?(chunk)
            case let .warmup(status):
                onStatus?(.loading(status.rawValue))
            case .phase(.downloadingModel):
                onStatus?(.downloading)
            case .phase(.loadingModel):
                onStatus?(.loading("loadingModel"))
            default:
                break
            }
        }
        return output
    }

    /// Tear down an in-flight generation (used by the watchdog timeout).
    func cancel() async {
        await inference.cancel()
    }
}
