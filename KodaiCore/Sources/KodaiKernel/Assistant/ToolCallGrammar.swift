//
//  ToolCallGrammar.swift
//  KodaiKernel
//
//  Generates a GBNF grammar from the consumer tool catalog so llama.cpp's
//  grammar sampler can make malformed tool calls unsampleable: invalid JSON,
//  unknown tool names, unknown argument keys, and the hybrid formats a 1.2B
//  drifts into all become impossible rather than parse-time failures.
//
//  The grammar constrains the completion AFTER the `<|tool_call_start|>`
//  primer (which lives in the prompt, not the output). It is the union of the
//  two clean shapes LFM2.5 actually emits — a JSON call array and a Pythonic
//  call — so the model keeps whichever it prefers per turn:
//
//      [{"name":"reminders_create","arguments":{"title":"…"}}]
//      [reminders_create(title="…")]
//
//  Deliberately permissive where the validator is the better judge: argument
//  keys are constrained to the tool's declared set, but required-ness and
//  semantic checks (dates, paths) stay in ToolCallValidator. Forcing key
//  order or presence at the sampler level fights the model's trained
//  emission and derails argument content.
//
//  The Pythonic branch mirrors the argument dialects LFM2.5 actually mixes
//  (all of which ToolCallParser reads): `key="value"` kwargs, JSON-colon
//  keys (`"key": "value"`), a bare positional FIRST string for tools where
//  the parser maps one (`files_create("ideas", …)`), and a full JSON object
//  in the parens. Constraining tighter than the trained emission reroutes
//  probability mass into the wrong tool — an A/B showed files_create
//  flipping to files_create_folder when `("` was masked.
//
//  Pythonic string values are quote-free (no escapes) because the parser's
//  regexes can't read escapes; the JSON forms carry full escaping for
//  content that needs it.
//

import Foundation

public enum ToolCallGrammar {
    /// GBNF for the catalog, or nil if the catalog JSON doesn't decode
    /// (callers fall back to unconstrained sampling).
    public static func gbnf(
        toolDefinitionsJSON: String = ConsumerToolRouting.toolDefinitionsJSON
    ) -> String? {
        guard let data = toolDefinitionsJSON.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !decoded.isEmpty else { return nil }

        var tools: [(name: String, slug: String, keys: [(key: String, type: String)])] = []
        for entry in decoded {
            guard let name = entry["name"] as? String, isRuleSafe(name) else { return nil }
            let properties = ((entry["parameters"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
            // JSONSerialization loses declaration order; sort for determinism.
            // Key order never matters — argument alternatives are unordered.
            let keys: [(String, String)] = properties.keys.sorted().compactMap { key in
                guard isRuleSafe(key) else { return nil }
                let type = (properties[key] as? [String: Any])?["type"] as? String ?? "string"
                return (key, type)
            }
            guard keys.count == properties.count else { return nil }
            tools.append((name, name.replacingOccurrences(of: "_", with: "-"), keys))
        }

        var rules: [String] = [
            "root ::= ws \"[\" ws call ws \"]\" ws end?",
            "end ::= \"<|tool_call_end|>\"",
            "call ::= json-call | py-call",
            "json-call ::= " + tools.map { "jc-\($0.slug)" }.joined(separator: " | "),
            "py-call ::= " + tools.map { "pc-\($0.slug)" }.joined(separator: " | "),
        ]

        for tool in tools {
            let slug = tool.slug
            rules.append(
                "jc-\(slug) ::= \"{\" ws \(quoted("name")) ws \":\" ws \(quoted(tool.name)) ws \",\" ws \(quoted("arguments")) ws \":\" ws jargs-\(slug) ws \"}\""
            )
            if tool.keys.isEmpty {
                rules.append("jargs-\(slug) ::= \"{\" ws \"}\"")
                rules.append(
                    "pc-\(slug) ::= \"\(tool.name)\" ws \"(\" ws \")\" | \"\(tool.name)\" ws \"(\" ws jargs-\(slug) ws \")\""
                )
            } else {
                rules.append(
                    "jargs-\(slug) ::= \"{\" ws \"}\" | \"{\" ws jkv-\(slug) (ws \",\" ws jkv-\(slug))* ws \"}\""
                )
                rules.append(
                    "jkv-\(slug) ::= " + tool.keys
                        .map { "\(quoted($0.key)) ws \":\" ws \(jsonValueRule(for: $0.type))" }
                        .joined(separator: " | ")
                )
                // A bare positional string is only sampleable where the parser
                // maps one to a named parameter.
                let first = ToolCallParser.primaryArgument[tool.name] != nil
                    ? "pfirst-\(slug)" : "pkv-\(slug)"
                rules.append(
                    "pc-\(slug) ::= \"\(tool.name)\" ws \"(\" ws \")\" | \"\(tool.name)\" ws \"(\" ws jargs-\(slug) ws \")\" | \"\(tool.name)\" ws \"(\" ws \(first) (ws \",\" ws pkv-\(slug))* ws \")\""
                )
                if ToolCallParser.primaryArgument[tool.name] != nil {
                    rules.append("pfirst-\(slug) ::= pkv-\(slug) | pstring")
                }
                rules.append(
                    "pkv-\(slug) ::= " + tool.keys
                        .map { "\"\($0.key)\" ws \"=\" ws pstring | \(quoted($0.key)) ws \":\" ws pstring" }
                        .joined(separator: " | ")
                )
            }
        }

        rules.append(contentsOf: [
            // Mirrors llama.cpp's own json.gbnf string rule.
            "jstring ::= \"\\\"\" jchar* \"\\\"\"",
            "jchar ::= [^\"\\\\\\x7F\\x00-\\x1F] | \"\\\\\" ([\"\\\\bfnrt] | \"u\" hex hex hex hex)",
            "hex ::= [0-9a-fA-F]",
            "jbool ::= \"true\" | \"false\" | \(quoted("true")) | \(quoted("false"))",
            "pstring ::= \"\\\"\" [^\"]* \"\\\"\"",
            "ws ::= [ \\t\\n]*",
        ])

        return rules.joined(separator: "\n") + "\n"
    }

    private static func jsonValueRule(for type: String) -> String {
        type == "boolean" ? "jbool" : "jstring"
    }

    /// GBNF literal for a JSON-quoted string: `name` → "\"name\"".
    private static func quoted(_ text: String) -> String {
        "\"\\\"\(text)\\\"\""
    }

    /// Tool and key names are embedded in rule text verbatim; anything outside
    /// this set would need escaping, and nothing in the catalog does.
    private static func isRuleSafe(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLowercase && $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
