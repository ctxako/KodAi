//
//  SystemPromptBuilder.swift
//  kodai-consumer
//
//  Builds the system turn in the format LFM2 was trained on for tool use: a
//  firm instruction to always call exactly one tool (a 1.2B otherwise refuses
//  or narrates), the current datetime/timezone (so relative times can be
//  resolved), and the tools rendered as `List of tools: [<json>]` — mirroring
//  the GGUF chat template's `{%- if tools -%}` branch. The runtime also primes
//  the assistant turn with `<|tool_call_start|>` (see RuntimeAgentModel) so the
//  model continues straight into a native call, which ToolCallParser extracts.
//  No grammar needed: firm prompt + primer ≈ 100% valid calls in measurement.
//

import Foundation
import KodaiKernel

/// Thin seam over `ConsumerToolRouting.systemPrompt` — keeps the injectable
/// now/calendar/timeZone for tests while the prompt text lives in KodaiKernel.
struct SystemPromptBuilder {
    var now: () -> Date = Date.init
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current

    func build() -> String {
        ConsumerToolRouting.systemPrompt(now: now(), calendar: calendar, timeZone: timeZone)
    }
}
