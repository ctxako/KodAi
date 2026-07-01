# Phase 3: Feed Tab UI

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. It runs a 1.2B model on-device, executes tool calls against iOS frameworks, and persists results as `ActionCard` objects in SwiftData (via `ActionStore`). Phases 0-2 built the tool system, routers, and data layer.

The current UI is a single-screen `AssistantView.swift` with an input bar and ephemeral status text. We're replacing it with an activity feed of action cards — like Raycast, not a chatbot.

The app uses SwiftUI, targets iOS 26.4+, and is dark-mode only.

## What the Feed tab looks like

A vertical stream of action cards with a floating input bar at the bottom. Not a chat — an activity stream.

**Three types of entries in the feed** (determined by `ActionCard.kind`):

1. **Action cards** (`kind == "action"`) — tool results
   - Compact: domain icon (color-coded) | one-line summary | timestamp | status chip
   - Tappable to expand: shows full detail fields
   - Status chips: Done (green), Pending (blue), Failed (red), Cancelled (gray)

2. **Prompt rows** (`kind == "prompt"`) — user messages
   - Compact, leading-aligned, subtle foreground color
   - NOT a chat bubble. Small, understated.

3. **Agent notes** (`kind == "note"`) — agent text responses
   - Indented text with subtle background (ultraThinMaterial)
   - NOT a chat bubble. Plain note styling.

**Domain icon + color mapping:**
- calendar: `calendar.badge.plus` / red
- reminders: `checklist` / blue
- contacts: `person.crop.circle` / green
- files: `doc.text` / purple
- clipboard: `doc.on.clipboard` / orange
- notifications: `bell.badge` / yellow
- system/web: `globe` / gray

**Feed behavior:**
- Newest entries at the bottom, auto-scrolls to bottom on new entries
- Thinking indicator (use existing `ThinkingDotsView`) appears at bottom while agent works
- Empty state: centered wolf icon or minimal "What would you like to do?" text

## What to do

### 1. Create `ActionCardView.swift`

New file at `kodai-consumer/UI/ActionCardView.swift`.

Renders one `ActionCard` where `kind == "action"`.

**Compact state** (default):
```
[icon]  Summary text here              2:30 PM  [Done]
```
- Leading icon: SF Symbol for the domain, colored per domain
- Summary: `.callout` font, primary color, single line
- Timestamp: `.caption2`, secondary color
- Status chip: small capsule with colored text

**Expanded state** (on tap):
- Shows all `details` dictionary entries as key-value rows
- Each row: key in `.caption` secondary, value in `.callout` primary
- Subtle divider between compact and expanded sections
- Animate expansion with `.spring`

Use a `@State private var isExpanded = false` toggle.

Container: `RoundedRectangle(cornerRadius: 14)` with `.ultraThinMaterial` background. Padding 12 horizontal, 10 vertical.

### 2. Create `PromptRow.swift`

New file at `kodai-consumer/UI/PromptRow.swift`.

Renders one `ActionCard` where `kind == "prompt"`.

- Leading-aligned text
- `.subheadline` font, `.secondary.opacity(0.7)` color
- No background, no bubble, no border
- Small vertical padding (4pt)
- The text is the card's `summary` field (which contains the user's input)

### 3. Create `AgentNoteView.swift`

New file at `kodai-consumer/UI/AgentNoteView.swift`.

Renders one `ActionCard` where `kind == "note"`.

- Leading-aligned text
- `.callout` font, `.primary` color
- Background: `.ultraThinMaterial` with `RoundedRectangle(cornerRadius: 10)`, subtle
- 12pt padding inside, 4pt leading indent
- The text is the card's `summary` field

### 4. Create `FeedView.swift`

New file at `kodai-consumer/UI/FeedView.swift`.

The main Feed tab content.

Structure:
```swift
ZStack(alignment: .bottom) {
    // Background
    CanvasBackground()

    // Feed content
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(cards) { card in
                    switch card.kind {
                    case "prompt": PromptRow(card: card)
                    case "note": AgentNoteView(card: card)
                    default: ActionCardView(card: card)
                    }
                }

                if controller.isRunning {
                    // Thinking indicator at bottom
                    ThinkingDotsView()
                        .padding()
                        .id("bottom")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 80) // Space for input bar
        }
        .onChange(of: cards.count) {
            // Auto-scroll to bottom
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    // Floating input bar
    InputBar(...)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
}
```

`cards` comes from `ActionStore.feedCards()` — either via `@Query` or by observing the store.

### 5. Refactor input bar

Rename `kodai-consumer/UI/ConsumerInputBar.swift` to `kodai-consumer/UI/InputBar.swift` (or just update it in place).

Same functionality as the existing `ConsumerInputBar`:
- Text field with placeholder "What would you like to do?"
- Send button (arrow icon) — enabled when text is non-empty and model is ready
- Stop button — shown while generating
- Backdrop blur to float above content

### 6. Update confirm sheet

The existing `SimpleConfirmView` is embedded in `AssistantView.swift`. Extract it to `kodai-consumer/UI/ConfirmCardView.swift` and expand it to cover all 20 tools:

**Icon + color mapping** (same as domain mapping above, but specific per tool for the confirm sheet title):
- `calendar_create_event`: "New calendar event"
- `calendar_delete_event`: "Delete event"
- `reminders_create`: "New reminder"
- `reminders_complete`: "Complete reminder"
- `contacts_create`: "New contact"
- `files_create`: "Save file"
- `files_delete`: "Delete file"
- `clipboard_write`: "Copy to clipboard"
- `notification_schedule`: "Schedule notification"
- `notification_cancel`: "Cancel notification"
- `open_url`: "Open link"

Keep the existing confirm/cancel button layout. Keep the ParseConfidence warning for low-confidence parses.

### 7. Update `AssistantController.swift`

Modify `AssistantController` to drive the feed:

- In `run()`: the store already logs prompts, actions, and notes (wired in Phase 2). The controller's job is now to:
  - Set `isRunning` for the thinking indicator
  - Handle confirmation sheets (existing logic)
  - Handle file picker sheets (existing logic)
  - Remove the `summary` property — results are cards now, not a summary string
- Keep the deep link handler (`onOpenURL`), App Intent handler, and model prewarm.
- Keep the watchdog timeout.

### 8. Replace `AssistantView.swift`

The old `AssistantView` becomes unnecessary — `FeedView` replaces it. Either:
- Gut `AssistantView.swift` and make it just wrap `FeedView` with the confirmation/file-picker sheets, OR
- Delete `AssistantView.swift` and move the sheet modifiers into `FeedView`

The sheets (confirm card, file picker) should be presented from wherever `FeedView` lives. The `controller` drives them via `pendingConfirmation` and `pendingFilePicker`.

### 9. Update `kodai_consumerApp.swift`

For now, the app entry point should show `FeedView` (wrapped with sheets) instead of `AssistantView`. The tab bar comes in Phase 4 — for now just the feed.

Keep: onboarding gate, SwiftData container, deep link handler.

## Important

- Dark mode only (`.preferredColorScheme(.dark)` on the root view).
- All animations use `.smooth(duration: 0.3)` or `.spring` — no jarring transitions.
- Keep existing haptics: `HapticFeedback.send()` on send, `.confirm()` on confirm, `.cancel()` on cancel, `.error()` on failure, `.cardAppear()` on card appear, `.success()` on success.
- The feed should feel fast — `LazyVStack` for performance, minimal view overhead per card.
- Do NOT implement the Upcoming or Archive tabs — that's Phase 4.
- Verify compile: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Do NOT boot or run simulators.
