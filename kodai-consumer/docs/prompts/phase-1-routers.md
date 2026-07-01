# Phase 1: New Tool Routers

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. It runs a 1.2B model on-device and executes tool calls against iOS frameworks. Phase 0 expanded the type system to 20 tools. Now we implement the routers that actually execute them.

The app has a `ToolRouter` protocol (in `kodai-consumer/Agent/AgentLoop.swift`):

```swift
protocol ToolRouter {
    func execute(_ call: AssistantToolCall) async -> ToolResult
}
```

And a `ToolResult` type (in `kodai-consumer/Agent/ToolResult.swift`) with `.ok(tool:result:)` and `.failure(tool:error:)` constructors, plus `asContextJSON()` for feeding results back to the model.

Existing routers: `EventKitToolRouter` (calendar + reminders) and `FileToolRouter` (file read/write via document picker). Both are in `kodai-consumer/Tools/`.

Write actions require user confirmation. The existing pattern uses a `confirm` closure:
```swift
let confirm: (AssistantToolCall) async -> ConfirmDecision
```
where `ConfirmDecision` is `.accept(AssistantToolCall)` or `.cancel`.

## What to do

### 1. Update `EventKitToolRouter.swift`

The existing router handles: `createCalendarEvent`, `createReminder`, `addToList`, `queryCalendar`, `queryReminders`. Update to handle the new tool names:

- Rename internal dispatch to match new `AssistantToolCall` cases (the enum was updated in Phase 0).
- **`calendar_create_event`**: already works, just match the new enum case.
- **`calendar_list_events`**: already works as `queryCalendar`, just match new case. **New requirement**: include `event_id` (the `EKEvent.eventIdentifier`) in each result entry so `calendar_delete_event` can reference it.
- **`calendar_delete_event`**: NEW. Takes an `event_id` string. Use `store.event(withIdentifier:)` to fetch, then `store.remove(event, span: .thisEvent)`. This is a write action — requires confirmation.
- **`reminders_create`**: already works as `createReminder`, match new case. Add `priority` parameter — map "low"→1, "medium"→5, "high"→9 onto `EKReminder.priority`.
- **`reminders_list`**: already works as `queryReminders`, match new case. **New requirement**: include `reminder_id` (the `EKReminder.calendarItemIdentifier`) in each result entry so `reminders_complete` can reference it.
- **`reminders_complete`**: NEW. Takes a `reminder_id` string. Use `store.calendarItem(withIdentifier:)` cast to `EKReminder`, set `isCompleted = true`, save. This is a write action — requires confirmation.
- Remove the old `addToList` case handling (it was just `createReminder` with a list name — `reminders_create` with `list_name` covers it now).

### 2. Update `FileToolRouter.swift`

The existing router handles `saveFile` and `readFile` via the document picker. Update:

- **`files_list`**: NEW. Takes a `path` string. If path starts with "icloud/", resolve to the app's iCloud Drive container URL (`FileManager.default.url(forUbiquityContainerIdentifier: nil)`). If "local/", resolve to the app's documents directory. List directory contents with `FileManager.default.contentsOfDirectory(at:)`. Return file names, sizes, and types.
- **`files_read`**: Update from the old `readFile`. Read a text file at the given path (resolved same as above). Return contents truncated to 8000 characters. This is a read — no confirmation needed.
- **`files_create`**: Update from the old `saveFile`. Write content to the path. For paths outside the sandbox, present the document picker. This is a write — requires confirmation.
- **`files_delete`**: NEW. Delete a file at the path. This is a write — requires confirmation. Use `FileManager.default.removeItem(at:)`.
- Keep the document picker integration for when the user needs to select files outside the sandbox.

### 3. Create `ContactsToolRouter.swift`

New file at `kodai-consumer/Tools/ContactsToolRouter.swift`.

Uses `CNContactStore` from the Contacts framework.

