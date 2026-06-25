# kodai-consumer

A private, offline, on-device AI assistant for iOS. Not a chatbot — an agent. No cloud, no account, no data leaves the phone.

## What it does

You type a request. The model emits a tool call. You confirm. It executes. Done.

**Tools:**
- `create_calendar_event` — creates a calendar event via EventKit
- `create_reminder` — creates a reminder with optional due date
- `add_to_list` — adds an item to a named reminder list (creates the list if needed)
- `save_file` — saves text content to a file via the Files app picker
- `read_file` — reads a file the user selects from the Files app

## Architecture

```
User input
  → SystemPromptBuilder (LFM2 native format + tool schemas)
  → RuntimeAgentModel (llama.cpp inference via KodaiCore)
  → ToolCallParser (native → JSON → Pythonic fallback, returns ParseConfidence)
  → ToolCallValidator (typed AssistantToolCall or error)
  → Confirm card (user reviews, optionally edits, confirms or cancels)
  → EventKitToolRouter / FileToolRouter (executes the action)
  → ActionLogger (SwiftData log, auto-prunes at 100 entries)
```

Single-shot flow — the model is a pure tool-call emitter, never generates user-facing prose.

## Model

**LFM 2.5 1.2B Instruct** (Q4_K_M GGUF), running locally via llama.cpp through KodaiCore's `LocalModelRuntime`. The model is bundled in the app or downloaded on first launch. Cold start is ~2-4s on iPhone 14+; the app preloads the model on launch with a loading indicator.

Tool calls use LFM2's native format:
```
<|tool_call_start|>{"name": "create_reminder", "arguments": {"title": "Buy milk", "due": "2026-06-26T18:00:00"}}<|tool_call_end|>
```

The parser falls back through bare JSON and Pythonic formats if native tokens aren't present, tracking confidence via `ParseConfidence` (.native, .json, .pythonic).

## Project structure

```
kodai-consumer/
├── Agent/
│   ├── AgentLoop.swift          # Multi-step infer→parse→validate→execute loop
│   └── RuntimeAgentModel.swift  # Bridges KodaiCore inference, surfaces status + tokens
├── Assistant/
│   ├── AssistantTool.swift      # Tool names, typed calls, JSON schema catalog
│   ├── SystemPromptBuilder.swift # LFM2 native prompt with datetime + tool defs
│   ├── ToolCallParser.swift     # 3-format parser with ParseConfidence
│   └── ToolCallValidator.swift  # Validates and types raw tool calls
├── Store/
│   └── ActionLog.swift          # SwiftData @Model for action history
├── Tools/
│   ├── EventKitToolRouter.swift # Calendar + Reminders via EKEventStore
│   └── FileToolRouter.swift     # Files app via UIDocumentPickerViewController
├── UI/
│   ├── AssistantController.swift # @Observable controller: prewarm, dispatch, retry, log
│   ├── AssistantView.swift       # Main UI: status, activity log, confirm sheet, file picker
│   ├── ConsumerInputBar.swift    # Text input with send button
│   ├── HapticFeedback.swift      # Haptic feedback for card transitions
│   └── OnboardingView.swift      # First-launch permissions + privacy story
├── ConsumerModelFileResolver.swift
├── InferenceService.swift
└── kodai_consumerApp.swift       # Entry point, SwiftData container, onboarding gate
kodai-consumer-widget/
├── ConsumerWidget.swift          # WidgetKit input widget (small + medium)
└── ConsumerWidgetBundle.swift    # Widget bundle entry point
kodai-consumerTests/              # 26 unit tests
```

## Key behaviors

- **Confirmation card**: Every action shows a confirm card before executing. Tool-specific icons (calendar=red, reminder=blue, list=orange, save=purple, read=teal). Edit button converts fields to inline editors (TextFields, DatePickers). ParseConfidence indicator warns on low-confidence parses.
- **Auto-retry**: If a tool execution fails (not cancelled by user), retries once automatically before surfacing the error.
- **Haptics**: Medium impact on card appear, success notification on confirm, light impact on cancel, error notification on failure.
- **Permissions onboarding**: First-launch flow requests calendar (write-only) and reminders (full) access with privacy explanation. File access is per-use via the document picker.
- **Widget**: Input-only widget that deep-links into the app via `kodai://task?q=<query>`. The widget can't run inference (memory limits).

## Dependencies

- **KodaiCore** (local Swift package at `../KodaiCore`) — provides `KodaiKernel` (inference, context, tool schemas) and `KodaiRuntime` (llama.cpp `LocalModelRuntime`)
- **EventKit** — calendar events and reminders
- **WidgetKit** — home screen widget
- **SwiftData** — action log persistence

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

No data collected. No data shared. No tracking. No network calls. Everything runs on-device.
