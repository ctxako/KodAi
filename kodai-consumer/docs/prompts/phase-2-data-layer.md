# Phase 2: Data Layer — ActionStore

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. It runs a 1.2B model on-device, executes tool calls, and displays results. The app already uses SwiftData (registered in `kodai_consumerApp.swift`). Phases 0-1 expanded the tool system to 20 tools with routers.

The current UI is a single-screen view with ephemeral state — a `summary` string on `AssistantController` that gets overwritten each time. We're rebuilding the UI as an activity feed of persistent action cards. This phase creates the data layer that powers it.

## What to do

### 1. Create `ActionCard.swift`

New file at `kodai-consumer/Store/ActionCard.swift`.

SwiftData `@Model` class representing one action the agent performed (or attempted).

```swift
import Foundation
import SwiftData

@Model
final class ActionCard {
    var id: UUID
    var toolName: String          // e.g. "calendar_create_event"
    var domain: String            // "calendar", "reminders", "contacts", "files", "clipboard", "notifications", "system"
    var kind: String              // "prompt" (user input), "action" (tool result), "note" (agent text response)
    var summary: String           // one-line human-readable: "Team sync — Tomorrow, 2:00 PM"
    var status: String            // "done", "pending", "failed", "cancelled"
    var timestamp: Date
    var details: [String: String] // structured fields for expanded view (title, location, due date, etc.)
    var sessionID: UUID           // groups cards by user session
    var relatedDate: Date?        // for calendar events / reminders: the actual event/reminder date
    var isArchived: Bool          // false in feed, true after session ends

    init(
        toolName: String,
        domain: String,
        kind: String = "action",
        summary: String,
        status: String,
        details: [String: String] = [:],
        sessionID: UUID,
        relatedDate: Date? = nil
    ) {
        self.id = UUID()
        self.toolName = toolName
        self.domain = domain
        self.kind = kind
        self.summary = summary
        self.status = status
        self.timestamp = Date()
        self.details = details
        self.sessionID = sessionID
        self.relatedDate = relatedDate
        self.isArchived = false
    }
}
```

The `kind` field distinguishes:
- `"prompt"` — a user input row (toolName = "user_prompt", domain = "system")
- `"action"` — a tool call result
- `"note"` — an agent text response (clarification, answer) (toolName = "agent_note", domain = "system")

### 2. Create `SessionGroup.swift`

New file at `kodai-consumer/Store/SessionGroup.swift`.

```swift
import Foundation
import SwiftData

@Model
final class SessionGroup {
    var id: UUID
    var prompt: String       // the user's original request
    var startedAt: Date
    var endedAt: Date?

    init(prompt: String) {
        self.id = UUID()
        self.prompt = prompt
        self.startedAt = Date()
    }
}
```

`SessionGroup` and `ActionCard` are linked by `sessionID` (not a SwiftData relationship — just a UUID foreign key, simpler and avoids cascade issues).

### 3. Create `ActionStore.swift`

New file at `kodai-consumer/Store/ActionStore.swift`.

`@Observable` class that wraps a SwiftData `ModelContext` and provides clean methods for the rest of the app.

