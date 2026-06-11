# Architecture Overview

Compact developer map of file responsibilities, ownership, and dependency flow.

## Dependency Groups

```text
UI
  kodAI_chatbot_devApp.swift
    -> ChatView.swift
      -> ChatViewModel.swift
      -> ChatMessage.swift / ChatSession.swift / ChatRole.swift
      -> ChatExportService.swift

State and Orchestration
  ChatViewModel.swift
    -> ChatStore.swift
    -> InferenceService.swift
    -> ChatExportService.swift
    -> ChatMessage.swift / ChatSession.swift / InferencePhase.swift / InferenceEvent.swift

Persistence
  ChatStore.swift
    -> ChatSession.swift
    -> ChatMessage.swift
    -> ModelPromptSettings

Inference
  InferenceService.swift
    -> LocalModelRuntime.swift
      -> ModelDownloader.swift
      -> LlamaRuntime.swift
        -> BundledModelFileResolver.swift
        -> LlamaContextWrapper.swift

Utilities
  AppLog.swift
```

## File Responsibilities

### kodAI_chatbot_devApp.swift

- App entry point and root scene setup.
- Owns root `WindowGroup` composition.
- Depends on:
  - `ChatView.swift` for the app's primary screen.
- Used by:
  - SwiftUI app lifecycle.
- Key responsibilities:
  - root view selection
  - dark color scheme preference

### ChatView.swift

- Main chat UI container and local view composition.
- Renders header, message list, input bar, drawer/menu, summaries, export sheet, and status overlays.
- Owns:
  - drawer open/closed state
  - expanded process summaries
  - input focus state
  - message text size selection
  - local scroll-near-bottom coordination
- Depends on:
  - `ChatViewModel.swift` for app state and actions.
  - `ChatMessage.swift`, `ChatSession.swift`, and `ChatRole.swift` for UI data.
  - `ChatExportService.swift` for export sheet snapshots/results.
  - `InferencePhase.swift` and `InferenceEvent.swift` display state.
- Used by:
  - `kodAI_chatbot_devApp.swift`.
- Key responsibilities:
  - UI coordination only
  - keyboard/focus coordination
  - streaming auto-scroll
  - drawer presentation and navigation
  - export/share presentation
- High coupling warning:
  - This file contains many nested UI components and style helpers. It is currently acceptable as a single-screen app, but future UI growth may make it harder to scan.

### ChatViewModel.swift

- Central app orchestration layer for chat, streams, summaries, prompts, exports, persistence, and generation state.
- Owns:
  - active messages
  - sessions and streams
  - active session selection
  - inference phase and warmup status
  - pending streamed assistant text
  - generation task lifecycle
  - prompt settings and prompt preview context
  - export snapshot state
- Depends on:
  - `InferenceService.swift` for model generation.
  - `ChatStore.swift` for persisted sessions, streams, and prompt settings.
  - `ChatExportService.swift` for export data.
  - `ChatMessage.swift`, `ChatSession.swift`, `ChatRole.swift`.
  - `InferencePhase.swift`, `InferenceEvent.swift`, `LocalModelRuntime.swift`.
- Used by:
  - `ChatView.swift`.
- Key responsibilities:
  - user send/stop flow
  - streaming token buffering and UI flush timing
  - session and stream mutations
  - summary creation and saving
  - slash command handling
  - persistence save/load coordination
  - process summary attachment
- Persistence ownership:
  - Owns when chat/session/stream/prompt state is loaded or saved.
  - Delegates actual file I/O to `ChatStore.swift`.
- High coupling warning:
  - This file is the main coordination hub and carries the highest app coupling. Keep future changes narrow unless architecture changes are explicitly requested.

### ChatStore.swift

- Persistence actor for durable chat-related JSON files.
- Owns:
  - sessions file location
  - streams file location
  - prompt settings file location
  - JSON encode/decode policy
- Depends on:
  - `ChatSession.swift` and `ChatMessage.swift`.
  - `ModelPromptSettings` from `ChatViewModel.swift`.
  - `AppLog.swift`.
- Used by:
  - `ChatViewModel.swift`.
- Key responsibilities:
  - non-main-actor file I/O
  - load/save sessions
  - load/save streams
  - load/save prompt settings
  - tolerate unreadable persisted data by returning safe defaults

### ChatMessage.swift

