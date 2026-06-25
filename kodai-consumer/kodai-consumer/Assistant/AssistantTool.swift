//
//  AssistantTool.swift
//  kodai-consumer
//
//  The v1 tool surface (3 create actions, all writes → confirm) plus the
//  in-memory call types exchanged between the model output, the parser,
//  the validator, and (later) the executor + confirm UI.
//

import Foundation

/// v1 tool names. Kept tiny on purpose — a small, closed routing surface is
/// what makes a 1.2B reliable.
enum AssistantToolName: String, CaseIterable, Sendable {
    case createCalendarEvent = "create_calendar_event"
    case createReminder = "create_reminder"
    case addToList = "add_to_list"
    case saveFile = "save_file"
    case readFile = "read_file"
}

/// A tool call as emitted by the model and extracted by `ToolCallParser`:
/// a name plus flat string arguments. `ToolCallValidator` turns this into a
/// typed, checked `AssistantToolCall`.
struct RawToolCall: Equatable, Sendable {
    let name: String
    let arguments: [String: String]
}

/// A validated, typed tool call — ready to render in a confirm card and,
/// in Phase 3, execute against EventKit.
enum AssistantToolCall: Equatable, Sendable {
    case createCalendarEvent(title: String, start: Date, end: Date?, location: String?, notes: String?)
    case createReminder(title: String, due: Date?, list: String?, notes: String?)
    case addToList(list: String, item: String)
    case saveFile(name: String, content: String)
    case readFile(purpose: String)
}

/// The native LFM2 tool definitions injected into the system turn as
/// `List of tools: [<json>, ...]`. Descriptions carry negations ("NOT for…")
/// to keep routing crisp between the two date-ish tools.
enum AssistantToolCatalog {
    static let toolDefinitionsJSON: String = """
    [{"name":"create_calendar_event","description":"Create a calendar event at a specific date and time. Use for meetings, appointments, and anything with a start time — NOT for undated to-dos (use create_reminder).","parameters":{"type":"object","properties":{"title":{"type":"string"},"start_iso":{"type":"string","description":"ISO 8601 local start, e.g. 2026-06-26T14:00"},"end_iso":{"type":"string","description":"ISO 8601 local end"},"location":{"type":"string"},"notes":{"type":"string"}},"required":["title","start_iso"]}},{"name":"create_reminder","description":"Create a reminder or to-do, optionally with a due date. Use for tasks to remember — NOT for timed calendar events (use create_calendar_event).","parameters":{"type":"object","properties":{"title":{"type":"string"},"due_iso":{"type":"string","description":"ISO 8601 local due date/time"},"list":{"type":"string"},"notes":{"type":"string"}},"required":["title"]}},{"name":"add_to_list","description":"Add an item to a named list such as groceries, shopping, or packing. Use for list items — NOT for time-based reminders.","parameters":{"type":"object","properties":{"list":{"type":"string"},"item":{"type":"string"}},"required":["list","item"]}},{"name":"save_file","description":"Save text content to a file. The user chooses where to save in the Files app. Use for notes, lists, drafts — NOT for reminders or calendar events.","parameters":{"type":"object","properties":{"name":{"type":"string","description":"File name including extension, e.g. packing_list.txt"},"content":{"type":"string","description":"The text content to save"}},"required":["name","content"]}},{"name":"read_file","description":"Read a file the user selects from the Files app. Describe what you need so the user knows which file to pick. Use when the user asks you to read, review, or work with a file.","parameters":{"type":"object","properties":{"purpose":{"type":"string","description":"Brief description of what file is needed, shown to the user"}},"required":["purpose"]}}]
    """
}
