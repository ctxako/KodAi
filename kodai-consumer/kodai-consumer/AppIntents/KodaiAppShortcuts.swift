//
//  KodaiAppShortcuts.swift
//  kodai-consumer
//
//  Groups the top-10 tool intents into App Shortcuts so they appear in
//  Spotlight and the Shortcuts app and can be run by voice with Siri.
//  (iOS caps App Shortcuts at 10 per app; the remaining intents are still
//  available in the Shortcuts app — they just don't have automatic phrases.)
//
//  Every phrase must contain the \(.applicationName) token; users can rename
//  the app in Settings and the phrases follow.
//

import AppIntents

struct KodaiAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Calendar
        AppShortcut(
            intent: CreateCalendarEventIntent(),
            phrases: [
                "Add an event in \(.applicationName)",
                "Schedule something with \(.applicationName)",
                "Create a calendar event with \(.applicationName)"
            ],
            shortTitle: "Create Event",
            systemImageName: "calendar.badge.plus"
        )

        AppShortcut(
            intent: ListCalendarEventsIntent(),
            phrases: [
                "Show my calendar in \(.applicationName)",
                "What's on my schedule in \(.applicationName)",
                "List events with \(.applicationName)"
            ],
            shortTitle: "List Events",
            systemImageName: "calendar"
        )

        // Reminders
        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Add a reminder in \(.applicationName)",
                "Remind me using \(.applicationName)",
                "Create a reminder with \(.applicationName)"
            ],
            shortTitle: "Create Reminder",
            systemImageName: "checklist"
        )

        AppShortcut(
            intent: ListRemindersIntent(),
            phrases: [
                "Show my reminders in \(.applicationName)",
                "What do I need to do in \(.applicationName)",
                "List reminders with \(.applicationName)"
            ],
            shortTitle: "List Reminders",
            systemImageName: "list.bullet"
        )

        // Contacts
        AppShortcut(
            intent: SearchContactsIntent(),
            phrases: [
                "Search contacts with \(.applicationName)",
                "Find a contact in \(.applicationName)"
            ],
            shortTitle: "Search Contacts",
            systemImageName: "person.crop.circle"
        )

        AppShortcut(
            intent: CreateContactIntent(),
            phrases: [
                "Add a contact with \(.applicationName)",
                "Create a new contact in \(.applicationName)"
            ],
            shortTitle: "Create Contact",
            systemImageName: "person.badge.plus"
        )

        // Files
        AppShortcut(
            intent: CreateFileIntent(),
            phrases: [
                "Save a file with \(.applicationName)",
                "Create a file in \(.applicationName)"
            ],
            shortTitle: "Create File",
            systemImageName: "doc.text"
        )

        AppShortcut(
            intent: ReadFileContentIntent(),
            phrases: [
                "Read a file with \(.applicationName)",
                "Open a file in \(.applicationName)"
            ],
            shortTitle: "Read File",
            systemImageName: "doc.text.magnifyingglass"
        )

        // Notifications
        AppShortcut(
            intent: ScheduleNotificationIntent(),
            phrases: [
                "Schedule a notification with \(.applicationName)",
                "Set a notification in \(.applicationName)"
            ],
            shortTitle: "Schedule Notification",
            systemImageName: "bell.badge"
        )

        // Clipboard
        AppShortcut(
            intent: ReadClipboardIntent(),
            phrases: [
                "Read clipboard with \(.applicationName)",
                "What's on my clipboard in \(.applicationName)"
            ],
            shortTitle: "Read Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