- Message model and generation process summary model.
- Owns:
  - message identity, role, text, timestamp, and optional process summary
  - persisted inference summary data attached to assistant messages
- Depends on:
  - `ChatRole.swift`.
  - `InferencePhase.swift`.
- Used by:
  - `ChatView.swift`
  - `ChatViewModel.swift`
  - `ChatSession.swift`
  - `ChatStore.swift`
  - `ChatExportService.swift`
  - inference prompt formatting
- Key responsibilities:
  - stable message identity
  - Codable session persistence
  - process telemetry storage

### ChatRole.swift

- Role enum for chat messages.
- Owns:
  - supported persisted roles: user and assistant.
- Depends on:
  - Foundation for Codable/Sendable support.
- Used by:
  - `ChatMessage.swift`
  - `ChatView.swift`
  - `ChatViewModel.swift`
  - `ChatExportService.swift`
  - prompt formatting in `LlamaContextWrapper.swift`
- Key responsibilities:
  - model/UI/export role branching

### ChatSession.swift

- Persistent session and stream models.
- Owns:
  - chat session metadata
  - session messages
  - pinned state
  - session-to-stream membership
  - chat and stream summaries
  - stream chat ordering
- Depends on:
  - `ChatMessage.swift`.
- Used by:
  - `ChatView.swift`
  - `ChatViewModel.swift`
  - `ChatStore.swift`
  - `ChatExportService.swift`
- Key responsibilities:
  - Codable persistence shape
  - stream grouping data
  - backwards-compatible decode defaults for newer fields

### ChatExportService.swift

- Markdown export formatting and temporary file creation.
- Owns:
  - export snapshot shape
  - generated Markdown contents
  - export filename sanitization
  - temporary export file writing
- Depends on:
  - `ChatMessage.swift`
  - `ChatRole.swift`
  - `AppLog.swift`
- Used by:
  - `ChatViewModel.swift` to create export snapshots.
  - `ChatView.swift` export sheet to save/share files.
- Key responsibilities:
  - export-only formatting
  - metadata assembly
  - shareable temporary file output

### InferenceService.swift

- Thin actor boundary between view model orchestration and local runtime.
- Owns:
  - a `LocalModelRuntime` instance.
- Depends on:
  - `LocalModelRuntime.swift`
  - `InferenceEvent.swift`
  - `ChatMessage.swift`
  - `ModelPromptStack` from `ChatViewModel.swift`
- Used by:
  - `ChatViewModel.swift`.
- Key responsibilities:
  - start generation stream
  - forward cancellation
  - keep runtime calls off the main actor

### LocalModelRuntime.swift

- Local model lifecycle and generation-session coordinator.
- Owns:
  - selected model configuration
  - cached llama context
  - active generation task
  - model download coordination
- Depends on:
  - `LlamaRuntime.swift`
  - `ModelDownloader.swift`
  - `LlamaContextWrapper.swift`
  - `InferenceEvent.swift`
  - `ChatMessage.swift`
  - `ModelPromptStack` from `ChatViewModel.swift`
  - `AppLog.swift`
- Used by:
  - `InferenceService.swift`
  - tests and diagnostics
- Key responsibilities:
  - ensure model availability
  - load/reuse llama context
  - emit generation phase events
  - bridge runtime finish/cancellation/failure into stream events
- Model behavior ownership:
  - Owns default configuration values for context size, output limit, sampling, and model file names.

### LlamaRuntime.swift

- Actor wrapper around prompt preparation and llama generation phases.
- Owns:
  - model file resolution before context creation
  - GGUF header validation
  - high-level llama generation phase ordering
- Depends on:
  - `BundledModelFileResolver.swift`
  - `LlamaContextWrapper.swift`
  - `LocalModelRuntime.swift` configuration/errors
  - `InferenceEvent.swift`
  - `ChatMessage.swift`
  - `ModelPromptStack` from `ChatViewModel.swift`
  - `AppLog.swift`
- Used by:
  - `LocalModelRuntime.swift`.
- Key responsibilities:
  - initialize llama context
  - format prompt
  - tokenize
  - prefill
  - decode and yield token events

### LlamaContextWrapper.swift

