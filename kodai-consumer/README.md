# kodai-consumer

A private, offline, on-device iOS action agent. Not a chatbot — a command surface. No cloud, no account, no data leaves the phone.

You type a request. The agent plans, calls tools, observes results, and responds with structured action cards — not a wall of text. Think Raycast on macOS, or what Siri should have been.

## What it does

The user types natural language. The agent emits tool calls. Write actions require confirmation. Results appear as action cards in an activity feed.

**Tool surface** (20 tools across 7 domains):

| Domain | Tools | Framework |
|---|---|---|
| Calendar | `calendar_create_event`, `calendar_list_events`, `calendar_delete_event` | EventKit |
| Reminders | `reminders_create`, `reminders_list`, `reminders_complete` | EventKit |
| Contacts | `contacts_search`, `contacts_create` | Contacts.framework |
| Files | `files_list`, `files_read`, `files_create`, `files_delete` | FileManager + UIDocumentPickerViewController |
| Clipboard | `clipboard_read`, `clipboard_write` | UIPasteboard |
| Notifications | `notification_schedule`, `notification_cancel` | UserNotifications |
| System | `web_fetch`, `open_url` | URLSession, UIApplication |

**Hard limits** (iOS sandbox, no jailbreak, no special entitlements):
- Cannot send iMessage/SMS silently (can pre-fill via share sheet)
- Cannot read Mail or Messages inbox
- Cannot change system settings
- Cannot install or remove apps
- File access limited to app sandbox, iCloud Drive, and user-shared folders
- Cannot auto-dial (can pre-fill with `tel://`)
- Cannot execute arbitrary code or shell commands

## Architecture

```
User input (text bar)
  -> SystemPromptBuilder (agent system prompt + tool schemas + datetime context)
  -> RuntimeAgentModel (llama.cpp inference via KodaiCore)
  -> ToolCallParser (native LFM2 format -> JSON -> Pythonic fallback)
  -> ToolCallValidator (typed AssistantToolCall or error)
  -> AgentLoop (multi-turn: infer -> parse -> validate -> execute -> feed result back)
     -> ToolRouter protocol (dispatches to domain routers)
        -> EventKitToolRouter (calendar + reminders)
        -> ContactsToolRouter (contacts)
        -> FileToolRouter (files via sandbox/iCloud/document picker)
        -> ClipboardToolRouter (pasteboard)
        -> NotificationToolRouter (local notifications)
        -> SystemToolRouter (web fetch, open URL)
     -> Confirm card (user reviews write actions before execution)
     -> Action card (result rendered in feed)
  -> ActionStore (SwiftData persistence for feed, upcoming, archive)
```

Multi-step agent loop — the model can chain tool calls (up to 6 steps) before emitting a terminal response. Query tools skip confirmation. Write tools show a confirm card.

## UI

Three-tab layout, bottom tab bar. No hamburger menu, no sidebar. Native and thumb-reachable.

### Feed (home tab)

A vertical activity stream of action cards, with a floating input bar pinned above the tab bar. Not a chat log — an action feed.

Each card has:
- Domain icon (color-coded per tool type)
- One-line summary
- Timestamp
- Status chip: Done, Pending, Failed, Cancelled

User messages appear as compact prompt rows between cards (not bubbles). Agent text responses (clarifications, open answers) appear as plain notes — indented text with subtle background, not bubbles.

Tap a card to expand: shows full details, edit button, related actions.

### Upcoming (second tab)

Grouped timeline: Today, Tomorrow, This Week, Later. Shows all future calendar events and reminders (both agent-created and existing on device). Tap to edit or ask the agent to modify. This is the user's queue.

### Archive (third tab)

Completed actions, reverse chronological, grouped by session. Each session is collapsible — shows what was asked and what was done. Filterable by type: events, reminders, contacts, file ops, other. This is the audit log.

## Model

**LFM 2.5 1.2B Instruct** (Q4_K_M GGUF), running locally via llama.cpp through KodaiCore's `LocalModelRuntime`. Bundled or downloaded on first launch. Cold start ~2-4s on iPhone 14+.

Tool calls use LFM2's native format:
```
<|tool_call_start|>{"name": "calendar_create_event", "arguments": {"title": "Team sync", "start_date": "2026-06-27T14:00:00"}}<|tool_call_end|>
```

Parser falls back through bare JSON and Pythonic formats, tracking confidence via `ParseConfidence` (.native, .json, .pythonic).

## Agent system prompt

See [docs/AGENT_PROMPT.md](docs/AGENT_PROMPT.md) for the full system prompt injected into the model. Key behaviors:
- Prefer action over clarification
- Call tools by emitting JSON `{"tool": "<name>", "parameters": {...}}`
- Chain tool calls, wait for each result
- If a tool fails, explain why and suggest alternatives
- Hard limits are enforced at the router level, not just the prompt
- Timezone confirmed with user on first use, then persisted in user context

