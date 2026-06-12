# K2C — iOS local-only SwiftData workspace container

## What this slice did

- Linked the `KodaiPersistence` product (from the local `KodaiCore` package) into the
  iOS app target alongside the existing `KodaiKernel` dependency.
- Added `WorkspaceModelContainer.swift` in the iOS app: a local-only SwiftData
  `ModelContainer` scaffold with two factories:
  - `makeLocal()` — on-disk store `KodaiWorkspace.store` under Application Support,
    `cloudKitDatabase: .none`.
  - `makeInMemory()` — for tests and startup verification.
- Added `WorkspaceModelContainerTests` (app-hosted, runs on simulator) verifying the
  in-memory container initializes and can save/fetch a project with a task.
- Repaired the stale `generationDiagnostics` test in `kodAI_chatbot_devTests.swift`
  (it still used the pre-K1 `generate(prompt:)` API, which broke the test target build).

## Schema scope

The container registers the full relationship closure of `KodaiProject`:
`KodaiProject`, `KodaiTask`, `KodaiChatSession`, `KodaiChatMessage`, `KodaiSummary`,
`KodaiStream`. The chat-side models are pulled in **necessarily** because
`KodaiProject.sessions` relates to `KodaiChatSession`, which relates to messages,
summaries, and streams — SwiftData requires the closed schema. Nothing writes chat
data through this container; chats stay JSON.

## What did NOT change

- JSON remains the source of truth: `ProjectTaskStore` still owns `Projects.json`,
  `ChatStore` still owns ChatSessions/Streams/PromptSettings JSON.
- No CloudKit, no entitlements, no sync, no migration, no chat/prompt/inference/UI
  changes. The app does not touch the container at runtime yet.

## K2D — next slice

- Migrate `Projects.json` into the SwiftData workspace container via
  `WorkspaceModelContainer.makeLocal()` and the existing kernel↔persistence adapters
  (remember the medium↔normal priority mapping).
- Rename `Projects.json` to a `.migrated` backup **only after** a verified successful
  import. Never delete the original data.
- Chats remain JSON/local-only permanently unless explicitly redesigned later.
