import Testing
import Foundation
@testable import kodai_consumer

struct ToolCallValidatorTests {
    private static let fmt: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return df
    }()

    private func date(_ string: String) -> Date { Self.fmt.date(from: string)! }

    private func validator(now: Date) -> ToolCallValidator {
        var validator = ToolCallValidator()
        validator.now = { now }
        return validator
    }

    @Test func validReminderWithFutureDue() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "Call mom", "due_iso": "2026-06-25T18:00"])
        #expect(v.validate(raw) == .success(.createReminder(title: "Call mom", due: date("2026-06-25T18:00"), list: nil, notes: nil)))
    }

    @Test func reminderWithoutDueIsAllowed() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "Buy stamps"])
        #expect(v.validate(raw) == .success(.createReminder(title: "Buy stamps", due: nil, list: nil, notes: nil)))
    }

    @Test func rejectsMissingTitle() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "create_reminder", arguments: ["due_iso": "2026-06-25T18:00"])
        #expect(v.validate(raw) == .failure(.missingField("title")))
    }

    @Test func rejectsPastDue() {
        let v = validator(now: date("2026-06-25T20:00"))
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "x", "due_iso": "2026-06-25T18:00"])
        #expect(v.validate(raw) == .failure(.pastDate(field: "due_iso", value: "2026-06-25T18:00")))
    }

    @Test func rejectsUnknownTool() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "delete_everything", arguments: [:])) == .failure(.unknownTool("delete_everything")))
    }

    @Test func calendarEventRejectsEndBeforeStart() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "create_calendar_event", arguments: [
            "title": "Sync", "start_iso": "2026-06-25T14:00", "end_iso": "2026-06-25T13:00"
        ])
        #expect(v.validate(raw) == .failure(.endBeforeStart))
    }

    @Test func addToListRequiresItem() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "add_to_list", arguments: ["list": "Groceries"])) == .failure(.missingField("item")))
    }

    // MARK: - File tools

    @Test func validSaveFile() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "save_file", arguments: ["name": "list.txt", "content": "eggs\nmilk"])
        #expect(v.validate(raw) == .success(.saveFile(name: "list.txt", content: "eggs\nmilk")))
    }

    @Test func saveFileRequiresName() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "save_file", arguments: ["content": "stuff"])) == .failure(.missingField("name")))
    }

    @Test func saveFileRequiresContent() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "save_file", arguments: ["name": "list.txt"])) == .failure(.missingField("content")))
    }

    @Test func validReadFile() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "read_file", arguments: ["purpose": "the shopping list"])
        #expect(v.validate(raw) == .success(.readFile(purpose: "the shopping list")))
    }

    @Test func readFileRequiresPurpose() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "read_file", arguments: [:])) == .failure(.missingField("purpose")))
    }
}