```swift
import Foundation
import SwiftData
import Observation

@Observable
final class ActionStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // -- Session lifecycle --

    func startSession(prompt: String) -> UUID {
        let session = SessionGroup(prompt: prompt)
        context.insert(session)
        try? context.save()
        return session.id
    }

    func endSession(id: UUID) {
        // Fetch session, set endedAt = Date(), save
    }

    // -- Card creation --

    func logPrompt(text: String, sessionID: UUID) {
        // Insert an ActionCard with kind="prompt", toolName="user_prompt", domain="system"
    }

    func logAction(
        toolName: String,
        domain: String,
        summary: String,
        status: String,
        details: [String: String] = [:],
        sessionID: UUID,
        relatedDate: Date? = nil
    ) {
        // Insert an ActionCard with kind="action"
    }

    func logNote(text: String, sessionID: UUID) {
        // Insert an ActionCard with kind="note", toolName="agent_note", domain="system"
    }

    // -- Queries --

    func feedCards() -> [ActionCard] {
        // Fetch non-archived cards, sorted by timestamp ascending (oldest first, newest at bottom)
    }

    func upcomingCards() -> [ActionCard] {
        // Fetch cards where relatedDate > now, sorted by relatedDate ascending
        // Only kind="action" cards for calendar/reminders domains
    }

    func archiveSessions() -> [(session: SessionGroup, cards: [ActionCard])] {
        // Fetch sessions with endedAt != nil, sorted by startedAt descending
        // For each session, fetch its cards
    }

    func archiveSession(id: UUID) {
        // Set isArchived = true on all cards with this sessionID
        // End the session if not already ended
    }

    // -- Maintenance --

    func pruneOldSessions(keepLast: Int = 200) {
        // Delete sessions (and their cards) beyond the keepLast limit
    }
}
```

Implement all the methods fully — the pseudocode above shows the intent, you write the real SwiftData queries.

### 4. Domain mapping helper

Add a static helper (on `ActionStore` or as a free function) that maps tool names to domains:

```
calendar_create_event, calendar_list_events, calendar_delete_event -> "calendar"
reminders_create, reminders_list, reminders_complete -> "reminders"
contacts_search, contacts_create -> "contacts"
files_list, files_read, files_create, files_delete -> "files"
clipboard_read, clipboard_write -> "clipboard"
notification_schedule, notification_cancel -> "notifications"
web_fetch, open_url -> "web"
respond -> "system"
```

### 5. Wire into `AssistantController.swift`

Update `AssistantController` (at `kodai-consumer/UI/AssistantController.swift`) to use `ActionStore`:

- Add an `ActionStore` property. It needs a `ModelContext` — accept it via init or environment.
- In `run()`:
  - Call `store.startSession(prompt:)` at the start, save the session ID.
  - Call `store.logPrompt(text:sessionID:)` to log the user's input.
  - After each tool result, call `store.logAction(...)` with the tool name, domain, summary, status, and details extracted from the `ToolResult`.
  - If the model emits a text response (not a tool call), call `store.logNote(text:sessionID:)`.
  - Call `store.endSession(id:)` when the task completes.
- The `summary` property can stay for now — it'll be replaced by the feed UI in Phase 3.
- Call `store.pruneOldSessions()` on app launch.

### 6. Register models in `kodai_consumerApp.swift`

Add `ActionCard` and `SessionGroup` to the SwiftData `ModelContainer` schema in `kodai_consumerApp.swift`.

### 7. Tests

Add tests in `kodai-consumerTests/`:

- `ActionStoreTests.swift`:
  - Start a session, log actions, verify `feedCards()` returns them in order.
  - End a session, archive it, verify it appears in `archiveSessions()`.
  - Log a prompt and a note, verify they have correct `kind` values.
  - `upcomingCards()` returns only future-dated calendar/reminder cards.
  - `pruneOldSessions()` removes sessions beyond the limit.

## Important

- Do NOT modify UI views (FeedView, etc.) — that's Phase 3. Only modify `AssistantController` to wire in persistence.
- Use SwiftData `@Query` or `FetchDescriptor` for queries, not raw predicates.
- The `details` dictionary on `ActionCard` stores structured data for the expanded card view. For a calendar event, it might be `["title": "Team sync", "start": "2026-06-27T14:00:00", "location": "Room 4"]`. For a reminder: `["title": "Call dentist", "due": "2026-06-28", "list": "Personal"]`.
- Summary generation: build a human-readable one-liner from the tool result. Examples: "Team sync — Tomorrow, 2:00 PM", "Call dentist — Friday", "Copied to clipboard", "3 events today".
- Verify compile: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build test`
- Do NOT boot or run simulators.
