import Testing
import Foundation
@testable import kodai_consumer

struct SystemPromptBuilderTests {
    private func makeBuilder(dateString: String = "2026-06-25T12:00") -> SystemPromptBuilder {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var builder = SystemPromptBuilder()
        builder.now = { fmt.date(from: dateString)! }
        return builder
    }

    @Test func containsAllTwentyToolNames() {
        let prompt = makeBuilder().build()

        let expectedTools = [
            "calendar_create_event", "calendar_list_events", "calendar_delete_event",
            "reminders_create", "reminders_list", "reminders_complete",
            "contacts_search", "contacts_create",
            "files_list", "files_read", "files_create", "files_delete",
            "clipboard_read", "clipboard_write",
            "notification_schedule", "notification_cancel",
            "web_fetch", "open_url",
            "respond"
        ]
        for tool in expectedTools {
            #expect(prompt.contains(tool), "missing tool: \(tool)")
        }
    }

    @Test func injectsCurrentDatetime() {
        let prompt = makeBuilder(dateString: "2026-06-25T12:00").build()
        #expect(prompt.contains("2026-06-25"))
    }

    @Test func containsToolDefinitionsJSON() {
        let prompt = makeBuilder().build()
        #expect(prompt.contains("List of tools:"))
        #expect(prompt.contains(AssistantToolCatalog.toolDefinitionsJSON))
    }

    @Test func doesNotContainNoTool() {
        let prompt = makeBuilder().build()
        #expect(!prompt.contains("no_tool"))
    }

    @Test func containsToolCallFormatInstruction() {
        let prompt = makeBuilder().build()
        #expect(prompt.contains("tool_call_start") || prompt.contains("tool call"))
    }

    @Test func containsHardLimitsSection() {
        let prompt = makeBuilder().build()
        let hasLimits = prompt.contains("NEVER") || prompt.contains("never") || prompt.contains("limit") || prompt.contains("must")
        #expect(hasLimits)
    }
}
