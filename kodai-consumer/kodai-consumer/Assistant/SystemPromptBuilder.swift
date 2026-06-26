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

struct SystemPromptBuilder {
    var now: () -> Date = Date.init
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current

    func build() -> String {
        let stamp = format(now(), "EEEE, yyyy-MM-dd HH:mm")

        return """
        You are kodAI, an on-device assistant. Complete the user's request by calling exactly one tool from the list below. You ALWAYS call a tool — never refuse, never apologize, never reply in prose, and never say what you "can only" do. Every request maps to one tool here; create_reminder handles reminders and to-dos with an optional due date.
        Current date and time: \(stamp) (\(timeZone.identifier)).
        Resolve relative times ("tonight", "tomorrow", "6pm", "in 2 hours") to absolute ISO 8601 (YYYY-MM-DDTHH:MM) using the current time above.
        List of tools: \(AssistantToolCatalog.toolDefinitionsJSON)
        """
    }

    // MARK: - Helpers

    private func format(_ date: Date, _ pattern: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = calendar
        df.timeZone = timeZone
        df.dateFormat = pattern
        return df.string(from: date)
    }
}
