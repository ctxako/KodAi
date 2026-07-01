# Development Roadmap

Step-by-step build plan for kodai-consumer. Each phase is a self-contained milestone that compiles and can be verified before moving to the next. Phases are ordered by dependency — later phases depend on earlier ones.

Read [README.md](../README.md) for the full architecture and UI spec. Read [AGENT_PROMPT.md](AGENT_PROMPT.md) for the agent system prompt and tool definitions.

---

## Phase 0: Foundation cleanup

**Goal**: Strip the existing codebase to a clean foundation. Remove v1 tool surface, old UI, and stale types. Keep the agent loop, inference bridge, parser, and validator infrastructure.

### Tasks

1. **Expand `AssistantToolName` and `AssistantToolCall`** in KodaiKernel to cover all 20 tools:
   - Calendar: `calendar_create_event`, `calendar_list_events`, `calendar_delete_event`
   - Reminders: `reminders_create`, `reminders_list`, `reminders_complete`
   - Contacts: `contacts_search`, `contacts_create`
   - Files: `files_list`, `files_read`, `files_create`, `files_delete`
   - Clipboard: `clipboard_read`, `clipboard_write`
   - Notifications: `notification_schedule`, `notification_cancel`
   - System: `web_fetch`, `open_url`

2. **Update `ToolCallValidator`** to validate the new tool calls with correct required/optional parameter checks.

3. **Update `SystemPromptBuilder`** to inject the new agent system prompt (from `docs/AGENT_PROMPT.md`) with all 20 tool schemas.

4. **Update `AssistantToolCatalog`** to expose the new tool definitions JSON.

5. **Verify**: Parser and validator tests pass for all 20 tools. `xcodebuild build` succeeds.

### Files touched
- `../KodaiCore/Sources/KodaiKernel/Assistant/` — tool names, call types, routing config
- `kodai-consumer/Assistant/AssistantTool.swift` — re-export updated types
- `kodai-consumer/Assistant/SystemPromptBuilder.swift` — new prompt
- `kodai-consumer/Assistant/ToolCallValidator.swift` — new validation rules
- `kodai-consumerTests/` — update/add tests for all 20 tools

---

## Phase 1: New tool routers

**Goal**: Implement all domain routers behind the `ToolRouter` protocol. Each router is a standalone struct with no UI dependencies.

### Tasks

1. **`ContactsToolRouter`** — new file at `kodai-consumer/Tools/ContactsToolRouter.swift`
   - Uses `CNContactStore` from Contacts.framework
   - `contacts_search`: search by name, phone, or email. Return structured results (name, phone, email, company).
   - `contacts_create`: create a new contact. Return the created contact's name.
   - Request access on first use, return structured error if denied.

2. **`ClipboardToolRouter`** — new file at `kodai-consumer/Tools/ClipboardToolRouter.swift`
   - Uses `UIPasteboard.general`
   - `clipboard_read`: return current pasteboard string content (or "empty").
   - `clipboard_write`: set pasteboard string. Return confirmation.
   - No permissions needed (available to all apps).

3. **`NotificationToolRouter`** — new file at `kodai-consumer/Tools/NotificationToolRouter.swift`
   - Uses `UNUserNotificationCenter`
   - `notification_schedule`: create a `UNTimeIntervalNotificationTrigger` or `UNCalendarNotificationTrigger` from the ISO 8601 trigger_date. Return the identifier.
   - `notification_cancel`: remove pending notification by identifier.
   - Request notification authorization on first use.

4. **`SystemToolRouter`** — new file at `kodai-consumer/Tools/SystemToolRouter.swift`
   - `web_fetch`: `URLSession.shared.data(from:)`, return the response body as text (truncated to 4000 chars). Return error for non-2xx status.
   - `open_url`: `await UIApplication.shared.open(url)`. Return success/failure. Supports `tel://`, `mailto:`, `maps://`, `https://`, and custom app deep links.

5. **Update `EventKitToolRouter`** to handle the new calendar/reminder tool names:
   - Rename internal dispatch from `createCalendarEvent`/`createReminder`/`addToList` to `calendar_create_event`/`reminders_create` etc.
   - Add `calendar_delete_event`: delete by event identifier (returned from `calendar_list_events`).
   - Add `reminders_complete`: fetch reminder by identifier, set `isCompleted = true`, save.
   - `calendar_list_events` returns event IDs in results so `calendar_delete_event` can reference them.
   - `reminders_list` returns reminder IDs in results so `reminders_complete` can reference them.

