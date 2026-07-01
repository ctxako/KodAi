# Production Plan: kodai-consumer v1.0

> **Status log**
> - **2026-07-01** — M1 ✅ (loop wired into UI, respond terminal, per-step cards,
>   cancel semantics). M2 ✅ (download UX, disk guard, GGUF verify, recovery).
>   M3 code ✅ (DeviceTier budgets + thermal guard; *device profiling still owed*).
>   M5 ✅ (permission-model bugs fixed: calendar reads were write-only-broken,
>   contacts had no usage description; web_fetch hardened; portrait/iPhone-only;
>   a11y pass). M4 in flight: route-eval rebuilt for v2 (was broken since the
>   rebuild); first baseline exposed hybrid-format parser losses + hallucinated
>   past due-dates — both fixed; re-measuring. M6/M7: feedback button in
>   Settings, APP_STORE.md + PRIVACY.md drafted. **Still owed:** device
>   profiling (M3), eval bar (M4), TestFlight upload (M6), icon + screenshots +
>   policy hosting (M7).

Sequenced plan from current state → App Store production. Complements
[NEXT_STEPS.md](NEXT_STEPS.md) (workstream catalog) by fixing an **order**, defining
**exit criteria** per milestone, and pinning the two product constraints that shape
every decision:

1. **Claude Code as the design reference.** The product is an agentic loop — plan,
   call tools, observe, iterate, confirm dangerous actions — not a chatbot with
   function calling bolted on. Where Claude Code has Bash/Edit/Read, kodai has
   EventKit/Files/Contacts. Where Claude Code has permission prompts, kodai has
   confirm cards. Where Claude Code streams its work, kodai streams action cards
   into the feed.
2. **iPhone 14 and under, fully on-device.** The floor device defines the budget:

   | Device | Chip | RAM | Realistic app budget |
   |---|---|---|---|
   | iPhone 14 / 14 Plus | A15 | 6 GB | ~3 GB |
   | iPhone 13 / 13 mini | A15 | 4 GB | ~1.8–2 GB |
   | iPhone 12 / 12 mini | A14 | 4 GB | ~1.8–2 GB |

   LFM 2.5 1.2B Q4_K_M (~700 MB weights + KV cache + app) fits the 4 GB tier with
   headroom — that is why the model choice holds. Any model upgrade must re-clear
   the **iPhone 12 bar**, not the iPhone 14 bar. Context window, chain depth, and
   thread count are all tuned against the floor device, never the dev device.

---

## Current state (verified 2026-07-01)

**Built and working:**
- 20 tools / 7 domains, all routers implemented (`Tools/`)
- `AgentLoop` — clean multi-step infer→parse→validate→execute loop with retry,
  step budget of 6, protocol-mocked and tested (`Agent/AgentLoop.swift`)
- 3-tab UI (Feed / Upcoming / Archive), SwiftData `ActionStore`, onboarding,
  settings, confirm flow, haptics, App Intents, input widget
- `ConsumerModelFileResolver` — download-then-bundle fallback already wired via
  `ModelDownloader` + `LocalModelConfiguration.downloadURL` (HF, Q4_K_M)
- ~1,700+ lines of tests: parser, validator, loop, dispatch, store

**The gap that defines the product:**
- `AssistantController.run()` is **single-turn**: one inference → one tool call →
  session ends. `AgentLoop` is never invoked from the UI. Until this is wired,
  the app is a one-shot command palette, not a Claude-Code-style agent.

**Not started:** device profiling on the 4 GB tier, download UX (progress /
resume / disk guard), App Store package, TestFlight, accessibility audit,
tool-calling eval suite on-device.

---

## Milestone 1 — Wire the real agent loop (the Claude Code core)

*Everything else polishes a product that doesn't exist until this lands.*

1. **Refactor `AssistantController.run()` to delegate to `AgentLoop.run(task:)`.**
   The controller keeps only UI concerns: phase updates, card logging, session
   lifecycle. Delete the duplicated parse/validate/execute code (lines ~128–201).
2. **Thread confirmation through the loop.** `ToolRouterDispatch` already takes a
   `confirm` closure — pass the controller's confirm-card closure into the router
   the loop uses, so the chain pauses mid-flight on write actions exactly like a
   Claude Code permission prompt. Same for `presentFilePicker`.
3. **Per-step card logging.** Extend `AgentLoop.onActivity` into a typed callback
   (`onStep(call:result:)`) so each completed step logs an `ActionCard`
   immediately. The user watches cards land in the feed as the agent works —
   this is the "watch it work" feel that makes Claude Code trustworthy.
