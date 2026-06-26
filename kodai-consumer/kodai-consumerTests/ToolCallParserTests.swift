import Testing
import Foundation
@testable import kodai_consumer

struct ToolCallParserTests {
    private let parser = ToolCallParser()

    @Test func parsesWrappedJSONArray() {
        let out = #"<|tool_call_start|>[{"name": "create_reminder", "arguments": {"title": "Call mom", "due_iso": "2026-06-26T18:00"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "create_reminder")
        #expect(result?.0.arguments["title"] == "Call mom")
        #expect(result?.0.arguments["due_iso"] == "2026-06-26T18:00")
        #expect(result?.1 == .native)
    }

    @Test func parsesBareJSONArrayWithSurroundingText() {
        let out = #"Sure thing. [{"name":"add_to_list","arguments":{"list":"Groceries","item":"Milk"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "add_to_list")
        #expect(result?.0.arguments["list"] == "Groceries")
        #expect(result?.0.arguments["item"] == "Milk")
        #expect(result?.1 == .json)
    }

    @Test func parsesSingleObjectForm() {
        let out = #"{"name":"create_calendar_event","arguments":{"title":"Sync","start_iso":"2026-06-26T14:00"}}"#
        let result = parser.parse(out)
        #expect(result?.0.name == "create_calendar_event")
        #expect(result?.0.arguments["start_iso"] == "2026-06-26T14:00")
        #expect(result?.1 == .json)
    }

    @Test func parsesStandalonePythonicAsTrusted() {
        let out = #"create_reminder(title="Walk dog", due_iso="2026-06-27T09:00")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "create_reminder")
        #expect(result?.0.arguments["title"] == "Walk dog")
        #expect(result?.0.arguments["due_iso"] == "2026-06-27T09:00")
        #expect(result?.1 == .native)  // standalone call → trusted, no verify hint
    }

    @Test func parsesPrimedBracketedCallAsTrusted() {
        // The shape the runtime's <|tool_call_start|> primer produces.
        let out = #"[create_reminder(title="Feed the dogs", due_iso="2026-06-26T06:00", notes="")]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "create_reminder")
        #expect(result?.0.arguments["title"] == "Feed the dogs")
        #expect(result?.1 == .native)
    }

    @Test func flagsPythonicRecoveredFromProse() {
        let out = #"Sure, I'll set that up: create_reminder(title="Walk dog", due_iso="2026-06-27T09:00") for you."#
        let result = parser.parse(out)
        #expect(result?.0.name == "create_reminder")
        #expect(result?.1 == .pythonic)  // embedded in prose → verify hint
    }

    @Test func coercesNumericArguments() {
        let out = #"[{"name":"add_to_list","arguments":{"list":"Shopping","item":"2 apples","qty":2}}]"#
        let result = parser.parse(out)
        #expect(result?.0.arguments["qty"] == "2")
    }

    @Test func returnsNilOnPlainText() {
        #expect(parser.parse("I'm not sure what you mean — could you clarify?") == nil)
    }

    @Test func parsesFileToolCalls() {
        let save = #"[{"name":"save_file","arguments":{"name":"list.txt","content":"eggs\nmilk"}}]"#
        let result = parser.parse(save)
        #expect(result?.0.name == "save_file")
        #expect(result?.0.arguments["name"] == "list.txt")

        let read = #"[{"name":"read_file","arguments":{"purpose":"the shopping list"}}]"#
        let readResult = parser.parse(read)
        #expect(readResult?.0.name == "read_file")
        #expect(readResult?.0.arguments["purpose"] == "the shopping list")
    }
}
