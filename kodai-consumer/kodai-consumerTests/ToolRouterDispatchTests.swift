import Testing
import Foundation
import KodaiKernel
@testable import kodai_consumer

private final class RecordingRouter: ToolRouter {
    var dispatched: [String] = []
    let result: ToolResult

    init(_ result: ToolResult = .ok(tool: "mock", result: ["ok": "true"])) {
        self.result = result
    }

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        dispatched.append(call.toolName)
        return result
    }
}

private func autoAccept(_ call: AssistantToolCall) async -> ConfirmDecision { .accept(call) }
private func autoCancel(_ call: AssistantToolCall) async -> ConfirmDecision { .cancel }

private func noopPicker(_ req: FilePickerRequest) async -> FilePickerResult { .cancelled }

struct ToolRouterDispatchTests {

    // MARK: - Dispatch routes all 18 tool cases

    @Test func dispatchesCalendarTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)
        let now = Date()
        let later = now.addingTimeInterval(3600)

        let calls: [AssistantToolCall] = [
            .calendarCreateEvent(title: "Test", startDate: now, endDate: later, location: nil, notes: nil, calendarName: nil, allDay: nil),
            .calendarListEvents(startDate: now, endDate: later, calendarName: nil),
            .calendarDeleteEvent(eventId: "E123"),
        ]

        for call in calls {
            let result = await dispatch.execute(call)
            #expect(result.tool == call.toolName)
        }
    }

    @Test func dispatchesReminderTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)

        let calls: [AssistantToolCall] = [
            .remindersCreate(title: "Buy milk", dueDate: nil, notes: nil, listName: nil, priority: nil),
            .remindersList(listName: nil, completed: false),
            .remindersComplete(reminderId: "R123"),
        ]

        for call in calls {
            let result = await dispatch.execute(call)
            #expect(result.tool == call.toolName)
        }
    }

    @Test func dispatchesContactTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)

        let searchResult = await dispatch.execute(.contactsSearch(query: "John"))
        #expect(searchResult.tool == "contacts_search")

        let createResult = await dispatch.execute(
            .contactsCreate(firstName: "Jane", lastName: nil, phone: nil, email: nil, company: nil, notes: nil)
        )
        #expect(createResult.tool == "contacts_create")
    }

    @Test func dispatchesFileTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)

        let calls: [AssistantToolCall] = [
            .filesList(path: "local/"),
            .filesRead(path: "local/test.txt"),
            .filesCreate(path: "test.txt", content: "hello"),
            .filesDelete(path: "local/test.txt"),
        ]

        for call in calls {
            let result = await dispatch.execute(call)
            #expect(result.tool == call.toolName)
        }
    }

    @Test func dispatchesClipboardTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)

        let readResult = await dispatch.execute(.clipboardRead)
        #expect(readResult.tool == "clipboard_read")

        let writeResult = await dispatch.execute(.clipboardWrite(content: "test"))
        #expect(writeResult.tool == "clipboard_write")
    }

    @Test func dispatchesNotificationTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)

        let scheduleResult = await dispatch.execute(
            .notificationSchedule(title: "Test", body: "body", triggerDate: Date().addingTimeInterval(3600), identifier: "N1")
        )
        #expect(scheduleResult.tool == "notification_schedule")

        let cancelResult = await dispatch.execute(.notificationCancel(identifier: "N1"))
        #expect(cancelResult.tool == "notification_cancel")
    }

    @Test func dispatchesSystemTools() async {
        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)

        let fetchResult = await dispatch.execute(.webFetch(url: "https://example.com"))
        #expect(fetchResult.tool == "web_fetch")

        let openResult = await dispatch.execute(.openUrl(url: "https://example.com"))
        #expect(openResult.tool == "open_url")
    }

    // MARK: - Confirmation behavior

    @Test func writeToolsCancelledByUser() async {
        let dispatch = ToolRouterDispatch(confirm: autoCancel, presentFilePicker: noopPicker)

        let writeCalls: [AssistantToolCall] = [
            .clipboardWrite(content: "test"),
            .filesCreate(path: "test.txt", content: "x"),
            .filesDelete(path: "local/test.txt"),
            .notificationCancel(identifier: "N1"),
            .openUrl(url: "https://example.com"),
        ]

        for call in writeCalls {
            let result = await dispatch.execute(call)
            #expect(result.status == .error)
            #expect(result.fields["error"] == "cancelled_by_user")
        }
    }

    @Test func readToolsDontRequireConfirmation() async {
        let dispatch = ToolRouterDispatch(confirm: autoCancel, presentFilePicker: noopPicker)

        let readResult = await dispatch.execute(.clipboardRead)
        #expect(readResult.tool == "clipboard_read")
        #expect(readResult.fields["error"] != "cancelled_by_user")
    }

    // MARK: - All 18 tool names covered

    @Test func allToolNamesDispatch() async {
        let allCalls: [AssistantToolCall] = [
            .calendarCreateEvent(title: "T", startDate: Date(), endDate: nil, location: nil, notes: nil, calendarName: nil, allDay: nil),
            .calendarListEvents(startDate: Date(), endDate: Date().addingTimeInterval(86400), calendarName: nil),
            .calendarDeleteEvent(eventId: "E1"),
            .remindersCreate(title: "R", dueDate: nil, notes: nil, listName: nil, priority: nil),
            .remindersList(listName: nil, completed: false),
            .remindersComplete(reminderId: "R1"),
            .contactsSearch(query: "Q"),
            .contactsCreate(firstName: "F", lastName: nil, phone: nil, email: nil, company: nil, notes: nil),
            .filesList(path: "local/"),
            .filesRead(path: "local/t.txt"),
            .filesCreate(path: "t.txt", content: "c"),
            .filesDelete(path: "local/t.txt"),
            .clipboardRead,
            .clipboardWrite(content: "c"),
            .notificationSchedule(title: "N", body: "b", triggerDate: Date().addingTimeInterval(3600), identifier: nil),
            .notificationCancel(identifier: "N1"),
            .webFetch(url: "https://example.com"),
            .openUrl(url: "https://example.com"),
        ]

        let dispatch = ToolRouterDispatch(confirm: autoAccept, presentFilePicker: noopPicker)
        for call in allCalls {
            let result = await dispatch.execute(call)
            #expect(result.tool == call.toolName, "Dispatch returned wrong tool name for \(call.toolName)")
        }
    }
}
