//
//  ConsumerToolCall.swift
//  KodaiKernel
//
//  The consumer agent's tool-call value types: the closed set of tool names,
//  the raw (name + flat string args) call the parser extracts, the typed/checked
//  call the validator produces, and the validation error set. These live in
//  KodaiKernel — alongside ConsumerToolRouting — so the shipped parse+validate
//  path is exercised verbatim by both the app and `kodai-route-eval` (no drift).
//

import Foundation

/// v2 tool names — 20 tools across 7 domains.
public enum AssistantToolName: String, CaseIterable, Sendable {
    case calendarCreateEvent = "calendar_create_event"
    case calendarListEvents = "calendar_list_events"
    case calendarDeleteEvent = "calendar_delete_event"
    case remindersCreate = "reminders_create"
    case remindersList = "reminders_list"
    case remindersComplete = "reminders_complete"
    case contactsSearch = "contacts_search"
    case contactsCreate = "contacts_create"
    case filesList = "files_list"
    case filesRead = "files_read"
    case filesCreate = "files_create"
    case filesCreateFolder = "files_create_folder"
    case filesDelete = "files_delete"
    case clipboardRead = "clipboard_read"
    case clipboardWrite = "clipboard_write"
    case notificationSchedule = "notification_schedule"
    case notificationCancel = "notification_cancel"
    case webFetch = "web_fetch"
    case openUrl = "open_url"
}

/// A tool call as emitted by the model and extracted by `ToolCallParser`:
/// a name plus flat string arguments. `ToolCallValidator` turns this into a
/// typed, checked `AssistantToolCall`.
public struct RawToolCall: Equatable, Sendable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

/// A validated, typed tool call — ready to render in a confirm card and to
/// execute against iOS frameworks.
public enum AssistantToolCall: Equatable, Sendable {
    case calendarCreateEvent(title: String, startDate: Date, endDate: Date?, location: String?, notes: String?, calendarName: String?, allDay: Bool?)
    case calendarListEvents(startDate: Date, endDate: Date, calendarName: String?)
    case calendarDeleteEvent(eventId: String)
    case remindersCreate(title: String, dueDate: Date?, notes: String?, listName: String?, priority: String?)
    case remindersList(listName: String?, completed: Bool)
    case remindersComplete(reminderId: String)
    case contactsSearch(query: String)
    case contactsCreate(firstName: String, lastName: String?, phone: String?, email: String?, company: String?, notes: String?)
    case filesList(path: String)
    case filesRead(path: String)
    case filesCreate(path: String, content: String)
    case filesCreateFolder(path: String)
    case filesDelete(path: String)
    case clipboardRead
    case clipboardWrite(content: String)
    case notificationSchedule(title: String, body: String, triggerDate: Date, identifier: String?)
    case notificationCancel(identifier: String)
    case webFetch(url: String)
    case openUrl(url: String)

    public var toolName: String {
        switch self {
        case .calendarCreateEvent: return AssistantToolName.calendarCreateEvent.rawValue
        case .calendarListEvents: return AssistantToolName.calendarListEvents.rawValue
        case .calendarDeleteEvent: return AssistantToolName.calendarDeleteEvent.rawValue
        case .remindersCreate: return AssistantToolName.remindersCreate.rawValue
        case .remindersList: return AssistantToolName.remindersList.rawValue
        case .remindersComplete: return AssistantToolName.remindersComplete.rawValue
        case .contactsSearch: return AssistantToolName.contactsSearch.rawValue
        case .contactsCreate: return AssistantToolName.contactsCreate.rawValue
        case .filesList: return AssistantToolName.filesList.rawValue
        case .filesRead: return AssistantToolName.filesRead.rawValue
        case .filesCreate: return AssistantToolName.filesCreate.rawValue
        case .filesCreateFolder: return AssistantToolName.filesCreateFolder.rawValue
        case .filesDelete: return AssistantToolName.filesDelete.rawValue
        case .clipboardRead: return AssistantToolName.clipboardRead.rawValue
        case .clipboardWrite: return AssistantToolName.clipboardWrite.rawValue
        case .notificationSchedule: return AssistantToolName.notificationSchedule.rawValue
        case .notificationCancel: return AssistantToolName.notificationCancel.rawValue
        case .webFetch: return AssistantToolName.webFetch.rawValue
        case .openUrl: return AssistantToolName.openUrl.rawValue
        }
    }
}

public enum ToolValidationError: Error, Equatable, Sendable {
    case unknownTool(String)
    case missingField(String)
    case badDate(field: String, value: String)
    case pastDate(field: String, value: String)
    case endBeforeStart
}
