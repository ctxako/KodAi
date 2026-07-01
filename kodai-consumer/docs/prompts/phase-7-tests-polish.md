# Phase 7: Tests + Polish

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. Phases 0-6 rebuilt the app: 20 tools, domain routers, SwiftData persistence (`ActionCard`/`SessionGroup`/`ActionStore`), three-tab UI (Feed/Upcoming/Archive), onboarding, and App Intents.

The existing test suite is in `kodai-consumerTests/` with files like `ToolCallParserTests.swift`, `ToolCallValidatorTests.swift`, `AgentLoopTests.swift`, `SystemPromptBuilderTests.swift`, and `kodai_consumerTests.swift`. Some may be outdated from the v1 tool surface.

This phase brings test coverage up to date and polishes the app.

## What to do

### 1. Update and expand unit tests

**`ToolCallParserTests.swift`** — verify the parser handles all 20 tool names in all three formats:

For each format (native `<|tool_call_start|>...<|tool_call_end|>`, bare JSON, Pythonic), test at least:
- `calendar_create_event` with all parameters
- `contacts_search` with query
- `clipboard_read` with no parameters
- `notification_schedule` with trigger_date
- `web_fetch` with url
- `open_url` with url
- `files_delete` with path
- `reminders_complete` with reminder_id

Verify `ParseConfidence` is set correctly for each format.

**`ToolCallValidatorTests.swift`** — validate all 20 tools:

For each tool, test:
- Valid call with all required params → `.success`
- Missing a required param → `.failure` with descriptive error
- Extra/unknown params → still `.success` (lenient)
- Optional params omitted → `.success` with nil values
- Date parsing: valid ISO 8601 → Date, invalid string → `.failure`

**`AgentLoopTests.swift`** — multi-step agent scenarios:

- **Single tool**: user says "set a reminder for Friday" → model emits `reminders_create` → router returns ok → loop completes
- **Chained tools**: user says "check my calendar for tomorrow and create a reminder to prep" → model emits `calendar_list_events` → result fed back → model emits `reminders_create` → loop completes with 2 steps
- **Mid-chain failure**: first tool succeeds, second tool fails → loop records error step, continues if model emits another call
- **Budget exceeded**: model emits 7 tool calls → loop stops at 6 with `.budgetExceeded`
- **Invalid call + retry**: model emits bad JSON → validator rejects → retry message sent → model emits valid call → succeeds
- **Respond tool**: model emits `respond` → loop returns completed with the message text
- **All tools mock**: use the existing `AgentModel` and `ToolRouter` protocol mocks

**`SystemPromptBuilderTests.swift`**:

- Verify all 20 tool names appear in the built prompt string
- Verify current datetime is injected
- Verify the prompt contains the hard limits section
- Verify the tool calling format instruction is present

**`ActionStoreTests.swift`** — NEW:

- `startSession` creates a `SessionGroup` and returns its ID
- `logPrompt`, `logAction`, `logNote` create cards with correct `kind` values
- `feedCards()` returns non-archived cards in timestamp order
- `upcomingCards()` returns only future-dated calendar/reminder cards
- `endSession` sets `endedAt`
- `archiveSession` marks all session cards as `isArchived = true`
- `archiveSessions()` returns ended sessions with their cards
- `pruneOldSessions` removes sessions beyond the limit
- Cards persist after save (use in-memory SwiftData container for tests)

**`ToolRouterDispatchTests.swift`** — NEW:

- Dispatch each of the 20 tool call cases → verify the correct domain router is invoked (use mock routers)
- Verify read tools don't trigger the confirm closure
- Verify write tools do trigger the confirm closure
- Verify cancelled confirmation returns `.failure(error: "cancelled_by_user")`

### 2. Edge case coverage

Add tests or verify handling for:

- **All permissions denied**: every tool router returns a structured error. The agent receives it and generates a note explaining the issue. No crashes.
- **Model timeout**: the watchdog in `AssistantController` fires after 45 seconds. Verify the task cancels cleanly and the UI resets.
- **Empty states**: Feed with no cards, Upcoming with no future items, Archive with no sessions — all show their empty state views without crashes.
- **Rapid input**: user sends a request while one is already running → second request is ignored (the `guard !isRunning` check).
- **Deep link while running**: `kodai://task?q=...` received during active task → queued or ignored, not crashed.
- **Invalid tool result**: router returns unexpected fields → the card still renders with whatever data is available.
- **Large result**: `web_fetch` returns a huge page → truncated to 4000 chars, card renders fine.
- **No calendars/reminder lists**: EventKit has no writable calendars → structured error, not crash.

### 3. Accessibility audit

Add VoiceOver labels to key interactive elements:

- **Action cards**: `.accessibilityLabel("\(summary), \(status), \(domain)")` — e.g., "Team sync, Done, calendar"
- **Status chips**: `.accessibilityLabel(status)` — "Done", "Pending", "Failed"
- **Input bar**: text field has `.accessibilityLabel("What would you like to do?")`, send button has `.accessibilityLabel("Send")`, stop button has `.accessibilityLabel("Stop")`
- **Tab bar**: each tab has its label (SwiftUI handles this automatically with `Tab("Feed", ...)`
- **Confirm sheet**: confirm button `.accessibilityLabel("Confirm action")`, cancel button `.accessibilityLabel("Cancel")`
- **Onboarding permission cards**: each card has `.accessibilityLabel("\(domain), \(explanation)")` 

### 4. Haptic audit

Verify all haptic events fire correctly. The haptics are in `kodai-consumer/UI/HapticFeedback.swift`. Confirm these trigger at the right moments:

- `HapticFeedback.send()` — when user taps Send
- `HapticFeedback.cardAppear()` — when a new action card appears in the feed
- `HapticFeedback.confirm()` — when user confirms a write action
- `HapticFeedback.cancel()` — when user cancels a confirmation
- `HapticFeedback.success()` — when a tool execution succeeds
- `HapticFeedback.error()` — when a tool execution fails or the model can't parse

If any haptic is missing from a UI flow, add it.

### 5. Visual polish

- **Dark mode**: verify all views render correctly. Check for any hardcoded light-mode colors.
- **Material backgrounds**: all cards use `.ultraThinMaterial`. Verify contrast is readable.
- **Typography**: verify font sizes are consistent — `.callout` for card summaries, `.caption2` for timestamps, `.subheadline` for section headers.
- **Animations**: verify `.smooth(duration: 0.3)` on card appear/disappear, `.spring` on card expand, no jarring transitions.
- **Status bar**: light content (white text) — already handled by `.preferredColorScheme(.dark)`.

### 6. Compile and test

Run the full build + test suite:

```
xcodebuild -project kodai-consumer.xcodeproj \
  -scheme kodai-consumer \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build test
```

Fix any warnings. Fix any test failures. Verify zero warnings in the build output.

## Important

- Do NOT add features or modify behavior. This phase is tests, edge cases, accessibility, and polish only.
- Use in-memory SwiftData containers for store tests (not on-disk).
- Mock `EKEventStore`, `CNContactStore`, `UNUserNotificationCenter` in router tests where possible. For things that can't be mocked, test the logic around the framework calls.
- Do NOT boot or run simulators for manual testing. Compile-only builds + unit tests.
