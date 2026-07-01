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

    // MARK: - Calendar

    @Test func validCalendarCreateEvent() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: [
            "title": "Sync", "start_date": "2026-06-25T14:00", "end_date": "2026-06-25T15:00",
            "location": "Office", "notes": "Bring laptop"
        ])
        if case let .success(.calendarCreateEvent(title, start, end, location, notes, calendarName, allDay)) = v.validate(raw) {
            #expect(title == "Sync")
            #expect(start == date("2026-06-25T14:00"))
            #expect(end == date("2026-06-25T15:00"))
            #expect(location == "Office")
            #expect(notes == "Bring laptop")
            #expect(calendarName == nil)
            #expect(allDay == nil)
        } else {
            Issue.record("expected valid calendar_create_event")
        }
    }

    @Test func calendarCreateEventRejectsEndBeforeStart() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: [
            "title": "Sync", "start_date": "2026-06-25T14:00", "end_date": "2026-06-25T13:00"
        ])
        #expect(v.validate(raw) == .failure(.endBeforeStart))
    }

    @Test func calendarCreateEventRequiresTitle() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: ["start_date": "2026-06-25T14:00"])
        #expect(v.validate(raw) == .failure(.missingField("title")))
    }

    @Test func calendarCreateEventParsesAllDay() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: [
            "title": "Holiday", "start_date": "2026-06-25T00:00", "all_day": "true"
        ])
        if case let .success(.calendarCreateEvent(_, _, _, _, _, _, allDay)) = v.validate(raw) {
            #expect(allDay == true)
        } else {
            Issue.record("expected valid calendar_create_event with all_day")
        }
    }

    @Test func validCalendarListEvents() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "calendar_list_events", arguments: [
            "start_date": "2026-06-24T00:00", "end_date": "2026-06-25T23:59"
        ])
        if case let .success(.calendarListEvents(start, end, calendarName)) = v.validate(raw) {
            #expect(start == date("2026-06-24T00:00"))
            #expect(end == date("2026-06-25T23:59"))
            #expect(calendarName == nil)
        } else {
            Issue.record("expected valid calendar_list_events")
        }
    }

    @Test func calendarListEventsAllowsPastDates() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "calendar_list_events", arguments: [
            "start_date": "2026-06-20T00:00", "end_date": "2026-06-21T23:59"
        ])
        if case .success(.calendarListEvents) = v.validate(raw) {
        } else {
            Issue.record("calendar_list_events should allow past dates")
        }
    }

    @Test func calendarListEventsRequiresStartDate() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "calendar_list_events", arguments: ["end_date": "2026-06-25T23:59"])
        #expect(v.validate(raw) == .failure(.missingField("start_date")))
    }

    @Test func validCalendarDeleteEvent() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "calendar_delete_event", arguments: ["event_id": "ABC123"])
        #expect(v.validate(raw) == .success(.calendarDeleteEvent(eventId: "ABC123")))
    }

    @Test func calendarDeleteEventRequiresId() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "calendar_delete_event", arguments: [:])) == .failure(.missingField("event_id")))
    }

    // MARK: - Reminders

    @Test func validRemindersCreate() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: [
            "title": "Call mom", "due_date": "2026-06-25T18:00", "list_name": "Personal", "priority": "high"
        ])
        if case let .success(.remindersCreate(title, due, notes, listName, priority)) = v.validate(raw) {
            #expect(title == "Call mom")
            #expect(due == date("2026-06-25T18:00"))
            #expect(listName == "Personal")
            #expect(priority == "high")
            #expect(notes == nil)
        } else {
            Issue.record("expected valid reminders_create")
        }
    }

    @Test func remindersCreateWithoutDue() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "Buy stamps"])
        #expect(v.validate(raw) == .success(.remindersCreate(title: "Buy stamps", dueDate: nil, notes: nil, listName: nil, priority: nil)))
    }

    @Test func remindersCreateRejectsMissingTitle() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "reminders_create", arguments: ["due_date": "2026-06-25T18:00"])) == .failure(.missingField("title")))
    }

    @Test func remindersCreateDropsInventedPastDue() {
        // The model routinely hallucinates a past "today" due date when the
        // user gave none — a dateless reminder beats a failed call.
        let v = validator(now: date("2026-06-25T20:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "x", "due_date": "2026-06-25T18:00"])
        #expect(v.validate(raw) == .success(.remindersCreate(title: "x", dueDate: nil, notes: nil, listName: nil, priority: nil)))
    }

    @Test func validRemindersList() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_list", arguments: ["list_name": "Groceries", "completed": "true"])
        if case let .success(.remindersList(list, completed)) = v.validate(raw) {
            #expect(list == "Groceries")
            #expect(completed == true)
        } else {
            Issue.record("expected valid reminders_list")
        }
    }

    @Test func remindersListNoArgs() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "reminders_list", arguments: [:])) == .success(.remindersList(listName: nil, completed: false)))
    }

    @Test func validRemindersComplete() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_complete", arguments: ["reminder_id": "R42"])
        #expect(v.validate(raw) == .success(.remindersComplete(reminderId: "R42")))
    }

    @Test func remindersCompleteRequiresId() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "reminders_complete", arguments: [:])) == .failure(.missingField("reminder_id")))
    }

    // MARK: - Contacts

    @Test func validContactsSearch() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "contacts_search", arguments: ["query": "John"])
        #expect(v.validate(raw) == .success(.contactsSearch(query: "John")))
    }

    @Test func contactsSearchRequiresQuery() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "contacts_search", arguments: [:])) == .failure(.missingField("query")))
    }

    @Test func validContactsCreate() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "contacts_create", arguments: [
            "first_name": "Jane", "last_name": "Doe", "phone": "555-1234", "email": "jane@example.com"
        ])
        if case let .success(.contactsCreate(first, last, phone, email, company, notes)) = v.validate(raw) {
            #expect(first == "Jane")
            #expect(last == "Doe")
            #expect(phone == "555-1234")
            #expect(email == "jane@example.com")
            #expect(company == nil)
            #expect(notes == nil)
        } else {
            Issue.record("expected valid contacts_create")
        }
    }

    @Test func contactsCreateRequiresFirstName() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "contacts_create", arguments: ["last_name": "Doe"])) == .failure(.missingField("first_name")))
    }

    // MARK: - Files

    @Test func validFilesCreate() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_create", arguments: ["path": "list.txt", "content": "eggs\nmilk"])
        #expect(v.validate(raw) == .success(.filesCreate(path: "list.txt", content: "eggs\nmilk")))
    }

    @Test func filesCreateRequiresPath() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_create", arguments: ["content": "stuff"])) == .failure(.missingField("path")))
    }

    @Test func filesCreateRequiresContent() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_create", arguments: ["path": "list.txt"])) == .failure(.missingField("content")))
    }

    @Test func validFilesRead() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_read", arguments: ["path": "shopping.txt"])
        #expect(v.validate(raw) == .success(.filesRead(path: "shopping.txt")))
    }

    @Test func filesReadRequiresPath() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_read", arguments: [:])) == .failure(.missingField("path")))
    }

    @Test func validFilesList() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_list", arguments: ["path": "icloud/Documents"])
        #expect(v.validate(raw) == .success(.filesList(path: "icloud/Documents")))
    }

    @Test func filesListNormalizesBareDocuments() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_list", arguments: ["path": "/Documents"])
        #expect(v.validate(raw) == .success(.filesList(path: "local/")))
    }

    @Test func filesListRequiresPath() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_list", arguments: [:])) == .failure(.missingField("path")))
    }

    @Test func validFilesDelete() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_delete", arguments: ["path": "local/old.txt"])
        #expect(v.validate(raw) == .success(.filesDelete(path: "local/old.txt")))
    }

    @Test func filesDeleteNormalizesBarePathToICloud() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_delete", arguments: ["path": "old.txt"])
        #expect(v.validate(raw) == .success(.filesDelete(path: "icloud/old.txt")))
    }

    // MARK: - Path normalization (model drift on roots)

    @Test func createFolderNormalizesFilesPrefix() {
        // The observed failure: user says "in files", model emits files/coffee.
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_create_folder", arguments: ["path": "files/coffee"])
        #expect(v.validate(raw) == .success(.filesCreateFolder(path: "icloud/coffee")))
    }

    @Test func createFolderNormalizesCasedPrefixes() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_create_folder", arguments: ["path": "iCloud/Notes"]))
            == .success(.filesCreateFolder(path: "icloud/Notes")))
        #expect(v.validate(RawToolCall(name: "files_create_folder", arguments: ["path": "Local/Projects/Sub"]))
            == .success(.filesCreateFolder(path: "local/Projects/Sub")))
    }

    @Test func createFolderNormalizesBarePath() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_create_folder", arguments: ["path": "coffee"]))
            == .success(.filesCreateFolder(path: "icloud/coffee")))
    }

    @Test func createFolderKeepsValidPrefixUntouched() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_create_folder", arguments: ["path": "icloud/coffee"]))
            == .success(.filesCreateFolder(path: "icloud/coffee")))
    }

    @Test func filesReadPathNotNormalized() {
        // An unprefixed read path intentionally falls through to the picker.
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_read", arguments: ["path": "shopping list"]))
            == .success(.filesRead(path: "shopping list")))
    }

    @Test func filesDeleteRequiresPath() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "files_delete", arguments: [:])) == .failure(.missingField("path")))
    }

    // MARK: - Clipboard

    @Test func validClipboardRead() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "clipboard_read", arguments: [:])) == .success(.clipboardRead))
    }

    @Test func validClipboardWrite() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "clipboard_write", arguments: ["content": "Hello"])
        #expect(v.validate(raw) == .success(.clipboardWrite(content: "Hello")))
    }

    @Test func clipboardWriteRequiresContent() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "clipboard_write", arguments: [:])) == .failure(.missingField("content")))
    }

    // MARK: - Notifications

    @Test func validNotificationSchedule() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "notification_schedule", arguments: [
            "title": "Meeting", "body": "Sync in 5 min",
            "trigger_date": "2026-06-25T14:00", "identifier": "mtg1"
        ])
        if case let .success(.notificationSchedule(title, body, triggerDate, identifier)) = v.validate(raw) {
            #expect(title == "Meeting")
            #expect(body == "Sync in 5 min")
            #expect(triggerDate == date("2026-06-25T14:00"))
            #expect(identifier == "mtg1")
        } else {
            Issue.record("expected valid notification_schedule")
        }
    }

    @Test func notificationScheduleRejectsPastDate() {
        let v = validator(now: date("2026-06-25T20:00"))
        let raw = RawToolCall(name: "notification_schedule", arguments: [
            "title": "Late", "body": "x", "trigger_date": "2026-06-25T18:00", "identifier": "n1"
        ])
        #expect(v.validate(raw) == .failure(.pastDate(field: "trigger_date", value: "2026-06-25T18:00")))
    }

    @Test func notificationScheduleRequiresTitle() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "notification_schedule", arguments: [
            "body": "x", "trigger_date": "2026-06-25T14:00", "identifier": "n1"
        ])
        #expect(v.validate(raw) == .failure(.missingField("title")))
    }

    @Test func validNotificationCancel() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "notification_cancel", arguments: ["identifier": "mtg1"])
        #expect(v.validate(raw) == .success(.notificationCancel(identifier: "mtg1")))
    }

    @Test func notificationCancelRequiresIdentifier() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "notification_cancel", arguments: [:])) == .failure(.missingField("identifier")))
    }

    // MARK: - System

    @Test func validWebFetch() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "web_fetch", arguments: ["url": "https://example.com"])
        #expect(v.validate(raw) == .success(.webFetch(url: "https://example.com")))
    }

    @Test func webFetchRequiresUrl() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "web_fetch", arguments: [:])) == .failure(.missingField("url")))
    }

    @Test func validOpenUrl() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "open_url", arguments: ["url": "https://apple.com"])
        #expect(v.validate(raw) == .success(.openUrl(url: "https://apple.com")))
    }

    @Test func openUrlRequiresUrl() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "open_url", arguments: [:])) == .failure(.missingField("url")))
    }

    // MARK: - Unknown tool

    @Test func rejectsUnknownTool() {
        let v = validator(now: date("2026-06-25T12:00"))
        #expect(v.validate(RawToolCall(name: "delete_everything", arguments: [:])) == .failure(.unknownTool("delete_everything")))
    }

    // MARK: - Extra/unknown params → still success (lenient)

    @Test func calendarCreateEventIgnoresExtraParams() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: [
            "title": "Sync", "start_date": "2026-06-25T14:00", "unknown_param": "value", "another": "x"
        ])
        if case .success(.calendarCreateEvent) = v.validate(raw) {
        } else {
            Issue.record("extra params should be ignored")
        }
    }

    @Test func remindersCreateIgnoresExtraParams() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: [
            "title": "Test", "extra_field": "ignored", "bogus": "123"
        ])
        if case .success(.remindersCreate) = v.validate(raw) {
        } else {
            Issue.record("extra params should be ignored")
        }
    }

    @Test func contactsSearchIgnoresExtraParams() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "contacts_search", arguments: ["query": "John", "extra": "stuff"])
        if case .success(.contactsSearch) = v.validate(raw) {
        } else {
            Issue.record("extra params should be ignored")
        }
    }

    @Test func filesCreateIgnoresExtraParams() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "files_create", arguments: ["path": "t.txt", "content": "x", "foo": "bar"])
        if case .success(.filesCreate) = v.validate(raw) {
        } else {
            Issue.record("extra params should be ignored")
        }
    }

    @Test func clipboardReadIgnoresExtraParams() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "clipboard_read", arguments: ["whatever": "x"])
        if case .success(.clipboardRead) = v.validate(raw) {
        } else {
            Issue.record("extra params should be ignored for clipboard_read")
        }
    }

    @Test func webFetchIgnoresExtraParams() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "web_fetch", arguments: ["url": "https://example.com", "headers": "ignored"])
        if case .success(.webFetch) = v.validate(raw) {
        } else {
            Issue.record("extra params should be ignored")
        }
    }

    // MARK: - Optional params omitted → success with nil

    @Test func calendarCreateEventOptionalParams() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: [
            "title": "Quick chat", "start_date": "2026-06-25T14:00"
        ])
        if case let .success(.calendarCreateEvent(title, _, end, location, notes, calendarName, allDay)) = v.validate(raw) {
            #expect(title == "Quick chat")
            #expect(end == nil)
            #expect(location == nil)
            #expect(notes == nil)
            #expect(calendarName == nil)
            #expect(allDay == nil)
        } else {
            Issue.record("expected valid calendar_create_event with optional params omitted")
        }
    }

    @Test func remindersCreateAllOptional() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "Just a title"])
        if case let .success(.remindersCreate(title, due, notes, listName, priority)) = v.validate(raw) {
            #expect(title == "Just a title")
            #expect(due == nil)
            #expect(notes == nil)
            #expect(listName == nil)
            #expect(priority == nil)
        } else {
            Issue.record("expected valid reminders_create with all optionals nil")
        }
    }

    @Test func contactsCreateOptionalParams() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "contacts_create", arguments: ["first_name": "Solo"])
        if case let .success(.contactsCreate(first, last, phone, email, company, notes)) = v.validate(raw) {
            #expect(first == "Solo")
            #expect(last == nil)
            #expect(phone == nil)
            #expect(email == nil)
            #expect(company == nil)
            #expect(notes == nil)
        } else {
            Issue.record("expected valid contacts_create with optionals nil")
        }
    }

    @Test func notificationScheduleOptionalIdentifier() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "notification_schedule", arguments: [
            "title": "Test", "body": "Body", "trigger_date": "2026-06-25T14:00"
        ])
        if case let .success(.notificationSchedule(title, body, _, identifier)) = v.validate(raw) {
            #expect(title == "Test")
            #expect(body == "Body")
            #expect(identifier == nil)
        } else {
            Issue.record("expected valid notification_schedule with optional identifier nil")
        }
    }

    // MARK: - Bad date parsing

    @Test func calendarCreateEventBadDate() {
        let v = validator(now: date("2026-06-25T08:00"))
        let raw = RawToolCall(name: "calendar_create_event", arguments: [
            "title": "Test", "start_date": "not-a-date"
        ])
        #expect(v.validate(raw) == .failure(.badDate(field: "start_date", value: "not-a-date")))
    }

    @Test func notificationScheduleBadTriggerDate() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "notification_schedule", arguments: [
            "title": "T", "body": "B", "trigger_date": "garbage", "identifier": "n1"
        ])
        #expect(v.validate(raw) == .failure(.badDate(field: "trigger_date", value: "garbage")))
    }

    @Test func calendarListEventsBadEndDate() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "calendar_list_events", arguments: [
            "start_date": "2026-06-25T00:00", "end_date": "invalid"
        ])
        #expect(v.validate(raw) == .failure(.badDate(field: "end_date", value: "invalid")))
    }

    // MARK: - Respond tool

    @Test func respondToolNotInValidator() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "respond", arguments: ["message": "hi"])
        let result = v.validate(raw)
        #expect(result == .failure(.unknownTool("respond")))
    }

    // MARK: - Natural-language date fallback

    private func validator(now: Date, nl: Date?) -> ToolCallValidator {
        var v = validator(now: now)
        v.resolveNaturalDate = { _, _ in nl }
        return v
    }

    @Test func reminderFallsBackToPhraseWhenDateMissing() {
        let due = date("2026-06-25T18:00")
        let v = validator(now: date("2026-06-25T12:00"), nl: due)
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "Dinner"])
        #expect(v.validate(raw, userInput: "remind me about dinner at 6 tonight")
            == .success(.remindersCreate(title: "Dinner", dueDate: due, notes: nil, listName: nil, priority: nil)))
    }

    @Test func reminderFallsBackWhenDateUnparseable() {
        let due = date("2026-06-26T09:00")
        let v = validator(now: date("2026-06-25T12:00"), nl: due)
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "Standup", "due_date": "tomorrow morning"])
        #expect(v.validate(raw, userInput: "remind me about standup tomorrow at 9")
            == .success(.remindersCreate(title: "Standup", dueDate: due, notes: nil, listName: nil, priority: nil)))
    }

    @Test func reminderFallbackRescuesPastDate() {
        let due = date("2026-06-26T18:00")
        let v = validator(now: date("2026-06-25T20:00"), nl: due)
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "Call", "due_date": "2026-06-25T18:00"])
        #expect(v.validate(raw, userInput: "remind me to call tomorrow at 6pm")
            == .success(.remindersCreate(title: "Call", dueDate: due, notes: nil, listName: nil, priority: nil)))
    }

    @Test func reminderFallbackWithin24hRollsToNextDay() {
        // "at 8pm" said after 8pm means the NEXT 8pm — a bare-time fallback
        // that resolved to earlier today rolls forward one day.
        let v = validator(now: date("2026-06-25T20:00"), nl: date("2026-06-25T10:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "x", "due_date": "2026-06-25T18:00"])
        #expect(v.validate(raw, userInput: "remind me at 10")
            == .success(.remindersCreate(title: "x", dueDate: date("2026-06-26T10:00"), notes: nil, listName: nil, priority: nil)))
    }

    @Test func reminderDropsDueWhenFallbackIsDistantPast() {
        // A fallback more than a day old isn't a rollable bare time — the due
        // date is dropped rather than failing the whole call.
        let v = validator(now: date("2026-06-25T20:00"), nl: date("2026-06-20T10:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "x", "due_date": "2026-06-25T18:00"])
        #expect(v.validate(raw, userInput: "remind me about last thursday")
            == .success(.remindersCreate(title: "x", dueDate: nil, notes: nil, listName: nil, priority: nil)))
    }

    @Test func calendarFallsBackToPhraseForStart() {
        let start = date("2026-06-26T12:00")
        let v = validator(now: date("2026-06-25T12:00"), nl: start)
        let raw = RawToolCall(name: "calendar_create_event", arguments: ["title": "Lunch"])
        #expect(v.validate(raw, userInput: "schedule lunch tomorrow at noon")
            == .success(.calendarCreateEvent(title: "Lunch", startDate: start, endDate: nil, location: nil, notes: nil, calendarName: nil, allDay: nil)))
    }

    @Test func parseAcceptsIso8601WithZoneDesignator() {
        let v = validator(now: date("2026-06-25T12:00"))
        let raw = RawToolCall(name: "reminders_create", arguments: ["title": "Sync", "due_date": "2026-12-31T23:59:00Z"])
        if case .success(.remindersCreate(_, let due, _, _, _)) = v.validate(raw) {
            #expect(due != nil)
        } else {
            Issue.record("expected a valid reminder with a parsed Z-suffixed date")
        }
    }
}