- Low-level llama.cpp context, sampler, prompt formatting, tokenization, prefill, decode, and stop filtering.
- Owns:
  - llama model pointer
  - llama context pointer
  - sampler chain
  - cancellation flag
  - UTF-8 token buffer
  - textual stop filtering
  - llama chat prompt formatting helpers
- Depends on:
  - external `llama` package.
  - `LocalModelRuntime.swift` configuration/errors.
  - `ChatMessage.swift` and `ChatRole.swift`.
  - `ModelPromptStack` from `ChatViewModel.swift`.
  - `InferenceEvent.swift` warmup/finish types.
  - `AppLog.swift`.
- Used by:
  - `LlamaRuntime.swift`
  - `LocalModelRuntime.swift`
- Key responsibilities:
  - native resource lifetime
  - tokenization and decode loops
  - cancellation checks during prefill/decode
  - stop-string filtering
  - prompt truncation/recent-history selection
- High coupling warning:
  - This file combines native resource management, prompt formatting, token flow, and decode diagnostics. Keep edits especially small because behavior changes here affect model output.

### ModelDownloader.swift

- Ensures the configured model exists in Application Support.
- Owns:
  - Qwen download URL
  - local model storage path
  - atomic-ish staging move into the model directory
- Depends on:
  - `LocalModelRuntime.swift` configuration.
  - `AppLog.swift`.
- Used by:
  - `LocalModelRuntime.swift`
  - `BundledModelFileResolver.swift`
- Key responsibilities:
  - locate local model files
  - download missing model files
  - validate HTTP response success before install

### BundledModelFileResolver.swift

- Resolves the model file used by llama initialization.
- Owns:
  - downloaded-model-first resolution
  - bundled fallback resolution
- Depends on:
  - `ModelDownloader.swift`
  - `LocalModelRuntime.swift` configuration/errors
  - `AppLog.swift`
- Used by:
  - `LlamaRuntime.swift`.
- Key responsibilities:
  - choose downloaded Qwen when available
  - fall back to bundled Smol model
  - raise a model-missing error with expected locations

### InferenceEvent.swift

- Stream event contract from inference runtime to UI orchestration.
- Owns:
  - phase events
  - warmup events
  - token events
  - completion and cancellation events
  - warmup status enum
- Depends on:
  - `InferencePhase.swift`
  - `LlamaContextWrapper.swift` finish reason
- Used by:
  - `InferenceService.swift`
  - `LocalModelRuntime.swift`
  - `LlamaRuntime.swift`
  - `ChatViewModel.swift`
  - `ChatView.swift`
- Key responsibilities:
  - async stream payload shape
  - UI-visible model lifecycle status

### InferencePhase.swift

- Generation phase enum used by runtime, summaries, logs, and UI.
- Owns:
  - lifecycle states from idle through failure.
- Depends on:
  - Foundation for Codable/Sendable support.
- Used by:
  - `InferenceEvent.swift`
  - `ChatMessage.swift`
  - `ChatViewModel.swift`
  - `ChatView.swift`
  - `LocalModelRuntime.swift`
  - `LlamaRuntime.swift`
- Key responsibilities:
  - persisted process phase values
  - display-state switching
  - process summary phase history

### AppLog.swift

- Lightweight categorized logging utility.
- Owns:
  - category labels
  - optional elapsed-time formatting
- Depends on:
  - Foundation.
- Used by:
  - persistence, inference, model resolution/download, export, and view model diagnostics.
- Key responsibilities:
  - consistent debug logging shape
  - low-friction timing logs

### kodAI_chatbot_devTests.swift

- Swift Testing target for app-level diagnostics.
- Owns:
  - default test stub
  - generation diagnostics over `LocalModelRuntime`
- Depends on:
  - `LocalModelRuntime.swift`
  - `InferenceEvent.swift`
- Used by:
  - test runner.
- Key responsibilities:
  - basic project test target presence
  - manual generation output diagnostics

### kodAI_chatbot_devUITests.swift

- Default UI test target.
- Owns:
  - app launch and placeholder UI test surface.
- Depends on:
  - XCTest.
- Used by:
  - UI test runner.
- Key responsibilities:
  - future UI test entry point

### kodAI_chatbot_devUITestsLaunchTests.swift

- Default launch-performance UI test target.
- Owns:
  - launch measurement setup.
- Depends on:
  - XCTest.
- Used by:
  - UI test runner.
- Key responsibilities:
  - future launch performance checks
