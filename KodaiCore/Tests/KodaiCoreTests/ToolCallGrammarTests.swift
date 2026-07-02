import Foundation
import Testing
@testable import KodaiKernel

@Suite("ToolCallGrammar")
struct ToolCallGrammarTests {
    @Test func generatesFromShippedCatalog() throws {
        let gbnf = try #require(ToolCallGrammar.gbnf())
        // One JSON rule and one Pythonic rule per catalog tool (20 + respond).
        for name in AssistantToolName.allCases.map(\.rawValue) + ["respond"] {
            let slug = name.replacingOccurrences(of: "_", with: "-")
            #expect(gbnf.contains("jc-\(slug) ::="), "missing JSON rule for \(name)")
            #expect(gbnf.contains("pc-\(slug) ::="), "missing Pythonic rule for \(name)")
        }
        #expect(gbnf.contains("root ::="))
    }

    @Test func grammarIsDeterministic() {
        #expect(ToolCallGrammar.gbnf() == ToolCallGrammar.gbnf())
    }

    @Test func everyRuleReferenceResolves() throws {
        let gbnf = try #require(ToolCallGrammar.gbnf())
        var defined = Set<String>()
        var referenced = Set<String>()
        for line in gbnf.split(separator: "\n") {
            let parts = line.components(separatedBy: " ::= ")
            guard parts.count == 2 else { continue }
            defined.insert(parts[0])
            // Scan the body, skipping string literals and char classes
            // (either may contain the other's delimiter), collecting bare
            // rule-name references.
            var name = ""
            var delimiter: Character? = nil   // active " or [ span
            var escaped = false
            for char in parts[1] {
                if let active = delimiter {
                    if escaped { escaped = false; continue }
                    if char == "\\" { escaped = true; continue }
                    if (active == "\"" && char == "\"") || (active == "[" && char == "]") {
                        delimiter = nil
                    }
                    continue
                }
                if char == "\"" || char == "[" {
                    delimiter = char
                } else if char.isLetter || char.isNumber || char == "-" {
                    name.append(char)
                    continue
                }
                if !name.isEmpty { referenced.insert(name); name = "" }
            }
            if !name.isEmpty { referenced.insert(name) }
        }
        #expect(defined.contains("root"))
        let unresolved = referenced.subtracting(defined)
        #expect(unresolved.isEmpty, "referenced but undefined: \(unresolved.sorted())")
        let unused = defined.subtracting(referenced).subtracting(["root"])
        #expect(unused.isEmpty, "defined but never referenced: \(unused.sorted())")
    }

    @Test func goldenShapeForSingleTool() throws {
        let catalog = """
        [{"name":"clipboard_write","description":"d","parameters":{"type":"object",\
        "properties":{"content":{"type":"string"}},"required":["content"]}}]
        """
        let gbnf = try #require(ToolCallGrammar.gbnf(toolDefinitionsJSON: catalog))
        let expected = """
        root ::= ws "[" ws call ws "]" ws end?
        end ::= "<|tool_call_end|>"
        call ::= json-call | py-call
        json-call ::= jc-clipboard-write
        py-call ::= pc-clipboard-write
        jc-clipboard-write ::= "{" ws "\\"name\\"" ws ":" ws "\\"clipboard_write\\"" ws "," ws "\\"arguments\\"" ws ":" ws jargs-clipboard-write ws "}"
        jargs-clipboard-write ::= "{" ws "}" | "{" ws jkv-clipboard-write (ws "," ws jkv-clipboard-write)* ws "}"
        jkv-clipboard-write ::= "\\"content\\"" ws ":" ws jstring
        pc-clipboard-write ::= "clipboard_write" ws "(" ws ")" | "clipboard_write" ws "(" ws jargs-clipboard-write ws ")" | "clipboard_write" ws "(" ws pfirst-clipboard-write (ws "," ws pkv-clipboard-write)* ws ")"
        pfirst-clipboard-write ::= pkv-clipboard-write | pstring
        pkv-clipboard-write ::= "content" ws "=" ws pstring | "\\"content\\"" ws ":" ws pstring
        jstring ::= "\\"" jchar* "\\""
        jchar ::= [^"\\\\\\x7F\\x00-\\x1F] | "\\\\" (["\\\\bfnrt] | "u" hex hex hex hex)
        hex ::= [0-9a-fA-F]
        jbool ::= "true" | "false" | "\\"true\\"" | "\\"false\\""
        pstring ::= "\\"" [^"]* "\\""
        ws ::= [ \\t\\n]*

        """
        #expect(gbnf == expected)
    }

