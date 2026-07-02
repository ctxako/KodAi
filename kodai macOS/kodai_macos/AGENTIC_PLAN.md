# Kodai macOS — Agentic Foundation Models Plan

Goal: turn Kodai macOS from a chat app with two propose-only tools into an
on-device agent built on Apple Foundation Models that can execute multi-step
tool chains (with user confirmation for writes) to organize the user's device
and life — calendar, reminders, contacts, files, notifications, and Kodai's
own projects/tasks.

Everything stays on-device. No network calls, no API keys (per CLAUDE.md).

---

## 1. Where the code is today

### kodai_macos (this repo)
- `foundationmodelsbackend.swift` — wraps `LanguageModelSession` with per-chat
  session cache. Registers exactly two tools.
- `kodaitoolbox.swift` — `CreateTaskTool` / `CreateProjectTool`. **Propose-only**:
  they stash a single `PendingToolProposal` in `ToolProposalCollector` and
  return "Awaiting user confirmation" to the model. The model's turn ends;
  the actual SwiftData write happens later in `ChatViewModel.confirmProposal`.
  The model never learns whether the action happened.
- `chatviewmodel.swift` (~1500 lines) — slash commands (`/task`, `/project`,
  `/done`) do the real mutations; the system prompt explicitly tells the model
  it *cannot* create tasks itself.
- SwiftData: projects, tasks, chats, streams; `ledgerRecorder` already logs
  action events; Studio dashboard + telemetry exist.
- 4096-token context window (`contextWindowTokenLimit`), `ContextAssembler`
  with `TokenBudget` already budgets the prompt.

### What is reusable from the rest of the monorepo
- **KodaiKernel** (`KodaiCore/Sources/KodaiKernel/Assistant/`) already defines
  `AssistantToolCall` — a typed enum of 19 tools: calendar (create/list/delete
  event), reminders (create/list/complete), contacts (search/create), files
  (list/read/create/create-folder/delete), clipboard (read/write),
  notifications (schedule/cancel), webFetch, openUrl.
- **kodai-consumer app** has concrete routers for all of them
  (`Tools/EventKitToolRouter.swift`, `ContactsToolRouter`, `FileToolRouter`,
  `ClipboardToolRouter`, `NotificationToolRouter`, `SystemToolRouter`,
  `ToolRouterDispatch`) plus `ConfirmDecision`, `ToolResult`, and an async
  confirm gate: `confirm: (AssistantToolCall) async -> ConfirmDecision`.
  Tests exist (`ToolRouterDispatchTests`).
- The consumer's `AgentLoop` (parse → validate → execute → feed back) exists
  because llama.cpp emits raw text. **We do not port it.** On macOS, Apple's
  `LanguageModelSession` runs the tool loop natively: register `Tool`
  conformers and the framework calls them, feeds results back, and continues
  until the model produces a final response — all inside one
  `session.streamResponse(to:)`. The agentic loop is free; we only supply
  tools that actually execute.

### Constraint notes
- `GenerationOptions.ToolCallingMode` (.required/.allowed) is macOS 27 beta —
  not available at our 26.4 deployment target. Not needed: the default
  session behavior already loops tool calls.
- `webFetch` conflicts with the "no network calls" rule. Ship `openUrl`
  (NSWorkspace, hands off to the browser — no in-app networking); leave
  `webFetch` out unless it becomes an explicit opt-in later.
- Repo hygiene: `docs` at the repo root is a *file* (the design doctrine),
  not a directory, and `docs/architecture.md` referenced by CLAUDE.md does
  not exist. Fix during Phase 0 (make `docs/` a directory, move the doctrine
  into it).

---

## 2. Target architecture

```
LanguageModelSession (Foundation Models, native tool loop)
  └── FM Tool adapters (one per AssistantToolName, @Generable args)
        └── build AssistantToolCall (KodaiKernel)
              └── MacToolRouterDispatch
                    ├── ConfirmBroker (async, suspends tool call,
                    │    shows inline confirmation card, resumes with decision)
                    ├── EventKit / Contacts / Files / Clipboard /
                    │    Notifications / System routers (macOS ports)
                    └── Workspace router (SwiftData: Kodai projects & tasks)
        └── returns ToolResult JSON string → model continues the chain
```

