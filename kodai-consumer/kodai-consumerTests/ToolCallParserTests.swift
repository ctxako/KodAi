import Testing
import Foundation
import KodaiKernel
@testable import kodai_consumer

struct ToolCallParserTests {
    private let parser = ToolCallParser()

    // MARK: - Native format (<|tool_call_start|>…<|tool_call_end|>)

    @Test func nativeCalendarCreateEvent() {
        let out = #"<|tool_call_start|>[{"name":"calendar_create_event","arguments":{"title":"Team sync","start_date":"2026-06-26T14:00","end_date":"2026-06-26T15:00","location":"Room 4","notes":"Bring slides","calendar_name":"Work","all_day":"false"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_create_event")
        #expect(result?.0.arguments["title"] == "Team sync")
        #expect(result?.0.arguments["start_date"] == "2026-06-26T14:00")
        #expect(result?.0.arguments["end_date"] == "2026-06-26T15:00")
        #expect(result?.0.arguments["location"] == "Room 4")
        #expect(result?.0.arguments["notes"] == "Bring slides")
        #expect(result?.0.arguments["calendar_name"] == "Work")
        #expect(result?.1 == .native)
    }

    @Test func nativeContactsSearch() {
        let out = #"<|tool_call_start|>[{"name":"contacts_search","arguments":{"query":"John"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "contacts_search")
        #expect(result?.0.arguments["query"] == "John")
        #expect(result?.1 == .native)
    }

    @Test func nativeClipboardRead() {
        let out = #"<|tool_call_start|>[{"name":"clipboard_read","arguments":{}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "clipboard_read")
        #expect(result?.0.arguments.isEmpty == true)
        #expect(result?.1 == .native)
    }

    @Test func nativeNotificationSchedule() {
        let out = #"<|tool_call_start|>[{"name":"notification_schedule","arguments":{"title":"Standup","body":"Daily standup in 5","trigger_date":"2026-06-27T09:55","identifier":"standup1"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "notification_schedule")
        #expect(result?.0.arguments["title"] == "Standup")
        #expect(result?.0.arguments["trigger_date"] == "2026-06-27T09:55")
        #expect(result?.1 == .native)
    }

    @Test func nativeWebFetch() {
        let out = #"<|tool_call_start|>[{"name":"web_fetch","arguments":{"url":"https://example.com/api"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "web_fetch")
        #expect(result?.0.arguments["url"] == "https://example.com/api")
        #expect(result?.1 == .native)
    }

    @Test func nativeOpenUrl() {
        let out = #"<|tool_call_start|>[{"name":"open_url","arguments":{"url":"https://apple.com"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "open_url")
        #expect(result?.0.arguments["url"] == "https://apple.com")
        #expect(result?.1 == .native)
    }

    @Test func nativeFilesDelete() {
        let out = #"<|tool_call_start|>[{"name":"files_delete","arguments":{"path":"old_notes.txt"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "files_delete")
        #expect(result?.0.arguments["path"] == "old_notes.txt")
        #expect(result?.1 == .native)
    }

    @Test func nativeRemindersComplete() {
        let out = #"<|tool_call_start|>[{"name":"reminders_complete","arguments":{"reminder_id":"R42"}}]<|tool_call_end|>"#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_complete")
        #expect(result?.0.arguments["reminder_id"] == "R42")
        #expect(result?.1 == .native)
    }

    // MARK: - Bare JSON format

    @Test func bareJSONCalendarCreateEvent() {
        let out = #"[{"name":"calendar_create_event","arguments":{"title":"Lunch","start_date":"2026-06-26T12:00"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_create_event")
        #expect(result?.0.arguments["title"] == "Lunch")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONContactsSearch() {
        let out = #"Sure thing. [{"name":"contacts_search","arguments":{"query":"Smith"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "contacts_search")
        #expect(result?.0.arguments["query"] == "Smith")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONClipboardRead() {
        let out = #"[{"name":"clipboard_read","arguments":{}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "clipboard_read")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONNotificationSchedule() {
        let out = #"[{"name":"notification_schedule","arguments":{"title":"Meeting","body":"Team sync in 5 min","trigger_date":"2026-06-27T14:00","identifier":"mtg1"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "notification_schedule")
        #expect(result?.0.arguments["title"] == "Meeting")
        #expect(result?.0.arguments["trigger_date"] == "2026-06-27T14:00")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONWebFetch() {
        let out = #"[{"name":"web_fetch","arguments":{"url":"https://example.com"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "web_fetch")
        #expect(result?.0.arguments["url"] == "https://example.com")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONOpenUrl() {
        let out = #"[{"name":"open_url","arguments":{"url":"https://google.com"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "open_url")
        #expect(result?.0.arguments["url"] == "https://google.com")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONFilesDelete() {
        let out = #"[{"name":"files_delete","arguments":{"path":"draft.md"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "files_delete")
        #expect(result?.0.arguments["path"] == "draft.md")
        #expect(result?.1 == .json)
    }

