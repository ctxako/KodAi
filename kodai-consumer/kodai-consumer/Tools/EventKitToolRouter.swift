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
import KodaiKernel

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
        case let .createCalendarEvent(title, start, end, location, notes):
            return try await createEvent(title: title, start: start, end: end, location: location, notes: notes)
        case let .createReminder(title, due, list, notes):
            return try await createReminder(title: title, due: due, listName: list, notes: notes)
        case let .addToList(list, item):
            return try await createReminder(title: item, due: nil, listName: list, notes: nil)
        case let .queryCalendar(dateRange):
            return try await fetchCalendarEvents(dateRange: dateRange)
        case let .queryReminders(list, status):
            return try await fetchReminders(listName: list, status: status)
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

    // MARK: - Queries

    private func fetchCalendarEvents(dateRange: String) async throws -> ToolResult {
        guard try await store.requestWriteOnlyAccessToEvents() else {
            return .failure(tool: "query_calendar", error: "calendar_access_denied")
        }
        let (start, end) = Self.resolveDateRange(dateRange)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            let label = Self.dateRangeLabel(dateRange)
            return .ok(tool: "query_calendar", result: [
                "summary": "No events \(label).",
                "count": "0"
            ])
        }

        let lines = events.prefix(20).map { event in
            var line = "• \(event.title ?? "Untitled") — \(Self.timeRange(event.startDate, event.endDate))"
            if let loc = event.location, !loc.isEmpty { line += " (\(loc))" }
            return line
        }
        let label = Self.dateRangeLabel(dateRange)
        var summary = "\(events.count) event\(events.count == 1 ? "" : "s") \(label):\n" + lines.joined(separator: "\n")
        if events.count > 20 { summary += "\n… and \(events.count - 20) more" }

        return .ok(tool: "query_calendar", result: [
            "summary": summary,
            "count": "\(events.count)"
        ])
    }

    private func fetchReminders(listName: String?, status: String?) async throws -> ToolResult {
        guard try await store.requestFullAccessToReminders() else {
            return .failure(tool: "query_reminders", error: "reminders_access_denied")
        }
        let showCompleted = status?.lowercased() == "completed"
        let calendars: [EKCalendar]?
        if let listName, !listName.isEmpty {
            let match = store.calendars(for: .reminder).filter {
                $0.title.caseInsensitiveCompare(listName) == .orderedSame
            }
            if match.isEmpty {
                return .ok(tool: "query_reminders", result: [
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
            return .ok(tool: "query_reminders", result: [
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
            return line
        }
        let label = showCompleted ? "completed" : "pending"
        let scope = listName.map { " in \($0)" } ?? ""
        var summary = "\(filtered.count) \(label) reminder\(filtered.count == 1 ? "" : "s")\(scope):\n" + lines.joined(separator: "\n")
        if filtered.count > 20 { summary += "\n… and \(filtered.count - 20) more" }

        return .ok(tool: "query_reminders", result: [
            "summary": summary,
            "count": "\(filtered.count)"
        ])
    }

    // MARK: - Helpers

    static func isQuery(_ call: AssistantToolCall) -> Bool {
        switch call {
        case .queryCalendar, .queryReminders: return true
        default: return false
        }
    }

    static func name(_ call: AssistantToolCall) -> String {
        switch call {
        case .createCalendarEvent: return "create_calendar_event"
        case .createReminder: return "create_reminder"
        case .addToList: return "add_to_list"
        case .saveFile: return "save_file"
        case .readFile: return "read_file"
        case .queryCalendar: return "query_calendar"
        case .queryReminders: return "query_reminders"
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func resolveDateRange(_ range: String) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch range.lowercased().trimmingCharacters(in: .whitespaces) {
        case "today":
            return (today, cal.date(byAdding: .day, value: 1, to: today)!)
        case "tomorrow":
            let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
            return (tomorrow, cal.date(byAdding: .day, value: 1, to: tomorrow)!)
        case "this_week", "this week":
            let end = cal.date(byAdding: .day, value: 7, to: today)!
            return (today, end)
        default:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            if let date = df.date(from: range) {
                return (date, cal.date(byAdding: .day, value: 1, to: date)!)
            }
            return (today, cal.date(byAdding: .day, value: 1, to: today)!)
        }
    }

    private static func dateRangeLabel(_ range: String) -> String {
        switch range.lowercased().trimmingCharacters(in: .whitespaces) {
        case "today": return "today"
        case "tomorrow": return "tomorrow"
        case "this_week", "this week": return "this week"
        default: return "on \(range)"
        }
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