Key shift from today: a tool call **awaits the real outcome**. The
confirmation card appears mid-stream; on approve the router executes and the
model receives the truthful result ("Created event X at 3pm") and can chain
the next step. On decline the tool returns "cancelled by user" and the chain
ends gracefully (consumer learned: don't invite retries of a refused write).

### Trust tiers (design doctrine §12.3)
- **Auto-run (read-only):** list events/reminders/tasks, search contacts,
  list/read files in granted folders, read clipboard, Spotlight search.
- **Confirm (mutating):** create/edit event, reminder, contact, task, project,
  file, folder, notification, write clipboard, open URL.
- **Confirm with detail shown (destructive):** delete event, delete file,
  complete/close items in bulk.
- Per-tool enable/disable + per-tier auto-approve toggles in Settings.

---

## 3. Phases

### Phase 0 — Kernel promotion & repo hygiene (small) — DONE 2026-07-02
1. Promote `ConfirmDecision`, `ToolResult`, and the `ToolRouter` protocol from
   the consumer app into `KodaiKernel` (they are app-local today;
   `AssistantToolCall` is already kernel-level). Consumer app switches to the
   kernel types — no behavior change, tests stay green.
2. Add a `.toolActivity(name: String, phase: ...)` case to
   `InferenceEvent` in KodaiCore so any backend can stream tool progress.
3. Turn `docs` file into `docs/design-doctrine.md`; write the missing
   `docs/architecture.md` stub.

### Phase 1 — FM Tool bridge + confirm broker (the core) — DONE 2026-07-02
Implemented in `toolconfirmation.swift` (ConfirmBroker), `kodaitoolbox.swift`
(WorkspaceToolExecutor + executing CreateTaskTool/CreateProjectTool), backend
tool injection, and ChatViewModel turn bindings. Tool activity surfaces via
the streaming message's status line; broker/executor covered by unit tests.
M1 pending manual verification in the running app.
1. `kodaifmtools.swift`: one FM `Tool` conformer per kernel tool, with
   `@Generable`/`@Guide` argument structs mirroring the kernel argument
   shapes. `call(arguments:)` maps to `AssistantToolCall`, awaits the
   dispatcher, serializes `ToolResult` back to the model.
2. `ConfirmBroker` (@MainActor): `func request(_ call: AssistantToolCall)
   async -> ConfirmDecision` implemented with a `CheckedContinuation`; sets an
   `@Observable` `pendingConfirmation` that the transcript renders as an
   inline card (evolve `toolproposalconfirmationcard.swift`). Approve/decline
   resumes the tool call. Timeout/new-message/stop cancels → decline.
3. Replace `ToolProposalCollector` and the propose-only tools. Update the
   system prompt: the model *can* act, writes are user-confirmed.
4. Stream UI: render `.toolActivity` events as quiet step chips in the
   transcript ("Checking calendar…", "Created reminder ✓"); every executed
   step also lands in the existing `ledgerRecorder`.
5. Stop button cancels the session stream *and* declines any pending confirm.

### Phase 2 — Workspace tools (organize your life, app-domain)
1. Workspace router over SwiftData: `tasksList`, `taskCreate`, `taskComplete`,
   `taskReschedule`, `projectsList`, `projectCreate` — superseding the two
   propose-only tools, reusing `TaskDueDateSemantics` for date parsing.
2. `dailyBrief` composite tool: overdue → due-today → upcoming from SwiftData
   (later merged with EventKit data once Phase 3 lands).
3. Keep slash commands as fast paths; they now share the router code.

### Phase 3 — Device routers (organize your device, macOS ports)
1. Port consumer routers to macOS targets:
   - EventKit calendar + reminders (same API; needs
     `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`,
     `com.apple.security.personal-information.calendars`).
   - Contacts (same API; usage description + entitlement).
   - Notifications (`UNUserNotificationCenter`, same API).
   - Clipboard → `NSPasteboard`.
   - Files → sandbox-correct macOS version: `NSOpenPanel` "grant folder"
     flow, security-scoped bookmarks persisted, operations restricted to
     granted roots. Settings pane lists/revokes granted folders.
   - System → `openUrl` via `NSWorkspace` only (no `webFetch`).
2. Availability & graceful denial: each router reports "permission not
   granted" as a `ToolResult` failure the model can relay honestly, with a
   deep link to the right Settings pane.

### Phase 4 — macOS-native organizer tools (new capability)
1. `spotlightSearch` — `NSMetadataQuery` over granted scopes: find files by
   name/kind/date; read-only, auto-run.
2. `filesMove` / `filesRename` / `filesTag` (Finder tags via extended
   attributes) — the actual "organize my Downloads folder" muscle; confirm
   tier, batched preview card ("Move 14 screenshots → ~/Pictures/Screenshots?").
3. Research spike (timeboxed): running user Shortcuts from a sandboxed app
   (`NSUserAppleScriptTask` in the Application Scripts folder vs. App Intents
   interop). Ship only if it can be done sandbox-clean.

### Phase 5 — Context budget & mode-scoped toolsets
1. Measure real prompt overhead per registered tool (schemas count against
   the 4096 window). Expect ~20 tools to be too heavy.
2. Scope toolsets by `OutputMode`: **Chat** → workspace tools only;
   **Organize** → workspace + files + Spotlight + calendar/reminders;
   **Checklist** → workspace + reminders; **Summarize/Debug** → none.
   `configure(instructions:chatID:)` already rebuilds sessions on mode
   change — extend it to also swap the tool array.
3. Feed tool overhead into `ContextAssembler`'s `TokenBudget` so context
   trimming accounts for it.

### Phase 6 — Safety polish, settings, tests
1. Settings → new "Tools" section: master toggle, per-tool toggles, tier
   auto-approve, granted folders, permission status per framework.
2. Ledger view: every executed tool call visible and exportable; "undo"
   affordances where cheap (completed task → reopen; file move → move back).
3. Tests (mirror consumer's approach — protocol-mocked, no simulators):
   - Tool adapter mapping tests (FM args → `AssistantToolCall`).
   - ConfirmBroker suspend/resume/cancel tests.
   - Router tests with mocked stores (EventKit/Contacts wrapped behind thin
     protocols like the consumer did).
   - One end-to-end fake-backend test: multi-step chain with a confirm in the
     middle.

---

## 4. Milestone acceptance

- **M1 (Phases 0–1):** "add a task to finish the design doc by Friday" — the
  model calls the tool, a confirm card streams inline, approving writes to
  SwiftData, and the model's final message truthfully reports the created task.
- **M2 (Phases 2–3):** "what should I do today?" pulls tasks + calendar +
  reminders in one turn (read-only, zero confirms). "Move my dentist
  appointment to 4pm and remind me an hour before" chains two confirmed writes.
- **M3 (Phases 4–5):** "organize the PDFs in my Downloads into an Invoices
  folder" runs Spotlight/list → batched move preview → confirmed execution,
  in Organize mode, within context budget.
- **M4 (Phase 6):** every action in the ledger, every tool toggleable, tests
  green via compile-only + unit tests (no simulators).

## 5. Risks
- **Small model reliability on multi-step chains** — mitigations: tight
  @Guide descriptions, mode-scoped small toolsets, kernel bench harness to
  eval tool-call accuracy per toolset (reuse the KodAi Bench Lab pipeline).
- **Session cache staleness** — a confirmed write changes app state that
  cached per-chat sessions don't know; refresh instructions/context snapshot
  on next turn after any write.
- **Sandbox friction on files** — the grant-folder UX must come before file
  tools ship or every file call dead-ends.
- **Tool schema token cost on a 4096 window** — measured in Phase 5 before
  broadening any toolset; cut argument descriptions before cutting tools.
