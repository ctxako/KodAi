//
//  EventKitToolRouter.swift
//  kodai-consumer
//
//  Executes the EventKit tools (calendar + reminders) after the user confirms
//  writes. Calendar uses write-only access; reminders use full access.
//  Non-EventKit tools hit the default path and return not_implemented.
//

import Foundation
import EventKit
import KodaiKernel

enum ConfirmDecision: Sendable {
    case accept(AssistantToolCall)
    case cancel
}

struct EventKitToolRouter: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision
    var onActivity: ((String) -> Void)?

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
        let toolName = call.toolName

        if Self.isQuery(call) {
            onActivity?("Checking: \(toolName)")
            do {
                return try await perform(call)
            } catch {
                return .failure(tool: toolName, error: error.localizedDescription)
            }
        }

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
        case let .calendarCreateEvent(title, start, end, location, notes, _, _):
            return try await createEvent(title: title, start: start, end: end, location: location, notes: notes)
        case let .calendarListEvents(start, end, _):
            return try await fetchCalendarEvents(start: start, end: end)
        case let .calendarDeleteEvent(eventId):
            return try await deleteEvent(eventId: eventId)
        case let .remindersCreate(title, due, notes, list, priority):
            return try await createReminder(title: title, due: due, listName: list, notes: notes, priority: priority)
        case let .remindersList(list, completed):
            return try await fetchReminders(listName: list, status: completed ? "completed" : nil)
        case let .remindersComplete(reminderId):
            return try await completeReminder(reminderId: reminderId)
        default:
            return .failure(tool: call.toolName, error: "not_implemented")
        }
    }

    private func createEvent(
        title: String, start: Date, end: Date?, location: String?, notes: String?
    ) async throws -> ToolResult {
        guard try await store.requestWriteOnlyAccessToEvents() else {
            return .failure(tool: "calendar_create_event", error: "calendar_access_denied")
        }
        guard let calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first else {
            return .failure(tool: "calendar_create_event", error: "no_calendar_available")
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(3600)
        event.location = location
        event.notes = notes
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return .ok(tool: "calendar_create_event", result: ["title": title, "start": Self.iso(start)])
    }

    private func deleteEvent(eventId: String) async throws -> ToolResult {
        // Full access: write-only can't look up events by identifier.
        guard try await store.requestFullAccessToEvents() else {
            return .failure(tool: "calendar_delete_event", error: "calendar_access_denied")
        }
        guard let event = store.event(withIdentifier: eventId) else {
            return .failure(tool: "calendar_delete_event", error: "event_not_found")
        }
        try store.remove(event, span: .thisEvent)
        return .ok(tool: "calendar_delete_event", result: ["event_id": eventId, "deleted": "true"])
    }

    private func createReminder(
        title: String, due: Date?, listName: String?, notes: String?, priority: String?
    ) async throws -> ToolResult {
        guard try await store.requestFullAccessToReminders() else {
            return .failure(tool: "reminders_create", error: "reminders_access_denied")
        }
        guard let calendar = try reminderCalendar(named: listName) else {
            return .failure(tool: "reminders_create", error: "no_reminder_list_available")
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
        if let priority {
            switch priority.lowercased() {
            case "low": reminder.priority = 9
            case "medium": reminder.priority = 5
            case "high": reminder.priority = 1
            default: break
            }
        }
        try store.save(reminder, commit: true)

        var result = ["title": title]
        if let listName { result["list"] = listName }
        if let due { result["due"] = Self.iso(due) }
        return .ok(tool: "reminders_create", result: result)
    }

    private func completeReminder(reminderId: String) async throws -> ToolResult {
        guard try await store.requestFullAccessToReminders() else {
            return .failure(tool: "reminders_complete", error: "reminders_access_denied")
        }
        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return .failure(tool: "reminders_complete", error: "reminder_not_found")
        }
        item.isCompleted = true
        try store.save(item, commit: true)
        return .ok(tool: "reminders_complete", result: ["reminder_id": reminderId, "completed": "true"])
    }

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

    // MARK: - Queries

    private func fetchCalendarEvents(start: Date, end: Date) async throws -> ToolResult {
        // Full access: write-only returns no events from queries.
        guard try await store.requestFullAccessToEvents() else {
            return .failure(tool: "calendar_list_events", error: "calendar_access_denied")
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            return .ok(tool: "calendar_list_events", result: [
                "summary": "No events found.",
                "count": "0"
            ])
        }

        let lines = events.prefix(20).map { event in
            var line = "• \(event.title ?? "Untitled") — \(Self.timeRange(event.startDate, event.endDate))"
            if let loc = event.location, !loc.isEmpty { line += " (\(loc))" }
            line += " [event_id: \(event.eventIdentifier ?? "unknown")]"
            return line
        }
        var summary = "\(events.count) event\(events.count == 1 ? "" : "s"):\n" + lines.joined(separator: "\n")
        if events.count > 20 { summary += "\n… and \(events.count - 20) more" }

        return .ok(tool: "calendar_list_events", result: [
            "summary": summary,
            "count": "\(events.count)"
        ])
    }

    private func fetchReminders(listName: String?, status: String?) async throws -> ToolResult {
        guard try await store.requestFullAccessToReminders() else {
            return .failure(tool: "reminders_list", error: "reminders_access_denied")
        }
        let showCompleted = status?.lowercased() == "completed"
        let calendars: [EKCalendar]?
        if let listName, !listName.isEmpty {
            let match = store.calendars(for: .reminder).filter {
                $0.title.caseInsensitiveCompare(listName) == .orderedSame
            }
            if match.isEmpty {
                return .ok(tool: "reminders_list", result: [
                    "summary": "No list named \"\(listName)\" found.",
                    "count": "0"
                ])
            }
            calendars = match
        } else {
            calendars = nil
        }

        let predicate = store.predicateForReminders(in: calendars)
        let all = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }

        let filtered = all.filter { $0.isCompleted == showCompleted }
            .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }

        if filtered.isEmpty {
            let scope = listName.map { "in \($0)" } ?? ""
            let label = showCompleted ? "completed reminders" : "pending reminders"
            return .ok(tool: "reminders_list", result: [
                "summary": "No \(label) \(scope).".trimmingCharacters(in: .whitespaces),
                "count": "0"
            ])
        }

        let lines = filtered.prefix(20).map { reminder in
            var line = "• \(reminder.title ?? "Untitled")"
            if let comps = reminder.dueDateComponents, let due = comps.date {
                line += " — due \(Self.shortDate(due))"
            }
            if let list = reminder.calendar?.title { line += " [\(list)]" }
            line += " [reminder_id: \(reminder.calendarItemIdentifier)]"
            return line
        }
        let label = showCompleted ? "completed" : "pending"
        let scope = listName.map { " in \($0)" } ?? ""
        var summary = "\(filtered.count) \(label) reminder\(filtered.count == 1 ? "" : "s")\(scope):\n" + lines.joined(separator: "\n")
        if filtered.count > 20 { summary += "\n… and \(filtered.count - 20) more" }

        return .ok(tool: "reminders_list", result: [
            "summary": summary,
            "count": "\(filtered.count)"
        ])
    }

    // MARK: - Helpers

    static func isQuery(_ call: AssistantToolCall) -> Bool {
        switch call {
        case .calendarListEvents, .remindersList: return true
        default: return false
        }
    }

    static func name(_ call: AssistantToolCall) -> String {
        call.toolName
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func timeRange(_ start: Date, _ end: Date?) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let s = fmt.string(from: start)
        guard let end else { return s }
        return "\(s) – \(fmt.string(from: end))"
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
