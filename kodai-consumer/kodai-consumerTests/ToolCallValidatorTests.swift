import Testing
import Foundation
import KodaiKernel
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

    // MARK: - Natural-language date fallback

    /// Validator with a deterministic stub standing in for NSDataDetector.
    private func validator(now: Date, nl: Date?) -> ToolCallValidator {
        var v = validator(now: now)
        v.resolveNaturalDate = { _, _ in nl }
        return v
    }

    @Test func reminderFallsBackToPhraseWhenIsoMissing() {
        let due = date("2026-06-25T18:00")
        let v = validator(now: date("2026-06-25T12:00"), nl: due)
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "Dinner"])
        #expect(v.validate(raw, userInput: "remind me about dinner at 6 tonight")
            == .success(.createReminder(title: "Dinner", due: due, list: nil, notes: nil)))
    }

    @Test func reminderFallsBackWhenIsoUnparseable() {
        let due = date("2026-06-26T09:00")
        let v = validator(now: date("2026-06-25T12:00"), nl: due)
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "Standup", "due_iso": "tomorrow morning"])
        #expect(v.validate(raw, userInput: "remind me about standup tomorrow at 9")
            == .success(.createReminder(title: "Standup", due: due, list: nil, notes: nil)))
    }

    @Test func reminderFallbackRescuesPastIso() {
        let due = date("2026-06-26T18:00")
        let v = validator(now: date("2026-06-25T20:00"), nl: due)
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "Call", "due_iso": "2026-06-25T18:00"])
        #expect(v.validate(raw, userInput: "remind me to call tomorrow at 6pm")
            == .success(.createReminder(title: "Call", due: due, list: nil, notes: nil)))
    }

    @Test func reminderPastIsoStillFailsWhenFallbackAlsoPast() {
        // Both the model ISO and the phrase resolve to the past → still rejected.
        let v = validator(now: date("2026-06-25T20:00"), nl: date("2026-06-25T10:00"))
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "x", "due_iso": "2026-06-25T18:00"])
        #expect(v.validate(raw, userInput: "remind me earlier today")
            == .failure(.pastDate(field: "due_iso", value: "2026-06-25T18:00")))
    }

    @Test func calendarFallsBackToPhraseForStart() {
        let start = date("2026-06-26T12:00")
        let v = validator(now: date("2026-06-25T12:00"), nl: start)
        let raw = RawToolCall(name: "create_calendar_event", arguments: ["title": "Lunch"])
        #expect(v.validate(raw, userInput: "schedule lunch tomorrow at noon")
            == .success(.createCalendarEvent(title: "Lunch", start: start, end: nil, location: nil, notes: nil)))
    }

    @Test func parseAcceptsIso8601WithZoneDesignator() {
        // Model emits a UTC instant with a trailing Z; the strict parser must accept it.
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "create_reminder", arguments: ["title": "Sync", "due_iso": "2026-12-31T23:59:00Z"])
        if case .success(.createReminder(_, let due, _, _)) = v.validate(raw) {
            #expect(due != nil)
        } else {
            Issue.record("expected a valid reminder with a parsed Z-suffixed date")
        }
    }

    // MARK: - Query tools

    @Test func validQueryCalendar() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "query_calendar", arguments: ["date_range": "today"])
        #expect(v.validate(raw) == .success(.queryCalendar(dateRange: "today")))
    }

    @Test func queryCalendarRequiresDateRange() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "query_calendar", arguments: [:])) == .failure(.missingField("date_range")))
    }

    @Test func validQueryRemindersNoArgs() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "query_reminders", arguments: [:])
        #expect(v.validate(raw) == .success(.queryReminders(list: nil, status: nil)))
    }

    @Test func validQueryRemindersWithList() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "query_reminders", arguments: ["list": "Groceries", "status": "pending"])
        #expect(v.validate(raw) == .success(.queryReminders(list: "Groceries", status: "pending")))
    }
}
