import Testing
import Foundation
@testable import kodai_consumer

struct SystemPromptBuilderTests {
    @Test func usesNativeToolFormatWithInjectedDate() {
        var builder = SystemPromptBuilder()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        builder.now = { fmt.date(from: "2026-06-25T12:00")! }

        let prompt = builder.build()

        #expect(prompt.contains("List of tools:"))
        #expect(prompt.contains(AssistantToolCatalog.toolDefinitionsJSON))
        #expect(prompt.contains("create_reminder"))
        #expect(prompt.contains("create_calendar_event"))
        #expect(prompt.contains("add_to_list"))
        #expect(prompt.contains("save_file"))
        #expect(prompt.contains("read_file"))
        #expect(prompt.contains("2026-06-25"))
        #expect(!prompt.contains("no_tool"))
    }
}
