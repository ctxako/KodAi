//
//  DisplayText.swift
//  kodai-consumer
//
//  Display-only cleanup. LFM2 renders its special tokens (e.g.
//  <|tool_call_start|>) as literal text, which we don't want to show the user.
//  The parser still operates on the raw model output — this only affects UI.
//

import Foundation

extension String {
    func strippingModelTokens() -> String {
        replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