4. **Respond/no-op tool inside the loop.** The `respond` tool short-circuit
   currently lives in the controller; move the terminal-response handling into
   the loop so single-turn answers and multi-step chains share one code path.
5. **Cancel semantics.** Cancelling mid-chain keeps completed step cards
   (status stays `done`), marks the in-flight step `cancelled`, ends the session.
6. **Chain-depth guard for the floor tier.** Keep `maxSteps = 6` on 6 GB devices;
   consider 4 on 4 GB devices (longer context = bigger KV cache). Make it a
   config knob read from device RAM, decided during Milestone 3 profiling.

**Exit criteria:** integration test where a mock model chains 3 tool calls with
one confirmation in the middle → 3 cards in the store, correct statuses.
A real-device demo of "check my calendar tomorrow, then set a reminder at 8am"
completes as one session with two cards.

Files: `UI/AssistantController.swift` (major), `Agent/AgentLoop.swift` (hooks),
`kodai-consumerTests/AgentLoopTests.swift`.

---

## Milestone 2 — Model distribution & first-run experience

*Can't ship without it; blocks all real-device work at scale.*

1. **Decision: bundle for TestFlight/review, download for production.** The
   resolver already supports both — the missing pieces are UX and safety rails.
2. **Download UX:** `ModelDownloadView` with progress (bytes / ETA), background
   `URLSession` download that survives backgrounding, resume on relaunch,
   SHA256 verification, retry on failure. Gate the main UI on model readiness in
   `kodai_consumerApp.swift`.
3. **Disk guard:** refuse to start the download under 2 GB free; explain why.
4. **Corrupt/missing model recovery:** launch-time health check → recovery screen
   with re-download, never a crash (Workstream 7 item 1 folded in here).
5. **Model versioning:** persist a version id next to the GGUF; on mismatch after
   app update, re-resolve cleanly.

**Exit criteria:** fresh install on an airplane-moded phone with the bundled
build works immediately; fresh install of the download build completes the fetch
with a killed-and-relaunched app mid-download; corrupted GGUF shows recovery UI.

---

## Milestone 3 — Floor-device performance (iPhone 12/13, 4 GB)

*The "iPhone 14 and under" constraint is proven or broken here.*

1. **Memory ceiling:** Instruments (Allocations) during a 4-step chain on an
   iPhone 12. Target peak < 1.8 GB. If over: shrink context window, then thread
   count, then consider Q4_0. Document the measured ceiling in this file.
2. **Time-to-first-token:** target < 3 s warm, < 6 s cold on iPhone 12. If cold
   start exceeds that, add a model-loading interstitial (wolf animation).
3. **Thermal guard:** poll `ProcessInfo.thermalState`; at `.serious` pause
   between chain steps with a "cooling down" note card; never start a new
   inference at `.critical`.
4. **Adaptive watchdog:** replace the flat 45 s timeout with one scaled by
   measured tokens/sec on the current device (e.g. 3× the expected turn time).
5. **Background behavior:** backgrounding mid-chain → finish the current step if
   the OS allows, mark the rest `cancelled`, restore a coherent feed on return.
6. **Device-tier config:** one small `DeviceTier` type (RAM-based) that owns
   `maxSteps`, context length, `n_threads` — read by `RuntimeAgentModel` and
   `AgentLoop`.

**Exit criteria:** 10 consecutive multi-step tasks on a physical iPhone 12 or 13:
zero OOM kills, thermal never reaches `.critical`, all TTFT samples < 3 s warm.
Numbers recorded in this doc.

---

## Milestone 4 — Model quality: the eval bar

*A 1.2B model imitating Claude Code lives or dies on tool-call accuracy.*

1. **Eval dataset:** 100+ (input → expected tool call) pairs in `docs/prompts/`:
   ≥5 per tool, relative dates, ambiguous requests (should `respond`),
   out-of-surface requests (should `respond` with capabilities), 2–3-step chains.
2. **Run via Bench Lab** (harness already exists). Metrics: tool-name accuracy,
   parameter accuracy, ISO-8601 date correctness, chain completion rate.
   **Bar: >90 % single-step, >80 % 2-step, >70 % 3-step.**
3. **Prompt iteration** against failures: more few-shot examples, negative
   examples (reminder vs. calendar confusion is the known trap — see routing eval
   commits), stricter date-format instruction.
4. **If the bar isn't met** after prompt iteration: try Q5_K_M / Q6_K (must
   re-clear the Milestone 3 memory ceiling), then Qwen 2.5 1.5B, before
   considering anything ≥3B (which likely fails the iPhone 12 budget — that
   would force raising the floor to iPhone 14, a product decision to surface,
   not make silently).