- **`contacts_search`**: Takes a `query` string. Search contacts by name (`CNContact.predicateForContacts(matchingName:)`). Also search by phone and email if the query looks like one. Return up to 10 results, each with: full name, phone numbers, emails, company. This is a read — no confirmation.
- **`contacts_create`**: Takes `first_name` (required), `last_name`, `phone`, `email`, `company`, `notes`. Create a `CNMutableContact`, save via `CNSaveRequest`. This is a write — requires confirmation.
- Request contact access on first use (`CNContactStore().requestAccess(for: .contacts)`). Return structured error if denied.

### 4. Create `ClipboardToolRouter.swift`

New file at `kodai-consumer/Tools/ClipboardToolRouter.swift`.

Uses `UIPasteboard.general`. No permissions needed.

- **`clipboard_read`**: Read `UIPasteboard.general.string`. Return the content or "Clipboard is empty." No confirmation.
- **`clipboard_write`**: Set `UIPasteboard.general.string`. This is a write — requires confirmation (the user should see what's being written to their clipboard). Return "Copied to clipboard."

### 5. Create `NotificationToolRouter.swift`

New file at `kodai-consumer/Tools/NotificationToolRouter.swift`.

Uses `UNUserNotificationCenter`.

- **`notification_schedule`**: Takes `title`, `body`, `trigger_date` (ISO 8601), and optional `identifier`. Parse the trigger_date. If it's in the future, create a `UNCalendarNotificationTrigger` from the date components. Create a `UNNotificationRequest` with the content and trigger. Add via `UNUserNotificationCenter.current().add()`. Return the identifier. This is a write — requires confirmation.
- **`notification_cancel`**: Takes an `identifier`. Remove pending notifications with that identifier via `UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:)`. This is a write — requires confirmation.
- Request notification authorization on first use (`.requestAuthorization(options: [.alert, .sound])`). Return structured error if denied.

### 6. Create `SystemToolRouter.swift`

New file at `kodai-consumer/Tools/SystemToolRouter.swift`.

- **`web_fetch`**: Takes a `url` string. Use `URLSession.shared.data(from:)`. Return the response body as a string, truncated to 4000 characters. Return error for non-2xx status codes or network errors. No confirmation needed (read-only).
- **`open_url`**: Takes a `url` string. Call `await UIApplication.shared.open(url)`. Supports `tel://`, `mailto:`, `maps://`, `https://`, custom deep links. Return success/failure. This is a write (it opens something externally) — requires confirmation.

### 7. Create `ToolRouterDispatch.swift`

New file at `kodai-consumer/Tools/ToolRouterDispatch.swift`.

This is the single entry point. It conforms to `ToolRouter` and routes each `AssistantToolCall` case to the correct domain router.

```swift
struct ToolRouterDispatch: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision
    var onActivity: ((String) -> Void)?

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        // Switch on call, dispatch to the right domain router
        // Inject confirm closure for write actions
        // Skip confirm for read/query actions
    }
}
```

Read/query tools (no confirmation): `calendar_list_events`, `reminders_list`, `contacts_search`, `files_list`, `files_read`, `clipboard_read`, `web_fetch`.

Write tools (require confirmation): everything else.

### 8. Unit tests

Add tests in `kodai-consumerTests/`:
- Test each new router with mock/stub dependencies where possible.
- Test `ToolRouterDispatch` dispatches all 20 tool cases to the correct router.
- Test that read tools don't trigger confirmation, write tools do.

## Important

- Every router returns `ToolResult` — `.ok(tool:result:)` or `.failure(tool:error:)`.
- Every write action goes through the `confirm` closure before executing. If cancelled, return `.failure(tool:, error: "cancelled_by_user")`.
- Permission denials return structured errors, not crashes: `"calendar_access_denied"`, `"contacts_access_denied"`, `"notifications_access_denied"`, etc.
- Do NOT modify UI files. This phase is routers only.
- Verify compile: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build test`
- Do NOT boot or run simulators.