    @Test func booleanTypedKeysUseBoolRule() throws {
        let gbnf = try #require(ToolCallGrammar.gbnf())
        #expect(gbnf.contains(#""\"all_day\"" ws ":" ws jbool"#))
        #expect(gbnf.contains(#""\"completed\"" ws ":" ws jbool"#))
    }

    @Test func zeroParameterToolHasClosedForms() throws {
        let gbnf = try #require(ToolCallGrammar.gbnf())
        #expect(gbnf.contains(#"jargs-clipboard-read ::= "{" ws "}""#))
        #expect(gbnf.contains(#"pc-clipboard-read ::= "clipboard_read" ws "(" ws ")""#))
    }

    @Test func undecodableCatalogReturnsNil() {
        #expect(ToolCallGrammar.gbnf(toolDefinitionsJSON: "not json") == nil)
        #expect(ToolCallGrammar.gbnf(toolDefinitionsJSON: "[]") == nil)
    }

    /// Canonical emissions of both shapes must be inside the language the
    /// grammar describes AND round-trip through the shipped parser+validator.
    /// (A tiny recursive-descent GBNF matcher would be overkill; instead this
    /// asserts the parser accepts what the grammar is designed to force.)
    @Test func canonicalEmissionsParseAndValidate() {
        let parser = ToolCallParser()
        let validator = ToolCallValidator()
        let emissions = [
            #"[{"name":"reminders_create","arguments":{"title":"call mom","due_date":"2027-01-01T09:00"}}]"#,
            #"[reminders_create(title="call mom", due_date="2027-01-01T09:00")]"#,
            #"[{"name":"respond","arguments":{"message":"Hi!"}}]"#,
            #"[respond(message="Hi!")]"#,
            #"[{"name":"clipboard_read","arguments":{}}]"#,
            // Real LFM2.5 dialects the grammar must keep sampleable: bare
            // positional first arg, JSON-colon keys, JSON object in parens.
            #"[files_create("ideas", "content": "My startup thoughts")]"#,
            #"[files_create("shopping.txt", content="buy milk, eggs, bread")]"#,
            #"[reminders_create({"title": "call mom", "due_date": "2027-01-01T09:00"})]"#,
        ]
        // The grammar's jbool rule emits bare JSON booleans — they must
        // survive stringification as "true"/"false" (CFBoolean stringValue is
        // "1"/"0", which the validator reads as false).
        let boolEmission = #"[{"name":"calendar_create_event","arguments":{"title":"trip","start_date":"2027-01-01T09:00","all_day":true}}]"#
        if let (raw, _) = parser.parse(boolEmission),
           case let .success(call) = validator.validate(raw),
           case let .calendarCreateEvent(_, _, _, _, _, _, allDay) = call {
            #expect(allDay == true)
        } else {
            Issue.record("boolean emission failed to parse/validate")
        }
        for emission in emissions {
            let parsed = parser.parse(emission)
            #expect(parsed != nil, "parser rejected canonical emission: \(emission)")
            guard let (raw, _) = parsed else { continue }
            if raw.name != "respond" {
                let result = validator.validate(raw)
                guard case .success = result else {
                    Issue.record("validator rejected \(emission): \(result)")
                    continue
                }
            }
        }
    }
}