    @Test func bareJSONRemindersComplete() {
        let out = #"[{"name":"reminders_complete","arguments":{"reminder_id":"R99"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_complete")
        #expect(result?.0.arguments["reminder_id"] == "R99")
        #expect(result?.1 == .json)
    }

    @Test func singleObjectForm() {
        let out = #"{"name":"calendar_create_event","arguments":{"title":"Sync","start_date":"2026-06-26T14:00"}}"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_create_event")
        #expect(result?.0.arguments["start_date"] == "2026-06-26T14:00")
        #expect(result?.1 == .json)
    }

    // MARK: - Hybrid format (pythonic call wrapping JSON args — observed in
    // real LFM2.5 emissions; see route-eval diagnostics 2026-07-01)

    @Test func hybridJSONArgsInsideParens() {
        let out = #"[reminders_create({"title": "Feed the dogs", "due_date": "2026-07-01T06:00", "notes": "Don't forget!"})]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_create")
        #expect(result?.0.arguments["title"] == "Feed the dogs")
        #expect(result?.0.arguments["due_date"] == "2026-07-01T06:00")
        #expect(result?.0.arguments["notes"] == "Don't forget!")
    }

    @Test func hybridJSONArgsMissingClosingParen() {
        let out = #"[clipboard_write({"content": "hunter2"}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "clipboard_write")
        #expect(result?.0.arguments["content"] == "hunter2")
    }

    @Test func hybridUnterminatedCalendarCreate() {
        let out = #"[calendar_create_event({"title": "Dentist Appointment", "start_date": "2026-07-05T14:00", "location": "Dental Clinic"}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_create_event")
        #expect(result?.0.arguments["title"] == "Dentist Appointment")
        #expect(result?.0.arguments["location"] == "Dental Clinic")
    }

    @Test func hybridPositionalPlusColonArgs() {
        let out = #"[files_create("letter.txt", "content": "This is a draft.")]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "files_create")
        #expect(result?.0.arguments["path"] == "letter.txt")
        #expect(result?.0.arguments["content"] == "This is a draft.")
    }

    @Test func barePositionalOnlyArgument() {
        let out = #"[contacts_search("john")]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "contacts_search")
        #expect(result?.0.arguments["query"] == "john")
    }

    // MARK: - Pythonic format

    @Test func pythonicCalendarCreateEvent() {
        let out = #"calendar_create_event(title="Sprint planning", start_date="2026-06-26T10:00")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_create_event")
        #expect(result?.0.arguments["title"] == "Sprint planning")
        #expect(result?.1 == .native)
    }

    @Test func pythonicContactsSearch() {
        let out = #"contacts_search(query="Alice")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "contacts_search")
        #expect(result?.0.arguments["query"] == "Alice")
        #expect(result?.1 == .native)
    }

    @Test func pythonicClipboardRead() {
        let out = #"clipboard_read()"#
        let result = parser.parse(out)
        #expect(result?.0.name == "clipboard_read")
        #expect(result?.1 == .native)
    }

    @Test func pythonicNotificationSchedule() {
        let out = #"notification_schedule(title="Gym", body="Time to work out", trigger_date="2026-06-27T18:00", identifier="gym1")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "notification_schedule")
        #expect(result?.0.arguments["title"] == "Gym")
        #expect(result?.0.arguments["trigger_date"] == "2026-06-27T18:00")
        #expect(result?.1 == .native)
    }

    @Test func pythonicWebFetch() {
        let out = #"web_fetch(url="https://example.com/page")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "web_fetch")
        #expect(result?.0.arguments["url"] == "https://example.com/page")
        #expect(result?.1 == .native)
    }

    @Test func pythonicOpenUrl() {
        let out = #"open_url(url="https://docs.swift.org")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "open_url")
        #expect(result?.0.arguments["url"] == "https://docs.swift.org")
        #expect(result?.1 == .native)
    }

    @Test func pythonicFilesDelete() {
        let out = #"files_delete(path="temp.txt")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "files_delete")
        #expect(result?.0.arguments["path"] == "temp.txt")
        #expect(result?.1 == .native)
    }

    @Test func pythonicRemindersComplete() {
        let out = #"reminders_complete(reminder_id="R7")"#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_complete")
        #expect(result?.0.arguments["reminder_id"] == "R7")
        #expect(result?.1 == .native)
    }

    // MARK: - Bracketed pythonic (trusted)

