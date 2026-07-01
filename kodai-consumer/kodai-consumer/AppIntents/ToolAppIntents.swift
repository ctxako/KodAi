//
//  ToolAppIntents.swift
//  kodai-consumer
//
//  One AppIntent per agent tool, so the system (Siri, Spotlight, the Shortcuts
//  app) can invoke them directly — an ADDITIONAL surface alongside the in-app
//  model pipeline, which is untouched and still runs fully offline.
//
//  Each intent builds the same `AssistantToolCall` the model emits and runs it
//  through the same routers (see ToolIntentSupport). Write intents confirm via
//  App Intents' native `requestConfirmation`; read intents return results as
//  dialogs. File intents needing the document picker open the app and hand off
//  to AssistantController via IntentActionInbox.
//

import Foundation
import AppIntents
import KodaiKernel

// MARK: - Calendar

struct CreateCalendarEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Calendar Event"
    static var description = IntentDescription(
        "Adds an event to your calendar, entirely on-device.",
        categoryName: "Calendar"
    )

    @Parameter(title: "Event", requestValueDialog: "What's the event?")
    var eventTitle: String

    @Parameter(title: "Start Date")
    var startDate: Date

    @Parameter(title: "End Date")
    var endDate: Date?

    @Parameter(title: "Location")
    var location: String?

    @Parameter(title: "Notes")
    var notes: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CalendarEventEntity> & ProvidesDialog {
        let call = AssistantToolCall.calendarCreateEvent(
            title: eventTitle, startDate: startDate, endDate: endDate,
            location: location, notes: notes, calendarName: nil, allDay: nil
        )
        let result = await IntentToolExecutor.runEventKitWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .create,
                    dialog: IntentToolDialog.confirmEvent(title: eventTitle, start: startDate)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)

        let entity = CalendarEventEntity(title: eventTitle, startDate: startDate, location: location)
        return .result(value: entity, dialog: IntentToolDialog.createdEvent(title: eventTitle))
    }
}

struct ListCalendarEventsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Calendar Events"
    static var description = IntentDescription(
        "Lists calendar events in a date range, entirely on-device.",
        categoryName: "Calendar"
    )

    @Parameter(title: "Start Date", requestValueDialog: "From when?")
    var startDate: Date

    @Parameter(title: "End Date", requestValueDialog: "Until when?")
    var endDate: Date

    @Parameter(title: "Calendar")
    var calendarName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.calendarListEvents(
            startDate: startDate, endDate: endDate, calendarName: calendarName
        )
        let result = await IntentToolExecutor.runEventKitRead(call)
        try IntentToolExecutor.throwIfFailed(result)
        let summary = result.fields["summary"] ?? "No events found."
        return .result(dialog: "\(summary)")
    }
}

struct DeleteCalendarEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete Calendar Event"
    static var description = IntentDescription(
        "Deletes a calendar event by its ID, entirely on-device.",
        categoryName: "Calendar"
    )

    @Parameter(title: "Event ID", requestValueDialog: "Which event ID?")
    var eventId: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.calendarDeleteEvent(eventId: eventId)
        let result = await IntentToolExecutor.runEventKitWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .do,
                    dialog: IntentToolDialog.confirmDeleteEvent()
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)
        return .result(dialog: IntentToolDialog.deletedEvent())
    }
}

// MARK: - Reminders

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Reminder"
    static var description = IntentDescription(
        "Adds a reminder to Apple Reminders, entirely on-device.",
        categoryName: "Reminders"
    )

    @Parameter(title: "Reminder", requestValueDialog: "What should I remind you about?")
    var reminderTitle: String

    @Parameter(title: "Due Date")
    var dueDate: Date?

    @Parameter(title: "List")
    var listName: String?

    @Parameter(title: "Notes")
    var notes: String?

    @Parameter(title: "Priority")
    var priority: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ReminderEntity> & ProvidesDialog {
        let call = AssistantToolCall.remindersCreate(
            title: reminderTitle, dueDate: dueDate, notes: notes, listName: listName, priority: priority
        )
        let result = await IntentToolExecutor.runEventKitWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .create,
                    dialog: IntentToolDialog.confirmReminder(title: reminderTitle, due: dueDate)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)

        let entity = ReminderEntity(title: reminderTitle, dueDate: dueDate, listName: listName, priority: priority)
        return .result(value: entity, dialog: IntentToolDialog.createdReminder(title: reminderTitle))
    }
}

