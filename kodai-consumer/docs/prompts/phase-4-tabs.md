# Phase 4: Upcoming + Archive Tabs

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. Phases 0-3 built the tool system, routers, data layer (`ActionStore` with `ActionCard` and `SessionGroup` SwiftData models), and the Feed tab (`FeedView` with action cards, prompt rows, and agent notes).

The app currently shows just the Feed. Now we add the tab bar and two more tabs: Upcoming (timeline of future events/reminders) and Archive (session history).

The app uses SwiftUI, targets iOS 26.4+, and is dark-mode only. Background is `CanvasBackground()`.

## What to do

### 1. Create the tab bar in `kodai_consumerApp.swift`

Replace the current single-view layout with a `TabView` at the app root (after the onboarding gate):

```swift
TabView {
    Tab("Feed", systemImage: "house.fill") {
        FeedView()
    }
    Tab("Upcoming", systemImage: "calendar") {
        UpcomingView()
    }
    Tab("Archive", systemImage: "clock.arrow.circlepath") {
        ArchiveView()
    }
}
.preferredColorScheme(.dark)
```

The input bar should only be visible on the Feed tab (it's already embedded in `FeedView`).

Keep: onboarding gate, SwiftData container, deep link handler, App Intent inbox drain.

### 2. Create `UpcomingView.swift`

New file at `kodai-consumer/UI/UpcomingView.swift`.

A grouped timeline of future events and reminders.

**Data sources:**
1. `ActionCard` entries from `ActionStore.upcomingCards()` — agent-created events/reminders with a `relatedDate` in the future
2. Live EventKit data — existing calendar events and reminders NOT created by the agent. Query `EKEventStore` directly for the next 14 days of events and pending reminders.

Merge both sources into a single timeline, deduplicated (if an agent-created event also exists in EventKit, show it once with an "agent-created" indicator).

**Grouped sections:**
- **Today** — items with relatedDate = today
- **Tomorrow** — items with relatedDate = tomorrow
- **This Week** — items within the next 7 days (excluding today/tomorrow)
- **Later** — items beyond this week

Each section header: bold title, item count.

**Each row:**
- Domain icon (calendar=red, reminders=blue) | Title | Date/time | Source indicator
- Source indicator: small tag or icon showing "via kodai" for agent-created, nothing for native
- Tap to expand: shows full details
- The row style should match `ActionCardView` — same material background, same corner radius, same padding

**Empty state:** Centered text "Nothing coming up." with a calendar icon above it, secondary color.

**Refresh:** Pull-to-refresh to re-query EventKit.

### 3. Create `ArchiveView.swift`

New file at `kodai-consumer/UI/ArchiveView.swift`.

Completed sessions with their action cards, grouped by session.

**Data source:** `ActionStore.archiveSessions()` — returns sessions with `endedAt != nil`, sorted by `startedAt` descending, each with their cards.

**Layout:**

Top: filter bar (horizontal scroll of capsule buttons):
- All (default), Events, Reminders, Contacts, Files, Other
- Active filter highlighted with accent color
- Filtering limits which cards are shown within sessions (sessions with zero matching cards are hidden)

Below: `LazyVStack` of session groups.

**Each session group:**
- Header: the user's prompt text (`.subheadline`, primary color) + timestamp (`.caption2`, secondary)
- Collapsible (tap header to expand/collapse, default expanded for recent, collapsed for older)
- Under the header: the session's `ActionCard` entries rendered with `ActionCardView` (compact only, no expand)
- Divider between sessions

**Empty state:** Centered text "No history yet." with a clock icon above it, secondary color.

**Auto-archive:** When a new session starts on the Feed tab, the previous session's cards should be marked as archived (this logic is in `AssistantController` / `ActionStore`). Verify this works — cards should move from Feed to Archive when a new task begins.

### 4. Session lifecycle

Make sure the session lifecycle works end-to-end:

1. User types a request on Feed → `AssistantController` calls `store.startSession(prompt:)` → new session starts
2. Tool results log cards to the session → cards appear in Feed
3. Task completes → `store.endSession(id:)` called
4. User starts a new task → previous session's cards are archived (`store.archiveSession(id:)`) → they disappear from Feed, appear in Archive
5. Cards with `relatedDate` in the future appear in Upcoming regardless of archive status

If this lifecycle isn't fully wired from Phase 2, wire it now.

### 5. Navigation polish

- Tab bar should have a subtle `.ultraThinMaterial` background, not opaque
- Active tab icon uses accent color, inactive uses `.secondary`
- Each tab remembers scroll position independently
- Deep links (`kodai://task?q=...`) should switch to the Feed tab and populate the input bar

## Important

- Dark mode only.
- `CanvasBackground()` behind each tab's content (or behind the `TabView` itself).
- Keep all existing functionality: input bar, confirm sheets, file picker, haptics, deep links, App Intents.
- The Upcoming tab queries EventKit directly — it needs the same `EKEventStore` instance used by `EventKitToolRouter`. Use the existing shared store pattern.
- Do NOT modify the tool routers, data models, or agent loop. This phase is UI only.
- Verify compile: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Do NOT boot or run simulators.
