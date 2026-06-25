//
//  SystemPromptBuilder.swift
//  kodai-consumer
//
//  Builds the system turn in the format LFM2 was trained on for tool use: a
//  terse instruction, the current datetime/timezone (so relative times can be
//  resolved), and the tools rendered as `List of tools: [<json>]` — mirroring
//  the GGUF chat template's `{%- if tools -%}` branch. LFM2 then emits a native
//  <|tool_call_start|>…<|tool_call_end|> call, which ToolCallParser extracts.
//  No grammar, no "emit JSON" rules, no plain-text escape.
//

import Foundation

struct SystemPromptBuilder {
    var now: () -> Date = Date.init
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current

    func build() -> String {
        let stamp = format(now(), "EEEE, yyyy-MM-dd HH:mm")

        return """
        You are kodAI, an on-device assistant that completes one device action per request by calling the single most appropriate tool with correct arguments.
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