struct ListRemindersIntent: AppIntent {
    static var title: LocalizedStringResource = "List Reminders"
    static var description = IntentDescription(
        "Lists pending or completed reminders, entirely on-device.",
        categoryName: "Reminders"
    )

    @Parameter(title: "List")
    var listName: String?

    @Parameter(title: "Show Completed", default: false)
    var completed: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.remindersList(listName: listName, completed: completed)
        let result = await IntentToolExecutor.runEventKitRead(call)
        try IntentToolExecutor.throwIfFailed(result)
        let summary = result.fields["summary"] ?? "No reminders found."
        return .result(dialog: "\(summary)")
    }
}

struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Reminder"
    static var description = IntentDescription(
        "Marks a reminder as complete by its ID, entirely on-device.",
        categoryName: "Reminders"
    )

    @Parameter(title: "Reminder ID", requestValueDialog: "Which reminder ID?")
    var reminderId: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.remindersComplete(reminderId: reminderId)
        let result = await IntentToolExecutor.runEventKitWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .do,
                    dialog: IntentToolDialog.confirmCompleteReminder()
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)
        return .result(dialog: IntentToolDialog.completedReminder())
    }
}

// MARK: - Contacts

struct SearchContactsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Contacts"
    static var description = IntentDescription(
        "Searches contacts by name, phone, or email, entirely on-device.",
        categoryName: "Contacts"
    )

    @Parameter(title: "Search", requestValueDialog: "Who are you looking for?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.contactsSearch(query: query)
        let result = await IntentToolExecutor.runContactsRead(call)
        try IntentToolExecutor.throwIfFailed(result)
        let summary = result.fields["summary"] ?? "No contacts found."
        return .result(dialog: "\(summary)")
    }
}

struct CreateContactIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Contact"
    static var description = IntentDescription(
        "Creates a new contact, entirely on-device.",
        categoryName: "Contacts"
    )

    @Parameter(title: "First Name", requestValueDialog: "What's the first name?")
    var firstName: String

    @Parameter(title: "Last Name")
    var lastName: String?

    @Parameter(title: "Phone")
    var phone: String?

    @Parameter(title: "Email")
    var email: String?

    @Parameter(title: "Company")
    var company: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ContactEntity> & ProvidesDialog {
        let call = AssistantToolCall.contactsCreate(
            firstName: firstName, lastName: lastName, phone: phone,
            email: email, company: company, notes: nil
        )
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        let result = await IntentToolExecutor.runContactsWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .create,
                    dialog: IntentToolDialog.confirmCreateContact(name: name)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)

        let entity = ContactEntity(name: name, phone: phone, email: email, company: company)
        return .result(value: entity, dialog: IntentToolDialog.createdContact(name: name))
    }
}

// MARK: - Files

struct CreateFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Create File"
    static var description = IntentDescription(
        "Creates a text file using kodAI's on-device file picker.",
        categoryName: "Files"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "File Name", requestValueDialog: "What should the file be called?")
    var fileName: String

    @Parameter(title: "Content", requestValueDialog: "What should I put in the file?")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentActionInbox.shared.deposit(.filesCreate(path: fileName, content: content))
        return .result(dialog: "Opening kodAI to save \(fileName)…")
    }
}

struct ReadFileContentIntent: AppIntent {
    static var title: LocalizedStringResource = "Read File"
    static var description = IntentDescription(
        "Opens kodAI to pick and read a text file on this device.",
        categoryName: "Files"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Purpose", default: "read a file", requestValueDialog: "What do you want to read?")
    var purpose: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentActionInbox.shared.deposit(.filesRead(path: purpose))
        return .result(dialog: "Opening kodAI to read a file…")
    }
}

struct ListFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "List Files"
    static var description = IntentDescription(
        "Lists files in a directory, entirely on-device. Use local/ or icloud/ prefix.",
        categoryName: "Files"
    )

    @Parameter(title: "Path", requestValueDialog: "Which directory? (e.g. local/Documents)")
    var path: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.filesList(path: path)
        let result = await IntentToolExecutor.runFileRead(call)
        try IntentToolExecutor.throwIfFailed(result)
        let summary = result.fields["summary"] ?? "No files found."
        return .result(dialog: "\(summary)")
    }
}