6. **Update `FileToolRouter`** to handle the new file tool names:
   - `files_list`: list contents of a directory path. Resolve "icloud/" prefix to the iCloud Drive container, "local/" to the app sandbox documents directory.
   - `files_read`: read a text file and return its contents (truncated to 8000 chars).
   - `files_create`: create or overwrite a text file.
   - `files_delete`: delete a file. This is a write action and requires confirmation.
   - Keep the document picker for user-initiated file selection where sandbox rules require it.

7. **`ToolRouterDispatch`** — new file at `kodai-consumer/Tools/ToolRouterDispatch.swift`
   - Single struct conforming to `ToolRouter`.
   - Routes each `AssistantToolCall` case to the correct domain router.
   - Injects the `confirm` closure for write actions, skips it for reads/queries.
   - This is the only `ToolRouter` the `AgentLoop` and `AssistantController` interact with.

### Verification
- Unit tests for each router with mock data where possible (mock `CNContactStore`, mock `UNUserNotificationCenter`).
- `ToolRouterDispatch` integration test: dispatch a call for each of the 20 tools, verify correct router is invoked.
- `xcodebuild build` succeeds.

### Files created
- `kodai-consumer/Tools/ContactsToolRouter.swift`
- `kodai-consumer/Tools/ClipboardToolRouter.swift`
- `kodai-consumer/Tools/NotificationToolRouter.swift`
- `kodai-consumer/Tools/SystemToolRouter.swift`
- `kodai-consumer/Tools/ToolRouterDispatch.swift`

### Files modified
- `kodai-consumer/Tools/EventKitToolRouter.swift`
- `kodai-consumer/Tools/FileToolRouter.swift`

---

## Phase 2: Data layer — ActionStore

**Goal**: SwiftData persistence for action cards, sessions, and the upcoming/archive views.

### Tasks

1. **`ActionCard` model** — new file at `kodai-consumer/Store/ActionCard.swift`
   - SwiftData `@Model` class.
   - Properties:
     - `id: UUID`
     - `toolName: String` — the tool that produced this card
     - `domain: String` — "calendar", "reminders", "contacts", "files", "clipboard", "notifications", "system"
     - `summary: String` — one-line human-readable summary
     - `status: String` — "done", "pending", "failed", "cancelled"
     - `timestamp: Date`
     - `details: [String: String]` — structured key-value pairs for expanded view
     - `sessionID: UUID` — groups cards by user session
     - `relatedDate: Date?` — for calendar events/reminders: the event/reminder date (used by Upcoming tab)
     - `isArchived: Bool` — false while in feed, true after session ends or is dismissed

2. **`SessionGroup` model** — new file at `kodai-consumer/Store/SessionGroup.swift`
   - SwiftData `@Model` class.
   - Properties:
     - `id: UUID`
     - `prompt: String` — the user's original request
     - `startedAt: Date`
     - `endedAt: Date?`
   - Relationship: one-to-many with `ActionCard` via `sessionID`.

3. **`ActionStore`** — new file at `kodai-consumer/Store/ActionStore.swift`
   - `@Observable` class that wraps SwiftData queries.
   - Methods:
     - `logAction(tool:domain:summary:status:details:sessionID:relatedDate:)` — creates an `ActionCard`
     - `startSession(prompt:) -> UUID` — creates a `SessionGroup`, returns its ID
     - `endSession(id:)` — sets `endedAt`
     - `feedCards() -> [ActionCard]` — non-archived, reverse chronological
     - `upcomingCards() -> [ActionCard]` — cards with `relatedDate` in the future, grouped by day
     - `archiveSessions() -> [SessionGroup]` — completed sessions with their cards
     - `archiveSession(id:)` — marks all cards in a session as archived
     - `pruneOldSessions(keepLast: Int = 200)` — auto-prune

4. **Wire `ActionStore` into `AssistantController`**:
   - On `start()`: create a session, store the session ID.
   - On each tool result: log an `ActionCard`.
   - On task completion: end the session.
   - Replace the existing `summary` string with the latest `ActionCard` from the current session.

5. **Register SwiftData models** in `kodai_consumerApp.swift` model container.

### Verification
- Unit tests for `ActionStore` CRUD operations.
- Cards persist across app launches.
- `xcodebuild build test` succeeds.

### Files created
- `kodai-consumer/Store/ActionCard.swift`
- `kodai-consumer/Store/SessionGroup.swift`
- `kodai-consumer/Store/ActionStore.swift`

### Files modified
- `kodai-consumer/UI/AssistantController.swift`
- `kodai-consumer/kodai_consumerApp.swift`

---

## Phase 3: Feed tab UI

**Goal**: Replace the current single-screen AssistantView with the Feed tab — an action card stream with the floating input bar.

