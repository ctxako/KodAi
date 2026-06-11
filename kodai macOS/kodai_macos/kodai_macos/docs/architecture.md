# Kodai macOS — Architecture

## Overview

Kodai is a single-window macOS app. All state is managed by one central `ChatViewModel` that coordinates between the UI, the on-device language model, and SwiftData persistence. There is no networking — every AI call goes through Apple's `LanguageModelSession`.

## Data flow

```
User types in ComposerView
  → ChatViewModel.send(context:)
      → ChatViewModel.runModel(context:)
          → KodaiModel.streamResponse(to:mode:history:onPartial:)
              → LanguageModelSession.streamResponse(to:)
                  → partial chunks arrive via async for loop
                  → onPartial callback updates messages[] every ~35ms
          → on completion: saves final message to SwiftData
          → updates estimatedContextPercent
```

## Files and responsibilities

| File | Responsibility |
|---|---|
| `kodai_macosApp.swift` | App entry point, SwiftData `ModelContainer` setup |
| `ContentView.swift` | Root layout: sidebar + chat area + composer, wires everything together |
| `chatviewmodel.swift` | `ChatViewModel` — all business logic, owns `KodaiModel` and drives SwiftData ops |
| `kodaimodel.swift` | `KodaiModel` — thin wrapper around `LanguageModelSession`, handles streaming and availability check |
| `kodaichatsession.swift` | SwiftData models: `KodaiChatSession` and `KodaiChatMessage` |
| `outputmode.swift` | `OutputMode` enum — the five modes (Chat, Organize, Summarize, Checklist, Debug) with their system prompts |
| `composerview.swift` | Text input area at the bottom of the chat |
| `chatbubble.swift` | Individual message bubble rendering |
| `chatmessage.swift` | `ChatMessage` struct — in-memory message model (not persisted directly) |
| `chatscrollview.swift` | Scrollable message list, handles auto-scroll to bottom |
| `kodaisidebar.swift` | Collapsible left sidebar — thread list, mode picker, new thread, settings trigger |
| `kodaisettings.swift` | Settings popover (mode reset, context info) |
| `kodaimarkdowntext.swift` | Markdown rendering for assistant messages |
| `kodaibackground.swift` | App window background (dark gradient / glass layer) |
| `kodaiglass.swift` | Reusable glass-style surface modifier |

## State model

`ChatViewModel` holds all in-flight UI state:

```swift
var messages: [ChatMessage]          // in-memory, rebuilt on chat switch
var selectedChat: KodaiChatSession?  // currently active SwiftData session
var isLoading: Bool                  // true while model is streaming
var inputText: String
var selectedMode: OutputMode
var estimatedContextPercent: Int     // rough token usage estimate (4 chars ≈ 1 token)
```

`messages[]` is ephemeral — it's rebuilt from SwiftData when switching chats via `messagesForSession(_:)`. The SwiftData store is the source of truth for persistence.

## Persistence (SwiftData)

Two models in `kodaichatsession.swift`:

```
KodaiChatSession
  id: UUID (unique)
  title: String          — auto-set from first user message (38 char max)
  createdAt / updatedAt: Date
  messages: [KodaiChatMessage]  (cascade delete)

KodaiChatMessage
  id: UUID
  role: String           — "user" or "assistant" (raw value of ChatRole)
  content: String
  createdAt: Date
  session: KodaiChatSession?
```

`ModelContainer` is configured in `kodai_macosApp.swift` and passed down via SwiftUI environment. `ChatViewModel` receives a `ModelContext` at call sites (not stored on self) to avoid threading issues.

## AI layer

`KodaiModel` creates a new `LanguageModelSession` on first use and holds it until `reset()` is called (on new chat or chat switch). Each session maintains its own conversation history inside the Foundation Models framework.

The prompt passed to the session is assembled at call time from:
1. Mode label + system prompt (`OutputMode.systemPrompt`)
2. Last 15 messages formatted as plain text history
3. The user's current message

Context percent is estimated client-side (character count / 4 ≈ tokens, against a 4096 token budget). This is approximate — Foundation Models does not expose real token counts.

## Mode system

`OutputMode` is a `CaseIterable` enum. Each case has:
- `rawValue` — display name shown in the UI
- `systemPrompt` — instruction block injected into every request when that mode is active

Adding a new mode: add a case to `OutputMode`, write its `systemPrompt`, and add an icon mapping in `kodaisidebar.swift:modeIcon(for:)`.

## Design system

- Background: dark gradient via `KodaiBackground`
- Surfaces: `.ultraThinMaterial` with `stroke(.white.opacity(0.10))` border
- Typography: `SF Rounded` at various weights, white-on-opacity for hierarchy
- Animations: `.spring(response: 0.32, dampingFraction: 0.86)` for all interactive transitions
- Corner radius: `18` for panels, `10–12` for buttons/rows, `8` for list items