## Project structure

```
kodai-consumer/
  Agent/
    AgentLoop.swift              # Multi-step infer -> parse -> validate -> execute loop
    RuntimeAgentModel.swift      # Bridges KodaiCore inference, surfaces status + tokens
    StateAnchor.swift            # Task state injected each turn for model grounding
    ToolResult.swift             # Structured result fed back into context
  Assistant/
    AssistantTool.swift          # Tool names, typed calls, JSON schema catalog
    SystemPromptBuilder.swift    # Agent system prompt with datetime + tool definitions
    ToolCallParser.swift         # 3-format parser with ParseConfidence
    ToolCallValidator.swift      # Validates and types raw tool calls
  Tools/
    EventKitToolRouter.swift     # Calendar + Reminders via EKEventStore
    ContactsToolRouter.swift     # Contacts via CNContactStore
    FileToolRouter.swift         # Files via FileManager + UIDocumentPicker
    ClipboardToolRouter.swift    # UIPasteboard read/write
    NotificationToolRouter.swift # UserNotifications schedule/cancel
    SystemToolRouter.swift       # URLSession fetch + UIApplication openURL
    ToolRouterDispatch.swift     # Routes AssistantToolCall to the right domain router
  Store/
    ActionStore.swift            # SwiftData models for action cards
    ActionCard.swift             # Card data: icon, summary, timestamp, status, details
    SessionGroup.swift           # Groups cards by user session for archive view
  UI/
    FeedView.swift               # Home tab: action card stream + input bar
    ActionCardView.swift         # Single action card (compact + expanded)
    PromptRow.swift              # User message between cards
    AgentNoteView.swift          # Agent text response (not a bubble)
    UpcomingView.swift           # Upcoming tab: grouped timeline
    ArchiveView.swift            # Archive tab: session-grouped history
    InputBar.swift               # Floating text input with send/stop
    ConfirmCardView.swift        # Write action confirmation sheet
    OnboardingView.swift         # First-launch permissions + privacy story
    SplashView.swift             # Wolf constellation splash
    CanvasBackground.swift       # Background canvas
    HapticFeedback.swift         # Haptic feedback
    ThinkingDotsView.swift       # Loading indicator
  AppIntents/
    (existing App Intents for Siri/Shortcuts/Spotlight)
  Resources/
    wolf-points.json             # Splash constellation data
  kodai_consumerApp.swift        # Entry point, SwiftData container, tab bar, onboarding gate
  ConsumerModelFileResolver.swift
  InferenceService.swift
  Info.plist
  kodai_consumer.entitlements
kodai-consumer-widget/
  (existing WidgetKit input widget)
kodai-consumerTests/
  (unit tests)
```

## Key behaviors

- **Confirmation card**: Every write action shows a confirm card before executing. Query/read tools skip confirmation and render results directly as action cards. Tool-specific icons and colors per domain.
- **Action cards**: Results appear in the feed as structured cards, not text. Each card is tappable for details.
- **Agent loop**: Multi-step — the model can chain tool calls. Invalid calls get one silent retry. Budget of 6 steps per task.
- **Auto-retry**: If a tool execution fails (not cancelled by user), retries once automatically.
- **Haptics**: Medium impact on card appear, success notification on confirm, light impact on cancel, error notification on failure.
- **Permissions onboarding**: First-launch flow requests access to each domain with privacy explanations. File and contact access is per-use.
- **Widget**: Input-only widget that deep-links into the app via `kodai://task?q=<query>`.
- **App Intents**: Same tools exposed to Siri, Shortcuts, and Spotlight as an additional surface.

## Dependencies

- **KodaiCore** (local Swift package at `../KodaiCore`) — provides `KodaiKernel` (inference, context, tool schemas) and `KodaiRuntime` (llama.cpp `LocalModelRuntime`)
- **EventKit** — calendar events and reminders
- **Contacts** — contact search and creation
- **UserNotifications** — local notification scheduling
- **WidgetKit** — home screen widget
- **SwiftData** — action card persistence and archive

## Building

Open `kodai-consumer.xcodeproj` in Xcode 26.4+. The project requires:
- iOS 26.4+
- KodaiCore at `../KodaiCore`
- A bundled or downloadable LFM2.5 GGUF model

```
xcodebuild -project kodai-consumer.xcodeproj \
  -scheme kodai-consumer \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build test
```

## Privacy

No data collected. No data shared. No tracking. No network calls (except user-initiated `web_fetch`). Everything runs on-device.
