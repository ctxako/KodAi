# Phase 6: App Intents Update

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. Phases 0-5 expanded the tool surface from 7 to 20 tools with new routers, data layer, feed UI, and onboarding.

The existing App Intents (in `kodai-consumer/AppIntents/`) expose the old v1 tools to Siri, Shortcuts, and Spotlight: `CreateReminderIntent`, `CreateCalendarEventIntent`, `AddToListIntent`, `SaveFileIntent`, `ReadFileIntent`. These need to be updated to cover all 20 tools.

Read the existing files first:
- `kodai-consumer/AppIntents/ToolAppIntents.swift` — current intent definitions
- `kodai-consumer/AppIntents/ToolAppEntities.swift` — result entity types
- `kodai-consumer/AppIntents/KodaiAppShortcuts.swift` — spoken phrases
- `kodai-consumer/AppIntents/ToolIntentSupport.swift` — shared executor, errors, dialogs

## What to do

### 1. Expand `ToolAppIntents.swift`

Add new App Intent structs for each new tool. Follow the existing pattern — each intent:
- Has `@Parameter` properties matching the tool's parameters
- Has a `perform()` method that builds an `AssistantToolCall` and runs it through the same router
- Write intents use `requestConfirmation` before executing
- Returns an `IntentResult` with a result entity or dialog

**New intents to add:**

Calendar:
- `ListCalendarEventsIntent` — parameters: start_date, end_date, calendar_name (optional). Returns a dialog listing events.
- `DeleteCalendarEventIntent` — parameter: event_id. Confirms, then deletes. This one may need to open the app if event_id requires context from a previous list.

Reminders:
- `ListRemindersIntent` — parameters: list_name (optional), completed (optional bool). Returns dialog listing reminders.
- `CompleteReminderIntent` — parameter: reminder_id. Confirms, then completes.

Contacts:
- `SearchContactsIntent` — parameter: query string. Returns dialog with matching contacts.
- `CreateContactIntent` — parameters: first_name (required), last_name, phone, email, company. Confirms, then creates. Returns `ContactEntity`.

Files:
- `ListFilesIntent` — parameter: path. Returns dialog listing files.
- `DeleteFileIntent` — parameter: path. Confirms, then deletes. Opens the app for sandbox confirmation.

Clipboard:
- `ReadClipboardIntent` — no parameters. Returns dialog with clipboard content.
- `WriteClipboardIntent` — parameter: content string. Confirms, then writes.

Notifications:
- `ScheduleNotificationIntent` — parameters: title, body, trigger_date, identifier (optional). Confirms, then schedules. Returns `NotificationEntity`.
- `CancelNotificationIntent` — parameter: identifier. Confirms, then cancels.

System:
- `FetchWebContentIntent` — parameter: url. Returns dialog with fetched text (truncated).
- `OpenURLIntent` — parameter: url. Confirms, then opens.

**Existing intents to update:**
- `CreateReminderIntent` — update to match new `reminders_create` tool (add `priority` parameter)
- `CreateCalendarEventIntent` — update to match new `calendar_create_event` tool (verify parameter names)
- Remove `AddToListIntent` — covered by `CreateReminderIntent` with `list_name` parameter
- `SaveFileIntent` → rename to `CreateFileIntent` to match `files_create`
- `ReadFileIntent` → rename to `ReadFileContentIntent` to match `files_read`

### 2. Expand `ToolAppEntities.swift`

Add new result entities:

- `ContactEntity` — properties: name (string), phone (string?), email (string?), company (string?)
- `NotificationEntity` — properties: title (string), body (string), triggerDate (Date), identifier (string)
- `FileEntity` — properties: name (string), path (string), size (string?)

Update existing entities if needed:
- `ReminderEntity` — add `priority` field
- `CalendarEventEntity` — verify all fields are present

Each entity conforms to `AppEntity` with a `DisplayRepresentation`.

### 3. Update `KodaiAppShortcuts.swift`

Add spoken phrases for all new intents. Group by domain:

```swift
AppShortcut(
    intent: SearchContactsIntent(),
    phrases: [
        "Search contacts with \(.applicationName)",
        "Find a contact in \(.applicationName)"
    ],
    shortTitle: "Search Contacts",
    systemImageName: "person.crop.circle"
)
```

Add similar entries for: ListCalendarEvents, DeleteCalendarEvent, ListReminders, CompleteReminder, CreateContact, ListFiles, DeleteFile, ReadClipboard, WriteClipboard, ScheduleNotification, CancelNotification, FetchWebContent, OpenURL.

Remove the `AddToListIntent` shortcut.

### 4. Update `ToolIntentSupport.swift`

The shared executor and error handling needs to support all 20 tools:

- Update the `AssistantToolCall` building logic to handle all new intent types
- Add error dialogs for new permission types: `"contacts_access_denied"`, `"notifications_access_denied"`
- Update the app-handoff logic: intents that need the document picker or complex UI should open the app and deposit the call in `IntentActionInbox`

### 5. Tests

- Verify all intents compile and appear in the Shortcuts app schema
- Verify spoken phrases are registered

## Important

- Every intent executes the same routers as the in-app agent — no duplicate execution logic.
- Write intents MUST confirm before executing (via `requestConfirmation` for App Intents).
- Read intents return results directly as dialogs.
- The intents run on-device only — no network calls (except `web_fetch` which is user-initiated).
- File intents that need the document picker should open the app (use `IntentActionInbox` pattern from the existing `SaveFileIntent`/`ReadFileIntent`).
- Verify compile: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Do NOT boot or run simulators.