    @Test func bracketedPythonicReminder() {
        let out = #"[reminders_create(title="Feed the dogs", due_date="2026-06-26T06:00", notes="")]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_create")
        #expect(result?.0.arguments["title"] == "Feed the dogs")
        #expect(result?.1 == .native)
    }

    @Test func bracketedPythonicClipboardWrite() {
        let out = #"[clipboard_write(content="Hello world")]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "clipboard_write")
        #expect(result?.0.arguments["content"] == "Hello world")
        #expect(result?.1 == .native)
    }

    // MARK: - Confidence: low when embedded in prose

    @Test func pythonicInProseIsLowConfidence() {
        let out = #"Sure, I'll set that up: reminders_create(title="Walk dog", due_date="2026-06-27T09:00") for you."#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_create")
        #expect(result?.1 == .low)
    }

    @Test func pythonicCalendarInProseIsLowConfidence() {
        let out = #"Let me do that: calendar_create_event(title="Meeting", start_date="2026-06-28T10:00") right away."#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_create_event")
        #expect(result?.1 == .low)
    }

    // MARK: - Respond tool

    @Test func parsesRespondTool() {
        let out = #"[respond(message="Hi! What can I help you with?")]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "respond")
        #expect(result?.0.arguments["message"] == "Hi! What can I help you with?")
        #expect(result?.1 == .native)
    }

    @Test func parsesRespondToolJSON() {
        let out = #"[{"name":"respond","arguments":{"message":"I can help with calendars and reminders."}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "respond")
        #expect(result?.0.arguments["message"] == "I can help with calendars and reminders.")
        #expect(result?.1 == .json)
    }

    // MARK: - Edge cases

    @Test func returnsNilOnPlainText() {
        #expect(parser.parse("I'm not sure what you mean — could you clarify?") == nil)
    }

    @Test func coercesNumericArguments() {
        let out = #"[{"name":"reminders_create","arguments":{"title":"2 apples","list_name":"Shopping","priority":"2"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.arguments["priority"] == "2")
    }

    @Test func parsesFileToolCalls() {
        let save = #"[{"name":"files_create","arguments":{"path":"list.txt","content":"eggs\nmilk"}}]"#
        let result = parser.parse(save)
        #expect(result?.0.name == "files_create")
        #expect(result?.0.arguments["path"] == "list.txt")

        let read = #"[{"name":"files_read","arguments":{"path":"shopping.txt"}}]"#
        let readResult = parser.parse(read)
        #expect(readResult?.0.name == "files_read")
        #expect(readResult?.0.arguments["path"] == "shopping.txt")
    }

    // MARK: - Remaining domain tools (all three formats covered above)

    @Test func parsesCalendarListEventsJSON() {
        let out = #"[{"name":"calendar_list_events","arguments":{"start_date":"2026-06-26T00:00","end_date":"2026-06-26T23:59"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_list_events")
    }

    @Test func parsesCalendarDeleteEventJSON() {
        let out = #"[{"name":"calendar_delete_event","arguments":{"event_id":"EV123"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "calendar_delete_event")
        #expect(result?.0.arguments["event_id"] == "EV123")
    }

    @Test func parsesRemindersListJSON() {
        let out = #"[{"name":"reminders_list","arguments":{"list_name":"Work"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "reminders_list")
        #expect(result?.0.arguments["list_name"] == "Work")
    }

    @Test func parsesContactsCreateJSON() {
        let out = #"[{"name":"contacts_create","arguments":{"first_name":"Jane","last_name":"Doe","phone":"555-1234"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "contacts_create")
        #expect(result?.0.arguments["first_name"] == "Jane")
    }

    @Test func parsesFilesListJSON() {
        let out = #"[{"name":"files_list","arguments":{"path":"/Documents"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "files_list")
    }

    @Test func parsesClipboardWriteJSON() {
        let out = #"[{"name":"clipboard_write","arguments":{"content":"Hello world"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "clipboard_write")
        #expect(result?.0.arguments["content"] == "Hello world")
    }

    @Test func parsesNotificationCancelJSON() {
        let out = #"[{"name":"notification_cancel","arguments":{"identifier":"mtg1"}}]"#
        let result = parser.parse(out)
        #expect(result?.0.name == "notification_cancel")
        #expect(result?.0.arguments["identifier"] == "mtg1")
    }

    @Test func stringifiesJSONBooleansAsTrueFalse() {
        // CFBoolean's stringValue is "1"/"0", which the validator's `== "true"`
        // checks would read as false — booleans must keep their JSON spelling.
        let out = #"[{"name":"calendar_create_event","arguments":{"title":"trip","start_date":"2027-01-01T09:00","all_day":true}}]"#
        let result = parser.parse(out)
        #expect(result?.0.arguments["all_day"] == "true")
    }
}
