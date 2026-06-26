//
//  EventKitToolRouter.swift
//  kodai-consumer
//
//  Executes the v1 write tools against EventKit after the user confirms each
//  one (confirm-all-writes). Calendar uses write-only access; reminders and
//  named lists use full reminders access. A cancelled confirmation comes back
//  as a structured error the loop records and surfaces.
//

import Foundation
import EventKit

enum ConfirmDecision: Sendable {
    case accept(AssistantToolCall)
    case cancel
}

struct EventKitToolRouter: ToolRouter {
    /// Presents the confirm card and resolves to the user's decision.
    let confirm: (AssistantToolCall) async -> ConfirmDecision
    var onActivity: ((String) -> Void)?

    /// One long-lived store for the whole app session. A fresh EKEventStore per
    /// call can report nil/empty calendars before its sources finish loading,
    /// which is part of why writes were failing with no_reminder_list_available.
    private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }

    init(
        confirm: @escaping (AssistantToolCall) async -> ConfirmDecision,
        onActivity: ((String) -> Void)? = nil
    ) {
        self.confirm = confirm
        self.onActivity = onActivity
    }

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        let toolName = Self.name(call)
        onActivity?("Awaiting confirmation: \(toolName)")

        let decision = await confirm(call)
        guard case let .accept(confirmed) = decision else {
            onActivity?("Cancelled: \(toolName)")
            return .failure(tool: toolName, error: "cancelled_by_user")
        }

        do {
            onActivity?("Saving: \(toolName)")
            return try await perform(confirmed)
        } catch {
            return .failure(tool: toolName, error: error.localizedDescription)
        }
    }

    // MARK: - Execution

    private func perform(_ call: AssistantToolCall) async throws -> ToolResult {
        switch call {
        case let .createCalendarEvent(title, start, end, location, notes):
            return try await createEvent(title: title, start: start, end: end, location: location, notes: notes)
        case let .createReminder(title, due, list, notes):
            return try await createReminder(title: title, due: due, listName: list, notes: notes)
        case let .addToList(list, item):
            return try await createReminder(title: item, due: nil, listName: list, notes: nil)
        case .saveFile, .readFile:
            return .failure(tool: "unknown", error: "not_an_eventkit_tool")
        }
    }

    private func createEvent(
        title: String, start: Date, end: Date?, location: String?, notes: String?
    ) async throws -> ToolResult {
        guard try await store.requestWriteOnlyAccessToEvents() else {
            return .failure(tool: "create_calendar_event", error: "calendar_access_denied")
        }
        // Under write-only access `defaultCalendarForNewEvents` can be nil, but
        // `calendars(for: .event)` still returns a single virtual calendar and
        // EventKit saves the event to the calendar the person actually uses.
        // Fall back to it so a missing default doesn't block the write.
        guard let calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first else {
            return .failure(tool: "create_calendar_event", error: "no_calendar_available")
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(3600)
        event.location = location
        event.notes = notes
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return .ok(tool: "create_calendar_event", result: ["title": title, "start": Self.iso(start)])
    }

    private func createReminder(
        title: String, due: Date?, listName: String?, notes: String?
    ) async throws -> ToolResult {
        let toolName = listName == nil ? "create_reminder" : "add_to_list"
        guard try await store.requestFullAccessToReminders() else {
            return .failure(tool: toolName, error: "reminders_access_denied")
        }
        guard let calendar = try reminderCalendar(named: listName) else {
            return .failure(tool: toolName, error: "no_reminder_list_available")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        try store.save(reminder, commit: true)

        var result = ["title": title]
        if let listName { result["list"] = listName }
        if let due { result["due"] = Self.iso(due) }
        return .ok(tool: toolName, result: result)
    }

    /// Resolves the list a reminder is saved to. Falls back through default →
    /// any writable list → a created "kodAI" list, because
    /// defaultCalendarForNewReminders() is nil whenever the user hasn't picked a
    /// default list — even with writable iCloud lists present. The no-list case
    /// is the common one (the model usually omits `list`), so it must be robust.
    private func reminderCalendar(named name: String?) throws -> EKCalendar? {
        if let name, !name.isEmpty {
            if let existing = store.calendars(for: .reminder).first(where: {
                $0.title.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return existing
            }
            return try createReminderList(named: name)
        }
        if let defaultList = store.defaultCalendarForNewReminders() { return defaultList }
        if let writable = store.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) {
            return writable
        }
        return try createReminderList(named: "kodAI")
    }

    /// Creates a reminder list on the best available source — one that already
    /// holds reminder lists, else iCloud (calDAV), else local. nil only when no
    /// source can hold reminders at all (Reminders off in iCloud and no local).
    private func createReminderList(named name: String) throws -> EKCalendar? {
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.calendars(for: .reminder).first?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        else { return nil }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    // MARK: - Helpers

    static func name(_ call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "create_calendar_event"
        case .createReminder: return "create_reminder"
        case .addToList: return "add_to_list"
        case .saveFile: return "save_file"
        case .readFile: return "read_file"
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
