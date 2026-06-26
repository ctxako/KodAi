//
//  AssistantTool.swift
//  kodai-consumer
//
//  The v1 tool surface (3 create actions, all writes → confirm) plus the
//  in-memory call types exchanged between the model output, the parser,
//  the validator, and (later) the executor + confirm UI.
//

import Foundation
import KodaiKernel

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

/// Thin façade over the canonical routing config in KodaiKernel
/// (`ConsumerToolRouting`), kept so existing call sites stay unchanged while the
/// catalog/prompt/primer live in one shared place the routing eval also reads.
enum AssistantToolCatalog {
    static var respondToolName: String { ConsumerToolRouting.respondToolName }
    static var toolDefinitionsJSON: String { ConsumerToolRouting.toolDefinitionsJSON }
}
