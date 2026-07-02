# Kodai macOS — Architecture

All app logic runs on `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

## Data flow

```
ContentView
  └── ChatViewModel (@Observable, @MainActor)      — central state coordinator
        ├── FoundationModelsBackend                — wraps LanguageModelSession
        │     ├── SystemLanguageModel.default      — Apple Foundation Models
        │     └── FM Tool adapters (kodaitoolbox)  — agentic tool calls
        │           └── WorkspaceToolExecutor      — confirmed writes
        │                 └── ConfirmBroker        — async user confirmation
        ├── ContextAssembler (KodaiKernel)         — token-budgeted prompt blocks
        ├── SummaryEngine                          — auto chat summaries
        ├── TelemetryStore / LedgerRecorder        — diagnostics + action ledger
        └── ModelContext (SwiftData)               — persistence
```

## Agentic turn lifecycle

1. `ChatViewModel.send` → `runModel` binds the turn's `ModelContext` and
   projects into `WorkspaceToolExecutor`, then streams
   `backend.stream(prompt:instructions:)`.
2. `LanguageModelSession` natively loops tool calls: when the model invokes a
   tool, the FM adapter maps its `@Generable` arguments and awaits the
   executor.
3. For mutating tools the executor suspends on `ConfirmBroker.request(_:)` —
   a `CheckedContinuation` that resumes when the user approves or cancels the
   inline confirmation card.
4. The executor performs the SwiftData write (or reports cancellation) and
   returns a `ToolResult` (KodaiKernel) whose JSON is fed back to the model,
   which then continues or finishes its response with the true outcome.
5. Every executed step is recorded in the ledger; tool progress surfaces in
   the streaming message's status line.

## Session management

`FoundationModelsBackend` caches one `LanguageModelSession` per chat UUID so
conversational continuity survives chat switches. Mode changes rebuild the
session with fresh instructions (and, later, mode-scoped toolsets).

## Persistence

SwiftData models live in `kodaichatsession.swift` (chats, messages, streams,
projects, tasks) plus the ledger models. The workspace container is local-only
(CloudKit deferred to K2G).

## Shared kernel

`KodaiCore` (`../../KodaiCore`) supplies inference contracts
(`KodaiInferenceBackend`, `InferenceEvent`), context assembly
(`ContextAssembler`, `TokenBudget`), slash-command parsing, and the shared
tool-execution vocabulary (`ToolResult`, `ConfirmDecision`, `ToolRouter`,
`ToolActivity`) used by both this app and the iOS/consumer agents.

See `AGENTIC_PLAN.md` at the repo root for the phased roadmap and
`docs/design-doctrine.md` for the visual/UX doctrine.