5. **Garbage fallback:** if all three parse formats fail, show "I didn't
   understand that — try rephrasing," never raw model output.

**Exit criteria:** eval suite committed + runnable in one command; bar met on
the shipped quant; results table checked into `docs/prompts/`.

---

## Milestone 5 — Never crash, never confuse (error handling + a11y)

1. **Edge cases** (Workstream 7): permission revoked mid-session → structured
   error the agent explains; `web_fetch` 10 s timeout, no auto-retry; SwiftData
   migration plan for the v1 schema; keyboard avoidance; portrait-only lock.
2. **Loop edge cases as tests:** empty model output, unknown tool name, valid
   JSON that isn't a tool call, budget exceeded, cancel mid-inference.
3. **Accessibility** (Apple reviews for this): VoiceOver labels/hints on input
   bar, action cards, confirm card, tabs; Dynamic Type through AX5 (cards stack
   vertically at large sizes); reduce-motion disables dots/card/constellation
   animations.

**Exit criteria:** `xcodebuild build test` green with the new edge-case tests;
full VoiceOver pass of the critical path (type → confirm → card) by a human;
no layout breakage at AX5.

---

## Milestone 6 — TestFlight beta

1. Distribution signing, archive, upload; **bundled-model build** for testers.
2. 5–10 testers: power users (stress chains), non-technical (UX friction),
   one VoiceOver user.
3. "Send Feedback" button in Settings → pre-filled mail (device, iOS, version).
4. Crash reports via Xcode Organizer only — **zero analytics**, ever; it's the
   product promise.
5. Two-week bake with a known-issues note per build; fix P0/P1s.

**Exit criteria:** ≥2 weeks of beta, no unresolved crash clusters, top-3
friction items fixed or consciously deferred.

---

## Milestone 7 — App Store submission

1. Metadata: name, subtitle, keywords, description — position as *private,
   offline, on-device agent; no account, no cloud, no tracking*.
2. Screenshots (6.7" + 6.1"): feed with cards, confirm card, upcoming,
   onboarding privacy screen, Siri shortcut.
3. Privacy policy hosted on the CTXA site; App Privacy questionnaire = "no data
   collected" (must be literally true — audit any network call besides
   user-initiated `web_fetch` and the model download).
4. Review notes: on-device LFM 2.5 via llama.cpp, no server-side AI, which
   distribution path the review build uses, confirmation-before-write design.
5. Entitlements audit; usage-description strings for every framework; 1024×1024
   icon (pick pawprint vs. constellation); category Productivity; rating 4+.

**Exit criteria:** submitted. Rejection contingencies pre-written for the two
likely flags: model download size (answer: bundled review build) and "minimal
functionality without permissions" (answer: agent responds gracefully with
zero permissions — demoed in review notes).

---

## Post-launch track (ordered, from NEXT_STEPS.md)

1. **Agent context & user memory** (WS 11) — preferences block in the system
   prompt, ≤200 tokens, visible/editable in Settings. Biggest "feels personal" win.
2. **Multi-step intelligence** (WS 5) — plan-then-execute notes, resource-ID
   threading in `StateAnchor`, chain-length ceiling documented.
3. **UI polish** (WS 9) — card entrance animation, custom confirm transition,
   color/type system.
4. **Widget expansion** (WS 12) — upcoming widget, lock-screen widget, Live
   Activity for in-flight chains (the Claude-Code-progress-bar analog).
5. **Tool surface growth** (WS 10) — Photos first (highest value/feasibility),
   then Shortcuts `run_shortcut` (biggest capability multiplier). One domain at
   a time, full test coverage before the next.
6. **CI** (WS 13) — GitHub Actions `xcodebuild build test` on push.

## Non-goals (unchanged)

No cloud, no accounts, no IAP for v1, no iPad/Mac, no analytics, no third-party
integrations.

---

## Sequencing rationale

M1 first because every later milestone tests, profiles, and demos *the agentic
loop* — profiling the single-turn flow would produce numbers for the wrong
product. M2/M3 next because they're the physical constraints that could force
model or floor-device changes, which would invalidate M4 eval results if done
earlier. M4 before beta so testers exercise a model that mostly works. M5–M7
are the standard ship gauntlet. Estimated critical path: M1 (2–4 days), M2
(2–3 days), M3 (3–5 days incl. device time), M4 (3–5 days), M5 (3–4 days),
M6 (2+ weeks bake), M7 (2–3 days prep) → **~6–8 weeks to submission**, dominated
by the beta bake.
