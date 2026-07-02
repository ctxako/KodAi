//
//  ToolIntentSupport.swift
//  kodai-consumer
//
//  Shared plumbing for the App Intents surface. The intents are deliberately
//  thin: each one builds the same `AssistantToolCall` the model emits and runs
//  it through the same routers as the in-app pipeline, so tool logic lives in
//  exactly one place (hard constraint: do not duplicate execution).
//
//  The confirmation gate is preserved on this surface too — App Intents' native
//  `requestConfirmation` is wired into the router's confirm seam, so every write
//  is still confirmed before it happens, just as the in-app confirm card does.
//

import Foundation
import AppIntents
import KodaiKernel

// MARK: - Executors

enum IntentToolExecutor {
    // EventKit writes (create/delete event, create/complete reminder)
    static func runEventKitWrite(
        _ call: AssistantToolCall,
        confirm: @escaping (AssistantToolCall) async -> ConfirmDecision
    ) async -> ToolResult {
        await EventKitToolRouter(confirm: confirm).execute(call)
    }

    // EventKit reads (list events, list reminders)
    static func runEventKitRead(_ call: AssistantToolCall) async -> ToolResult {
        await EventKitToolRouter(confirm: { .accept($0) }).execute(call)
    }

    // Contacts write (create)
    static func runContactsWrite(
        _ call: AssistantToolCall,
        confirm: @escaping (AssistantToolCall) async -> ConfirmDecision
    ) async -> ToolResult {
        await ContactsToolRouter(confirm: confirm).execute(call)
    }

    // Contacts read (search)
    static func runContactsRead(_ call: AssistantToolCall) async -> ToolResult {
        await ContactsToolRouter(confirm: { .accept($0) }).execute(call)
    }

    // Clipboard write
    static func runClipboardWrite(
        _ call: AssistantToolCall,
        confirm: @escaping (AssistantToolCall) async -> ConfirmDecision
    ) async -> ToolResult {
        await ClipboardToolRouter(confirm: confirm).execute(call)
    }

    // Clipboard read
    static func runClipboardRead(_ call: AssistantToolCall) async -> ToolResult {
        await ClipboardToolRouter(confirm: { .accept($0) }).execute(call)
    }

    // Notification write (schedule/cancel)
    static func runNotificationWrite(
        _ call: AssistantToolCall,
        confirm: @escaping (AssistantToolCall) async -> ConfirmDecision
    ) async -> ToolResult {
        await NotificationToolRouter(confirm: confirm).execute(call)
    }

    // System write (open URL)
    static func runSystemWrite(
        _ call: AssistantToolCall,
        confirm: @escaping (AssistantToolCall) async -> ConfirmDecision
    ) async -> ToolResult {
        await SystemToolRouter(confirm: confirm).execute(call)
    }

    // System read (web fetch)
    static func runSystemRead(_ call: AssistantToolCall) async -> ToolResult {
        await SystemToolRouter(confirm: { .accept($0) }).execute(call)
    }

    // File read (list files — headless, for contained paths only)
    static func runFileRead(_ call: AssistantToolCall) async -> ToolResult {
        await FileToolRouter(presentPicker: { _ in .cancelled }).execute(call)
    }

    static func throwIfFailed(_ result: ToolResult) throws {
        guard result.status == .error else { return }
        let code = result.fields["error"] ?? "unknown"
        if code == "cancelled_by_user" { throw CancellationError() }
        throw IntentToolError(code: code)
    }
}

// MARK: - Error Mapping

struct IntentToolError: Error, CustomLocalizedStringResourceConvertible {
    let code: String

    var localizedStringResource: LocalizedStringResource {
        switch code {
        case "calendar_access_denied":
            return "Calendar access is off. Open kodAI, or Settings › Privacy › Calendars, to allow it."
        case "reminders_access_denied":
            return "Reminders access is off. Open kodAI, or Settings › Privacy › Reminders, to allow it."
        case "contacts_access_denied":
            return "Contacts access is off. Open kodAI, or Settings › Privacy › Contacts, to allow it."
        case "notifications_access_denied":
            return "Notification access is off. Open kodAI, or Settings › Privacy › Notifications, to allow it."
        case "no_reminder_list_available":
            return "No Reminders list was found. Open the Reminders app once, then try again."
        case "no_calendar_available":
            return "No calendar is available. Set a default in Settings › Calendar, then try again."
        case "invalid_path_prefix":
            return "Use a path starting with local/ or icloud/ (e.g. local/Documents)."
        default:
            return "kodAI couldn't complete that action (\(code))."
        }
    }
}

// MARK: - Dialogs

enum IntentToolDialog {
    // Calendar
    static func confirmEvent(title: String, start: Date) -> IntentDialog {
        "Add \"\(title)\" to your calendar on \(format(start))?"
    }
    static func createdEvent(title: String) -> IntentDialog { "Event added: \(title)." }
    static func confirmDeleteEvent() -> IntentDialog { "Delete this calendar event?" }
    static func deletedEvent() -> IntentDialog { "Event deleted." }

    // Reminders
    static func confirmReminder(title: String, due: Date?) -> IntentDialog {
        if let due { return "Add a reminder to \(title) for \(format(due))?" }
        return "Add a reminder to \(title)?"
    }
    static func createdReminder(title: String) -> IntentDialog { "Reminder set: \(title)." }
    static func confirmCompleteReminder() -> IntentDialog { "Mark this reminder as complete?" }
    static func completedReminder() -> IntentDialog { "Reminder completed." }

    // Contacts
    static func confirmCreateContact(name: String) -> IntentDialog {
        "Create a new contact for \(name)?"
    }
    static func createdContact(name: String) -> IntentDialog { "Contact created: \(name)." }

    // Clipboard
    static func confirmWriteClipboard(content: String) -> IntentDialog {
        let preview = content.count > 50 ? String(content.prefix(50)) + "…" : content
        return "Copy \"\(preview)\" to clipboard?"
    }
    static func wroteClipboard() -> IntentDialog { "Copied to clipboard." }

    // Notifications
    static func confirmScheduleNotification(title: String, date: Date) -> IntentDialog {
        "Schedule \"\(title)\" for \(format(date))?"
    }
    static func scheduledNotification(title: String) -> IntentDialog { "Notification scheduled: \(title)." }
    static func confirmCancelNotification(identifier: String) -> IntentDialog {
        "Cancel the notification \"\(identifier)\"?"
    }
    static func cancelledNotification() -> IntentDialog { "Notification cancelled." }

    // System
    static func confirmOpenURL(url: String) -> IntentDialog { "Open \(url)?" }
    static func openedURL(url: String) -> IntentDialog { "Opened \(url)." }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Intent Action Inbox

@MainActor
final class IntentActionInbox {
    static let shared = IntentActionInbox()
    private init() {}

    private var pending: [AssistantToolCall] = []
    private var pendingPrompts: [String] = []

    var onDeposit: (() -> Void)?

    func deposit(_ call: AssistantToolCall) {
        pending.append(call)
        onDeposit?()
    }

    func drain() -> [AssistantToolCall] {
        defer { pending.removeAll() }
        return pending
    }

    // Full agent prompts (toolflows) — run through the model loop rather than
    // as a direct tool call, so they need the app open and the model loaded.
    func depositPrompt(_ prompt: String) {
        pendingPrompts.append(prompt)
        onDeposit?()
    }

    func drainPrompts() -> [String] {
        defer { pendingPrompts.removeAll() }
        return pendingPrompts
    }
}
