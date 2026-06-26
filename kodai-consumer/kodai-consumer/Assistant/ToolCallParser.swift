//
//  ToolCallParser.swift
//  kodai-consumer
//
//  Extracts a tool call from raw model output. Robust to three shapes,
//  because llama.cpp's detokenizer may or may not surface LFM2's special
//  tool tokens as literal text:
//    1. wrapped:  <|tool_call_start|>[ {"name":…,"arguments":{…}} ]<|tool_call_end|>
//    2. bare:     [ {"name":…,"arguments":{…}} ]   (special tokens suppressed)
//    3. Pythonic: create_reminder(title="x", due_iso="…")  (fallback)
//

import Foundation

/// How much to trust the extracted call — drives whether the confirm card nudges
/// the user to double-check. `.native`: a clean tool-call emission (the native
/// `<|tool_call_*|>` wrapper, or a standalone call that is essentially the whole
/// output — the normal primed case). `.json`: structured JSON. `.pythonic`: a
/// call recovered loosely from surrounding prose, worth a second look.
enum ParseConfidence: Sendable {
    case native
    case json
    case pythonic
}

struct ToolCallParser {
    private let startToken = "<|tool_call_start|>"
    private let endToken = "<|tool_call_end|>"

    func parse(_ output: String) -> (RawToolCall, ParseConfidence)? {
        let wrapped = extractWrappedPayload(from: output)
        if let payload = wrapped, let call = parseJSON(in: payload) {
            return (call, .native)
        }
        if let call = parseJSON(in: output) { return (call, .json) }
        if let (call, isStandalone) = parsePythonic(in: output) {
            // A call that *is* essentially the whole output (the normal primed
            // emission) is trusted; one fished out of prose gets a verify hint.
            return (call, isStandalone ? .native : .pythonic)
        }
        return nil
    }

    // MARK: - Wrapper extraction

    private func extractWrappedPayload(from text: String) -> String? {
        guard let start = text.range(of: startToken) else { return nil }
        let afterStart = text[start.upperBound...]
        if let end = afterStart.range(of: endToken) {
            return String(afterStart[..<end.lowerBound])
        }
        return String(afterStart)
    }

    // MARK: - JSON

    private func parseJSON(in text: String) -> RawToolCall? {
        for (open, close) in [("[", "]"), ("{", "}")] {
            guard let lo = text.firstIndex(of: Character(open)),
                  let hi = text.lastIndex(of: Character(close)), lo < hi else { continue }
            let slice = String(text[lo...hi])
            guard let data = slice.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }

            let dict: [String: Any]?
            if let array = object as? [[String: Any]] {
                dict = array.first
            } else if let single = object as? [String: Any] {
                dict = single
            } else {
                dict = nil
            }
            if let dict, let call = rawCall(from: dict) { return call }
        }
        return nil
    }

    private func rawCall(from dict: [String: Any]) -> RawToolCall? {
        guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
        let argsAny = (dict["arguments"] as? [String: Any]) ?? [:]
        var arguments: [String: String] = [:]
        for (key, value) in argsAny {
            arguments[key] = stringify(value)
        }
        return RawToolCall(name: name, arguments: arguments)
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return String(describing: value)
        }
    }

    // MARK: - Pythonic fallback

    /// Returns the call plus whether it stands alone — i.e. the call is the whole
    /// output once wrapper tokens, enclosing brackets, and whitespace are removed.
    /// Standalone calls are the normal primed emission; non-standalone ones were
    /// recovered from surrounding prose and warrant a verify hint.
    private func parsePythonic(in text: String) -> (RawToolCall, isStandalone: Bool)? {
        guard let call = firstMatch(#"([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*)\)"#, in: text),
              call.count == 2 else { return nil }
        let name = call[0]
        let argString = call[1]
        guard name == AssistantToolCatalog.respondToolName
            || AssistantToolName(rawValue: name) != nil else { return nil }

        var arguments: [String: String] = [:]
        for pair in allMatches(#"([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*\"([^\"]*)\""#, in: argString) where pair.count == 2 {
            arguments[pair[0]] = pair[1]
        }

        let cleaned = text.strippingModelTokens()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] \n\t"))
        let afterName = cleaned.hasPrefix(name)
            ? cleaned.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            : ""
        return (RawToolCall(name: name, arguments: arguments), afterName.hasPrefix("("))
    }

    // MARK: - Regex helpers

    private func firstMatch(_ pattern: String, in text: String) -> [String]? {
        allMatches(pattern, in: text).first
    }

    /// Returns, for each match, the captured groups (group 1, 2, …) as strings.
    private func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}