### Tasks

1. **`ActionCardView`** — new file at `kodai-consumer/UI/ActionCardView.swift`
   - Renders one `ActionCard`.
   - Compact state: domain icon (color-coded), one-line summary, timestamp, status chip.
   - Expanded state (on tap): full detail fields, edit button (future), related actions.
   - Status chip colors: Done=green, Pending=blue, Failed=red, Cancelled=gray.
   - Domain icon mapping:
     - calendar: `calendar.badge.plus` / red
     - reminders: `checklist` / blue
     - contacts: `person.crop.circle` / green
     - files: `doc.text` / purple
     - clipboard: `doc.on.clipboard` / orange
     - notifications: `bell.badge` / yellow
     - system: `globe` / gray

2. **`PromptRow`** — new file at `kodai-consumer/UI/PromptRow.swift`
   - Renders user messages between cards.
   - Compact: small text, leading-aligned, subtle foreground color. Not a bubble.

3. **`AgentNoteView`** — new file at `kodai-consumer/UI/AgentNoteView.swift`
   - Renders agent text responses (clarifications, open-ended answers).
   - Indented text with subtle background. Not a bubble.

4. **`FeedView`** — new file at `kodai-consumer/UI/FeedView.swift`
   - Main content: `ScrollView` with `LazyVStack` of `ActionCardView`, `PromptRow`, and `AgentNoteView` items, ordered reverse chronologically (newest at bottom, auto-scrolls).
   - Floating `InputBar` pinned above the tab bar.
   - Thinking indicator (existing `ThinkingDotsView`) appears at the bottom of the feed while the agent is working.
   - Pull to load older cards (if feed is long).

5. **`InputBar`** — refactor `ConsumerInputBar.swift` into `kodai-consumer/UI/InputBar.swift`
   - Same functionality: text field, send button, stop button while generating.
   - Styled to float above the tab bar with backdrop blur.

6. **Update `ConfirmCardView`** — refactor `SimpleConfirmView` into `kodai-consumer/UI/ConfirmCardView.swift`
   - Expand to cover all 20 tools (icons, colors, detail fields).
   - Keep the sheet presentation model.

7. **Wire the feed**: `AssistantController` populates the feed via `ActionStore`. Each tool result creates an `ActionCard` that appears in the feed. User input creates a `PromptRow` entry. Agent text creates an `AgentNoteView` entry.

### Verification
- Feed displays action cards from mock data.
- Typing a request produces cards in the feed.
- Confirm sheet appears for write actions.
- Query results appear as cards (no confirmation).
- Haptics fire at correct moments.
- Compile-only build succeeds.

### Files created
- `kodai-consumer/UI/ActionCardView.swift`
- `kodai-consumer/UI/PromptRow.swift`
- `kodai-consumer/UI/AgentNoteView.swift`
- `kodai-consumer/UI/FeedView.swift`

### Files modified/replaced
- `kodai-consumer/UI/ConsumerInputBar.swift` -> `kodai-consumer/UI/InputBar.swift`
- `kodai-consumer/UI/AssistantView.swift` -> removed (replaced by tab bar + FeedView)
- `kodai-consumer/UI/AssistantController.swift` — updated to drive feed

---

## Phase 4: Upcoming + Archive tabs

**Goal**: Add the second and third tabs for timeline and history views.

### Tasks

1. **`UpcomingView`** — new file at `kodai-consumer/UI/UpcomingView.swift`
   - Queries `ActionStore.upcomingCards()` plus live EventKit data (existing calendar events and reminders not created by the agent).
   - Grouped sections: Today, Tomorrow, This Week, Later.
   - Each row: domain icon, title, date/time, source indicator (agent-created vs existing).
   - Tap to expand details. Long-press to ask the agent to modify ("Hey, reschedule this").
   - Empty state: "Nothing coming up."

2. **`ArchiveView`** — new file at `kodai-consumer/UI/ArchiveView.swift`
   - Queries `ActionStore.archiveSessions()`.
   - Grouped by session. Each session header: the user's prompt + timestamp, collapsible.
   - Under each session: the action cards from that session.
   - Filter bar at top: All, Events, Reminders, Contacts, Files, Other.
   - Empty state: "No history yet."

3. **Tab bar** — update `kodai_consumerApp.swift`
   - Bottom `TabView` with 3 tabs:
     - Feed (house icon) — `FeedView`
     - Upcoming (calendar icon) — `UpcomingView`
     - Archive (clock.arrow.circlepath icon) — `ArchiveView`
   - Input bar only visible on Feed tab.
   - Dark mode by default.

