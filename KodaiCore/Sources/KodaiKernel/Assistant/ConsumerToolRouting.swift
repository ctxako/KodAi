//
//  ConsumerToolRouting.swift
//  KodaiKernel
//
//  Canonical tool-routing config for the kodai-consumer agent: the tool
//  catalog, the firm system prompt, and the assistant primer. This lives in
//  KodaiKernel (not the app) so the routing eval (`kodai-route-eval`) exercises
//  the EXACT shipped prompt rather than a drifting copy.
//

import Foundation

public enum ConsumerToolRouting {
    public static let respondToolName = "respond"

    public static let toolCallPrimer = "<|tool_call_start|>"

    public static let toolDefinitionsJSON: String = """
    [{"name":"calendar_create_event","description":"Create a calendar event at a specific date and time. Use for appointments, meetings, calls, reservations, classes — anything scheduled at a set time. NOT for to-dos (use reminders_create). NOT for checking events (use calendar_list_events).","parameters":{"type":"object","properties":{"title":{"type":"string"},"start_date":{"type":"string","description":"ISO 8601 start, e.g. 2026-06-26T14:00"},"end_date":{"type":"string","description":"ISO 8601 end"},"location":{"type":"string"},"notes":{"type":"string"},"calendar_name":{"type":"string"},"all_day":{"type":"boolean"}},"required":["title","start_date"]}},\
    {"name":"calendar_list_events","description":"List calendar events in a date range. Use when the user asks what is scheduled, what is happening, or whether they are free. NOT for creating events (use calendar_create_event).","parameters":{"type":"object","properties":{"start_date":{"type":"string","description":"ISO 8601 range start"},"end_date":{"type":"string","description":"ISO 8601 range end"},"calendar_name":{"type":"string"}},"required":["start_date","end_date"]}},\
    {"name":"calendar_delete_event","description":"Delete a calendar event by its ID. Use only with an event_id from calendar_list_events.","parameters":{"type":"object","properties":{"event_id":{"type":"string"}},"required":["event_id"]}},\
    {"name":"reminders_create","description":"Create a reminder, to-do, or list item. Use for things to remember or do — buy something, call someone, take meds, a chore. To add to a named list, set list_name. NOT for appointments at a set time (use calendar_create_event). NOT for checking reminders (use reminders_list).","parameters":{"type":"object","properties":{"title":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 due date/time"},"notes":{"type":"string"},"list_name":{"type":"string"},"priority":{"type":"string","description":"none, low, medium, or high"}},"required":["title"]}},\
    {"name":"reminders_list","description":"List pending or completed reminders. Use when the user asks what they need to do, what reminders they have, or what is on a list. NOT for creating reminders (use reminders_create).","parameters":{"type":"object","properties":{"list_name":{"type":"string"},"completed":{"type":"boolean","description":"false for pending (default), true for completed"}},"required":[]}},\
    {"name":"reminders_complete","description":"Mark a reminder complete by its ID. Use only with a reminder_id from reminders_list.","parameters":{"type":"object","properties":{"reminder_id":{"type":"string"}},"required":["reminder_id"]}},\
    {"name":"contacts_search","description":"Search contacts by name, phone, or email. Use when the user asks to find or look up a contact.","parameters":{"type":"object","properties":{"query":{"type":"string","description":"Name, phone, or email to search"}},"required":["query"]}},\
    {"name":"contacts_create","description":"Create a new contact. Use when the user asks to add or save a contact.","parameters":{"type":"object","properties":{"first_name":{"type":"string"},"last_name":{"type":"string"},"phone":{"type":"string"},"email":{"type":"string"},"company":{"type":"string"},"notes":{"type":"string"}},"required":["first_name"]}},\
    {"name":"files_list","description":"List files in a directory. Use icloud/ prefix for iCloud Drive, local/ for app sandbox.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Directory path with icloud/ or local/ prefix"}},"required":["path"]}},\
    {"name":"files_read","description":"Read a text file. Use when the user asks to open, read, or review a file.","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},\
    {"name":"files_create","description":"Create or overwrite a text file. Use when the user asks to save, write, or create a file. NOT for creating folders (use files_create_folder).","parameters":{"type":"object","properties":{"path":{"type":"string","description":"File path including name and extension"},"content":{"type":"string","description":"Text content to write"}},"required":["path","content"]}},\
    {"name":"files_create_folder","description":"Create a new folder (directory). Use when the user asks to create, make, or add a folder. NOT for creating files (use files_create).","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Folder path with icloud/ or local/ prefix, e.g. icloud/MyFolder or local/Projects/Sub"}},"required":["path"]}},\
    {"name":"files_delete","description":"Delete a file. Use when the user asks to remove or delete a file.","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},\
    {"name":"clipboard_read","description":"Read the current clipboard contents.","parameters":{"type":"object","properties":{},"required":[]}},\
    {"name":"clipboard_write","description":"Copy text to the clipboard.","parameters":{"type":"object","properties":{"content":{"type":"string","description":"Text to copy"}},"required":["content"]}},\
    {"name":"notification_schedule","description":"Schedule a local notification at a future time.","parameters":{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"},"trigger_date":{"type":"string","description":"ISO 8601 date/time to fire"},"identifier":{"type":"string","description":"Optional ID for canceling later"}},"required":["title","body","trigger_date"]}},\
    {"name":"notification_cancel","description":"Cancel a scheduled notification by its identifier.","parameters":{"type":"object","properties":{"identifier":{"type":"string"}},"required":["identifier"]}},\
    {"name":"web_fetch","description":"Fetch the text content of a URL.","parameters":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}},\
    {"name":"open_url","description":"Open a URL or deep link. Use for web pages, apps via deep links, or tel:// links.","parameters":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}},\
    {"name":"respond","description":"Use ONLY when the request is NOT one of the device actions above — a greeting, small talk, a question, thanks, or anything you cannot do. Put a short reply in message. Never use this to avoid a real action the user asked for.","parameters":{"type":"object","properties":{"message":{"type":"string","description":"A brief reply to show the user"}},"required":["message"]}}]
    """

    public static func systemPrompt(
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let stamp = format(now, "EEEE, yyyy-MM-dd HH:mm", calendar: calendar, timeZone: timeZone)
        return """
        You are kodAI, an on-device assistant. Reply by calling exactly one tool from the list below — always exactly one, never plain text outside a tool call. You can manage calendar events, reminders, contacts, files, clipboard, notifications, and open URLs. For a device action, call the matching tool with correct arguments. An appointment, meeting, class, reservation, or anything scheduled at a set time is a calendar event (calendar_create_event), NOT a reminder. Use reminders_create for tasks, to-dos, list items, and things to remember. To add an item to a named list, use reminders_create with a list_name. When the user asks what is on their calendar, use calendar_list_events. When the user asks what reminders they have, use reminders_list. For a greeting, a question, small talk, or anything that is not a device action, call respond with a brief reply.
        Hard limits: you cannot send iMessages or SMS, read email or message inboxes, change system settings, install or remove apps, or execute code. File access is limited to app sandbox, iCloud Drive, and shared folders.
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