struct DeleteFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete File"
    static var description = IntentDescription(
        "Opens kodAI to delete a file with confirmation.",
        categoryName: "Files"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Path", requestValueDialog: "Which file?")
    var path: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentActionInbox.shared.deposit(.filesDelete(path: path))
        return .result(dialog: "Opening kodAI to delete \(path)…")
    }
}

// MARK: - Clipboard

struct ReadClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Read Clipboard"
    static var description = IntentDescription(
        "Reads the current clipboard contents, entirely on-device.",
        categoryName: "Clipboard"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await IntentToolExecutor.runClipboardRead(.clipboardRead)
        try IntentToolExecutor.throwIfFailed(result)
        let content = result.fields["content"] ?? "Clipboard is empty."
        return .result(dialog: "\(content)")
    }
}

struct WriteClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy to Clipboard"
    static var description = IntentDescription(
        "Copies text to the clipboard, entirely on-device.",
        categoryName: "Clipboard"
    )

    @Parameter(title: "Content", requestValueDialog: "What should I copy to the clipboard?")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.clipboardWrite(content: content)
        let result = await IntentToolExecutor.runClipboardWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .set,
                    dialog: IntentToolDialog.confirmWriteClipboard(content: content)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)
        return .result(dialog: IntentToolDialog.wroteClipboard())
    }
}

// MARK: - Notifications

struct ScheduleNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Schedule Notification"
    static var description = IntentDescription(
        "Schedules a local notification at a future time, entirely on-device.",
        categoryName: "Notifications"
    )

    @Parameter(title: "Title", requestValueDialog: "What's the notification title?")
    var notificationTitle: String

    @Parameter(title: "Body", requestValueDialog: "What should the notification say?")
    var body: String

    @Parameter(title: "When", requestValueDialog: "When should it fire?")
    var triggerDate: Date

    @Parameter(title: "Identifier")
    var identifier: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NotificationEntity> & ProvidesDialog {
        let call = AssistantToolCall.notificationSchedule(
            title: notificationTitle, body: body, triggerDate: triggerDate, identifier: identifier
        )
        let result = await IntentToolExecutor.runNotificationWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .create,
                    dialog: IntentToolDialog.confirmScheduleNotification(title: notificationTitle, date: triggerDate)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)

        let actualId = result.fields["identifier"] ?? identifier ?? UUID().uuidString
        let entity = NotificationEntity(title: notificationTitle, body: body, triggerDate: triggerDate, identifier: actualId)
        return .result(value: entity, dialog: IntentToolDialog.scheduledNotification(title: notificationTitle))
    }
}

struct CancelNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Notification"
    static var description = IntentDescription(
        "Cancels a scheduled notification by its identifier, entirely on-device.",
        categoryName: "Notifications"
    )

    @Parameter(title: "Identifier", requestValueDialog: "Which notification identifier?")
    var identifier: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.notificationCancel(identifier: identifier)
        let result = await IntentToolExecutor.runNotificationWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .do,
                    dialog: IntentToolDialog.confirmCancelNotification(identifier: identifier)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)
        return .result(dialog: IntentToolDialog.cancelledNotification())
    }
}

// MARK: - System

struct FetchWebContentIntent: AppIntent {
    static var title: LocalizedStringResource = "Fetch Web Content"
    static var description = IntentDescription(
        "Fetches text content from a URL.",
        categoryName: "System"
    )

    @Parameter(title: "URL", requestValueDialog: "Which URL?")
    var url: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await IntentToolExecutor.runSystemRead(.webFetch(url: url))
        try IntentToolExecutor.throwIfFailed(result)
        let content = result.fields["content"] ?? "No content."
        return .result(dialog: "\(content)")
    }
}

struct OpenURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Open URL"
    static var description = IntentDescription(
        "Opens a URL or deep link.",
        categoryName: "System"
    )

    @Parameter(title: "URL", requestValueDialog: "Which URL?")
    var url: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = AssistantToolCall.openUrl(url: url)
        let result = await IntentToolExecutor.runSystemWrite(call) { confirmed in
            do {
                try await requestConfirmation(
                    actionName: .open,
                    dialog: IntentToolDialog.confirmOpenURL(url: url)
                )
                return .accept(confirmed)
            } catch {
                return .cancel
            }
        }
        try IntentToolExecutor.throwIfFailed(result)
        return .result(dialog: IntentToolDialog.openedURL(url: url))
    }
}