4. **Session lifecycle**: when a task completes and the user starts a new one, the previous session's cards move to archive after a delay (or on next app launch). The feed always shows the current and recent sessions.

### Verification
- Tab bar navigates between all three views.
- Upcoming tab shows future events/reminders.
- Archive tab shows completed sessions with collapsible groups.
- Filter works in archive.
- Compile-only build succeeds.

### Files created
- `kodai-consumer/UI/UpcomingView.swift`
- `kodai-consumer/UI/ArchiveView.swift`

### Files modified
- `kodai-consumer/kodai_consumerApp.swift`

---

## Phase 5: Permissions + onboarding

**Goal**: Update the onboarding flow to cover all new domains and ensure graceful degradation when permissions are denied.

### Tasks

1. **Update `OnboardingView`**:
   - Permissions cards for: Calendar, Reminders, Contacts, Notifications, Files (explained as per-use).
   - Each card: icon, one-line explanation, privacy note, grant button.
   - "All on-device, nothing leaves your phone" banner at top.
   - Skip button — the app works with zero permissions, tools just return access-denied errors that the agent handles gracefully.

2. **Settings / Context tab** (optional, can be a sheet from Feed):
   - Shows what the agent knows: default calendar, timezone, connected folder paths, reminder lists.
   - Editable fields for each.
   - Permission status indicators (granted / denied / not requested).
   - Link to iOS Settings for each domain.

3. **Graceful degradation**: each tool router checks permission status and returns a structured error if denied. The agent receives the error and explains it to the user. No crashes, no silent failures.

### Verification
- Fresh install shows onboarding.
- Granting/denying each permission works.
- Denied permissions produce clear agent responses.
- Compile-only build succeeds.

### Files modified
- `kodai-consumer/UI/OnboardingView.swift`

---

## Phase 6: App Intents update

**Goal**: Expose all new tools to Siri, Shortcuts, and Spotlight.

### Tasks

1. **Expand `ToolAppIntents.swift`** with intents for the new tools:
   - `SearchContactsIntent`, `CreateContactIntent`
   - `ScheduleNotificationIntent`, `CancelNotificationIntent`
   - `ReadClipboardIntent`, `WriteClipboardIntent`
   - `ListFilesIntent`, `DeleteFileIntent`
   - `FetchWebIntent`, `OpenURLIntent`
   - `ListEventsIntent`, `DeleteEventIntent`
   - `ListRemindersIntent`, `CompleteReminderIntent`

2. **Update `ToolAppEntities.swift`** with result entities for new tool types:
   - `ContactEntity`, `NotificationEntity`, `FileEntity`

3. **Update `KodaiAppShortcuts.swift`** with spoken phrases for new tools.

4. **Update `ToolIntentSupport.swift`** — shared executor handles all 20 tools.

### Verification
- All intents appear in Shortcuts app.
- Siri can invoke representative tools via spoken phrases.
- Compile-only build succeeds.

### Files modified
- `kodai-consumer/AppIntents/ToolAppIntents.swift`
- `kodai-consumer/AppIntents/ToolAppEntities.swift`
- `kodai-consumer/AppIntents/KodaiAppShortcuts.swift`
- `kodai-consumer/AppIntents/ToolIntentSupport.swift`

---

## Phase 7: Tests + polish

**Goal**: Full test coverage, edge cases, and UI polish.

### Tasks

1. **Unit tests for all 20 tools** — parser, validator, and router tests for each tool.
2. **Agent loop tests** — multi-step scenarios: chain 3 tools, handle mid-chain failure, budget exceeded.
3. **ActionStore tests** — CRUD, session lifecycle, archive, prune.
4. **UI tests** — basic flow: type request, see card appear, confirm write, verify feed.
5. **Edge cases**:
   - All permissions denied — agent still responds with explanations.
   - Model times out — watchdog fires, user sees "try again."
   - Tool returns unexpected data — validator catches it, error card appears.
   - Empty states for all three tabs.
6. **Haptic audit** — verify all haptic events fire at the right moments.
7. **Dark mode audit** — all views render correctly in dark mode (the only mode).
8. **Accessibility** — VoiceOver labels on action cards, input bar, tab bar, confirm sheet.

### Verification
- `xcodebuild build test` passes all tests.
- No warnings.
- Compile-only build succeeds on device target.

---

## What's NOT in scope (separate tracks)

- Health data (HealthKit) — requires careful privacy handling, separate entitlement
- HomeKit — requires physical devices for testing
- Photos (PhotoKit) — read + add only, no delete
- Multi-turn Siri dialogue
- Cloud sync or backup
- Model download/update system
- Widget expansion beyond input-only
