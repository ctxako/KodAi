//
//  ConsumerToolRouting.swift
//  KodaiKernel
//
//  Canonical tool-routing config for the kodai-consumer agent: the tool
//  catalog, the firm system prompt, and the assistant primer. This lives in
//  KodaiKernel (not the app) so the routing eval (`kodai-route-eval`) exercises
//  the EXACT shipped prompt rather than a drifting copy. The consumer app's
//  AssistantToolCatalog / SystemPromptBuilder / RuntimeAgentModel delegate here.
//

import Foundation

public enum ConsumerToolRouting {
    /// Non-action escape hatch. The primer forces a tool call on every input, so
    /// without this a greeting like "hi" gets coerced into a real action. The
    /// model routes greetings / questions / small talk here instead.
    public static let respondToolName = "respond"

    /// Primed into the assistant turn to force a native LFM2 tool call. Without
    /// it the 1.2B refuses/narrates on most requests; priming `<|tool_call_start|>`
    /// puts the model *inside* a call so it emits `[tool(args)]`.
    public static let toolCallPrimer = "<|tool_call_start|>"

    /// LFM2 native tool definitions, rendered into the system turn as
    /// `List of tools: [<json>]`. Descriptions carry negations to keep the two
    /// date-ish tools apart.
    public static let toolDefinitionsJSON: String = """
    [{"name":"create_calendar_event","description":"Create a calendar event at a specific date and time. Use for appointments, meetings, calls, reservations, classes — anything that happens AT a scheduled time. ALWAYS use this when the request mentions an appointment, a meeting, or to schedule something. NOT for undated to-dos (use create_reminder). NOT for checking what is on the calendar (use query_calendar).","parameters":{"type":"object","properties":{"title":{"type":"string"},"start_iso":{"type":"string","description":"ISO 8601 local start, e.g. 2026-06-26T14:00"},"end_iso":{"type":"string","description":"ISO 8601 local end"},"location":{"type":"string"},"notes":{"type":"string"}},"required":["title","start_iso"]}},{"name":"create_reminder","description":"Create a reminder or to-do, optionally with a due date. Use for things to remember or do — buy or get something, call someone, take meds, a chore. NOT for appointments or meetings at a set time (use create_calendar_event). NOT for checking existing reminders (use query_reminders).","parameters":{"type":"object","properties":{"title":{"type":"string"},"due_iso":{"type":"string","description":"ISO 8601 local due date/time"},"list":{"type":"string"},"notes":{"type":"string"}},"required":["title"]}},{"name":"add_to_list","description":"Add an item to a named list such as groceries, shopping, or packing. Use for list items — NOT for time-based reminders. NOT for checking what is on a list (use query_reminders).","parameters":{"type":"object","properties":{"list":{"type":"string"},"item":{"type":"string"}},"required":["list","item"]}},{"name":"query_calendar","description":"Check what events are on the calendar. Use when the user asks what is happening, what is scheduled, whether they are free, or what is on their calendar for a date. NOT for creating events (use create_calendar_event).","parameters":{"type":"object","properties":{"date_range":{"type":"string","description":"One of: today, tomorrow, this_week, or an ISO 8601 date (YYYY-MM-DD)"}},"required":["date_range"]}},{"name":"query_reminders","description":"Check pending or completed reminders. Use when the user asks what they need to do, what reminders they have, what is on a list, or to show their to-dos. NOT for creating reminders (use create_reminder).","parameters":{"type":"object","properties":{"list":{"type":"string","description":"Optional list name to filter by"},"status":{"type":"string","description":"pending (default) or completed"}},"required":[]}},{"name":"save_file","description":"Save text content to a file the user picks in the Files app. Use ONLY when the user explicitly asks to save or write text to a file (notes, lists, drafts) — NOT for reminders or calendar events.","parameters":{"type":"object","properties":{"name":{"type":"string","description":"File name including extension, e.g. packing_list.txt"},"content":{"type":"string","description":"The text content to save"}},"required":["name","content"]}},{"name":"read_file","description":"Read a text file the user picks from the Files app. Use ONLY when the user refers to an actual file or document to open, read, or review (e.g. 'read my shopping list file', 'what is in my notes'). If no file is mentioned, use respond instead.","parameters":{"type":"object","properties":{"purpose":{"type":"string","description":"Brief description of what file is needed, shown to the user"}},"required":["purpose"]}},{"name":"respond","description":"Use ONLY when the request is NOT one of the device actions above — a greeting, small talk, a question, thanks, or anything you cannot do. Put a short reply in message. Never use this to avoid a real action the user asked for.","parameters":{"type":"object","properties":{"message":{"type":"string","description":"A brief reply to show the user"}},"required":["message"]}}]
    """

    /// The firm system prompt: exactly one tool per turn, the appointment→calendar
    /// routing rule, datetime grounding, and the tool list.
    public static func systemPrompt(
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let stamp = format(now, "EEEE, yyyy-MM-dd HH:mm", calendar: calendar, timeZone: timeZone)
        return """
        You are kodAI, an on-device assistant. Reply by calling exactly one tool from the list below — always exactly one, never plain text outside a tool call. You can create reminders, create calendar events, add items to lists, save or read files, and check your calendar or reminders. For a device action, call the matching tool with correct arguments. An appointment, meeting, class, reservation, or anything booked or scheduled at a set time is a calendar event (create_calendar_event), NOT a reminder. Use create_reminder only for a task to do or remember (buy something, call someone, take meds). When the user asks what is on their calendar or what events they have, use query_calendar. When the user asks what reminders or to-dos they have, or what is on a list, use query_reminders. For a greeting, a question, small talk, or anything that is not one of those actions, call respond with a brief reply.
        Current date and time: \(stamp) (\(timeZone.identifier)).
        Resolve relative times ("tonight", "tomorrow", "6pm", "in 2 hours") to absolute ISO 8601 (YYYY-MM-DDTHH:MM) using the current time above.
        List of tools: \(toolDefinitionsJSON)
        """
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar, timeZone: TimeZone) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = calendar
        df.timeZone = timeZone
        df.dateFormat = pattern
        return df.string(from: date)
    }
}
