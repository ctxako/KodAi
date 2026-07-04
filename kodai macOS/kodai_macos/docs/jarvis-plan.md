# Kodai macOS — Jarvis Plan (agentic workflows + agentic accountability)

Goal: evolve Kodai macOS from an agentic chat app into a personal interface
for agentic workflows — an on-device "Jarvis" that runs your day, holds you
accountable to your own commitments, and is present before you ask.

This is the arc **after** `AGENTIC_PLAN.md` (tool execution foundation;
Phases 0–1 done). It pulls some of that plan's later phases forward and adds
the accountability + ambient layers on top.

Everything stays on-device. No network calls, no API keys (per CLAUDE.md).

---

## 1. Direction decisions (locked 2026-07-03)

1. **Brain — hybrid, fully local.** Apple Foundation Models stays the fast
   default; the shared `KodaiRuntime` llama.cpp path (already proven on macOS
   in Studio's `StudioLlamaEngine`) becomes a second chat-capable engine for
   heavy agentic turns. No cloud escalation; the privacy doctrine holds.
2. **Accountability = the agent holds ME accountable.** Chief-of-staff
   product, not (only) an audit trail: briefings, debriefs, commitment
   tracking, honest follow-ups with receipts. (The existing ledger remains
   the substrate — nudges and briefings are themselves ledger-logged.)
3. **Tool reach = personal-data ring + apps/automation ring.**
   `~/life` + workspace SwiftData, then EventKit calendar/reminders,
   notifications, and a sandbox-clean Shortcuts/AppleScript spike. No
   general files/shell ring for now.
4. **Presence = ambient layer + chat.** Menu-bar item + global-hotkey HUD +
   scheduled notifications; the main window becomes mission control. Chat
   stays but stops being the front door.
5. **First win = morning briefing + evening debrief** (the daily rhythm).
6. **Proactivity = scheduled + slipping commitments only.** Fixed daily
   touchpoints plus event-driven nudges when a tracked commitment is about
   to slip. Nothing else interrupts.

---

## 2. Target architecture (delta over today)

```
Ambient layer
  ├── MenuBarExtra (today glance, quick capture, pending confirms)
  ├── Hotkey HUD (NSPanel, Spotlight-style → same ChatViewModel pipeline)
  └── UNUserNotificationCenter (scheduled briefings, slip nudges)
        ▲
BriefingEngine / CommitmentTracker (@MainActor, @Observable)
  ├── sources: SwiftData (tasks/projects/streams/commitments),
  │            ~/life via LifeFolderAccess + kb_search,
  │            EventKit (J2+)
  ├── composition: FM for short structured summarization
  └── every briefing/nudge → LedgerRecorder (accountability is auditable)
        ▲
Engine router (J5)
  ├── FoundationModelsBackend  — fast turns, composition, extraction
  └── LlamaChatBackend (KodaiRuntime) — long-context planning, heavy chains
        └── KodaiKernel AgentLoop + grammar-constrained tool calls
```

New SwiftData models (in `kodaichatsession.swift` per convention):

- `KodaiCommitment` — text, provenance (chat message ID or journal path +
  line), createdAt, dueDate, status (open / kept / slipped / dropped),
  slipCount, lastNudgedAt.
- `BriefingRecord` — date, kind (morning / evening), content snapshot,
  deliveredAt, openedAt.

---

## 3. Phases

### J0 — Accountability data model + settings (small) — DONE 2026-07-03
1. ✅ `KodaiCommitment` and `BriefingRecord` @Model classes live in
   `KodaiPersistence/Models/`; local store bumped to `KodaiLocalStoreSchemaV5`
   with a lightweight V4→V5 stage (additive only).
2. ✅ `ActivityKind` gains `briefingDelivered`, `nudgeSent`,
   `commitmentChange`; `CommitmentStatus`/`CommitmentSource`/`BriefingKind`
   added to KodaiKernel enums.
3. ✅ Settings: `accountabilitysettings.swift` (storage keys, defaults
   8:00 / 21:30, `NudgePolicy` defaulting to scheduled+slipping, nudge
   budget, quiet hours incl. wrap-past-midnight math) + a "Rhythm" tab in
   `KodaiSettingsView`, master-gated by `jarvis.rhythmEnabled` (off until
   J1 machinery exists). Tests in `accountabilitytests.swift`.

### J1 — Daily rhythm v1 (FIRST WIN) — BUILT 2026-07-03, pending manual verification
Shipped: `briefingengine.swift` (deterministic markdown composition from
tasks/commitments + read-only ~/life echo via `lifejournalreader.swift`
[debriefs/ships tables in life.db], optional FM headline, idempotent per
(day, kind), delivery ledger-logged), `briefingview.swift` (+ sidebar
"Briefing" row and `.briefing` route), `rhythmscheduler.swift`
(UNUserNotificationCenter daily triggers + tap routing),
`menubarglance.swift` (MenuBarExtra gated on `jarvis.rhythmEnabled`),
`SMAppService` login-item toggle in the Rhythm settings tab. Note: the
evening reflection stores on `BriefingRecord` only — journal append needs a
read-write ~/life grant (current `LifeFolderAccess` scope is read-only).
Unit tests in `briefingenginetests.swift` (compiled; run manually — test
execution launches the app).
1. `BriefingEngine`: composes the **morning brief** from due/overdue tasks,
   project + stream status, open commitments, and yesterday's journal
   (`LifeFolderAccess` + `kb_search`). FM handles composition — several
   small structured calls, not one big prompt (4096-token window; reuse
   `SummaryEngine` patterns and `ContextAssembler` budgeting).
2. **Evening debrief**: reconciles the day (due vs. done, commitments
   touched), asks for a two-line reflection, appends it to the `~/life`
   journal (confirm-gated write), rolls unresolved items forward.
3. Delivery: `UNUserNotificationCenter` scheduled at the configured times;
   tapping opens a new **Briefing view** in the main window. Store every
   brief as a `BriefingRecord`.
4. `MenuBarExtra`: today glance (next event-less v1: due tasks + open
   commitments) — also keeps the app resident so schedules actually fire.
5. Register as login item via `SMAppService` (Settings toggle) so the
   ambient layer survives reboots.

**Acceptance:** at 8:00 a notification "Morning brief ready" opens a brief
showing tasks, journal echo, and open commitments; at 21:30 the debrief asks
"you said X would be done today — did it happen?" and writes the reflection
to `~/life` after confirm.

### J2 — See the real day (EventKit ring — pulls AGENTIC_PLAN Phase 3 forward)
1. Port the consumer EventKit calendar + reminders routers to macOS
   (entitlements + usage descriptions; reads auto-run, writes confirm-gated
   through the existing `ConfirmBroker` flow).
2. Merge calendar into briefings — `dailyBrief` (AGENTIC_PLAN Phase 2.2)
   becomes real: meetings + tasks + commitments in one morning view.
3. Register the calendar/reminder FM tools in the chat loop (mode-scoped
   toolsets per AGENTIC_PLAN Phase 5 becomes load-bearing here — measure
   schema token cost before broadening).

**Acceptance:** the brief shows today's meetings; "move my 3pm and remind me
an hour before" chains two confirmed writes in one turn.

### J3 — Commitment tracking + slip nudges (the accountability core)
1. Extraction: FM structured extraction (`@Generable CommitmentCandidate`)
   runs over each finished chat turn and each evening journal entry;
   tracking is confirm-gated at first ("Track this? 'design doc by
   Friday'"), with an auto-track-and-review-in-debrief setting once
   precision is proven.
2. Slip detection: a lightweight scheduler checks open commitments against
   due dates; fires **one** nudge per the policy, always with a receipt —
   the original quote, linked to its source message or journal line.
3. Tracker UI in mission control: open / kept / slipped, streaks; kept-rate
   feeds Studio as an accountability analytics panel.
4. Eval the extractor with the bench-lab harness before trusting auto-track
   (small-model precision is the known risk).

**Acceptance:** say "I'll finish the design doc by Friday" in chat → it's
tracked; Friday afternoon with no completion → exactly one nudge quoting
your own words.

### J4 — Ambient presence (Jarvis is *there*)
1. **Hotkey HUD**: global shortcut summons a floating `NSPanel`
   (Spotlight-style, glass aesthetic) bound to the same
   `ChatViewModel`/tool pipeline; inline results; Esc dismisses; pending
   confirm cards render in the panel.
2. MenuBarExtra matures: quick capture ("remind me…", "log…", "/task…"),
   pending confirmations surface here, brief re-open.
3. Main window home becomes **Mission Control**: today, commitments,
   streams, briefing history, ledger — the Workspace persona's evolution
   (Studio persona untouched).

### J5 — Hybrid brain (engine router)
1. `LlamaChatBackend`: wire the existing `KodaiRuntime` llama path (Studio
   already loads file-based GGUF on macOS via model-store symlinks) behind
   the `KodaiInferenceBackend` contract as a chat engine.
2. Tool calls on raw-text models: reuse the `KodaiKernel` `AgentLoop`
   (iOS already runs it) with grammar-constrained tool-call output —
   grammar must match the model's dialect (consumer M1–M3 learning).
3. Routing v1 is **explicit**: per-chat/per-mode engine picker with a
   visible model badge per turn (doctrine honesty). Auto-escalation
   heuristics come later, informed by route-eval (use the repo-bundled
   GGUF for evals).
4. Long-context payoff: briefing composition and multi-step planning can
   move to the llama engine, relieving the FM 4096 window.

### J6 — Automation ring + trust polish
1. Timeboxed spike: run user Shortcuts / AppleScript sandbox-clean
   (`NSUserAppleScriptTask` in the Application Scripts folder vs. App
   Intents interop) — carry-over of AGENTIC_PLAN Phase 4.3; ship only if
   clean.
2. Trust settings: per-tool toggles + tier auto-approve (AGENTIC_PLAN
   Phase 6.1 lands here), nudge budget, quiet hours, and a "why did you
   nudge me" ledger view.
3. Tests (protocol-mocked, no simulators): BriefingEngine with mocked
   stores; ConfirmBroker paths already covered; scheduler timing tests;
   commitment-extraction eval suite via the bench harness.

---

## 4. Milestone acceptance

- **MJ1 (J0–J1):** daily rhythm live — scheduled brief + debrief, journal
  reflection written, app resident via menu bar + login item.
- **MJ2 (J2):** briefings see the real calendar; two-step confirmed
  calendar edit from chat works.
- **MJ3 (J3):** commitments tracked from natural speech with receipts;
  slip nudge fires once, on policy.
- **MJ4 (J4):** hotkey HUD + mission control shipped; chat is no longer
  the front door.
- **MJ5 (J5):** llama engine selectable in chat with truthful model badge;
  one long-context agentic task demonstrably better than FM.
- **MJ6 (J6):** Shortcuts spike decided; trust settings + nudge
  accountability views complete.

## 5. Risks

- **Scheduling requires a resident app** — mitigation: MenuBarExtra +
  `SMAppService` login item (J1); a true background daemon is out of scope.
- **Small-model extraction precision** — confirm-gated tracking first;
  bench-lab evals before auto-track.
- **Nudge fatigue kills trust** — hard daily budget, quiet hours, receipts
  on every nudge, all nudges ledger-logged.
- **SwiftData migration** (new models) — additive lightweight migration
  only; remember the quarantine-bug lesson before shipping.
- **EventKit entitlements/sandbox friction** — permission-denial must
  surface as honest `ToolResult` failures with a Settings deep link
  (AGENTIC_PLAN Phase 3.2 pattern).
- **Tool schema token cost on FM's 4096 window** — mode-scoped toolsets
  (AGENTIC_PLAN Phase 5) before broadening; llama engine relieves this
  in J5.
- **Sandbox + GGUF model files** — reuse Studio's model-store symlink
  approach; verify it holds inside the sandboxed chat app context (Studio
  path is currently not sandbox-constrained the same way).
