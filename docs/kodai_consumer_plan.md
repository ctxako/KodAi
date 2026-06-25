# kodAI Consumer — Implementation Plan (v1)

Status: **Phase 0 ✅ · Phase 1 ✅ · Phase 2 ✅ · Phase 3 code-complete (awaiting first build/run on device/sim)** · Last updated: 2026-06-25

### Progress log
- **Phase 0** — KodaiKernel+KodaiRuntime linked into the Xcode project; template stripped; engine probe builds. Download-on-first-run wired via `LocalModelConfiguration.downloadURL` → `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` (verified live, 731 MB).
- **Phase 1** — LFM2 chat template verified from the GGUF (ChatML + native `<|tool_call_*|>` tokens + `List of tools:` system rendering). Built `Assistant/`: `AssistantTool` (3-tool schema + JSON defs), `SystemPromptBuilder` (datetime + forced-JSON + tools + few-shot), `ToolCallParser` (wrapped/bare JSON + Pythonic fallback), `ToolCallValidator` (typed + future-date + end>start). 15 unit tests pass on iPhone 17 sim. Probe wired end-to-end (system prompt → stream → parse → validate → typed call).
- **Phase 2** — `Agent/`: `StateAnchor` (compact JSON, re-injected each turn), `ToolResult` (deterministic structured feedback), `AgentLoop` (infer→parse→validate→execute→feed-back; terminal detection; `maxSteps=6`; one silent retry then error step). Built against `AgentModel`/`ToolRouter` protocols. 6 loop tests pass (single/multi-step termination, budget cap, retry-then-recover, retry-then-error, state injection).
- **Pending live-model gate** (Phases 0–2): run the app once to download the GGUF and confirm real streaming + canonical prompts → correct typed calls, then drive the loop end-to-end.
- **Phase 5 hardening — pure-emitter pivot (build-verified, awaiting device run)** — first device runs showed the 1.2B *chatting* instead of tool-calling (hallucinated "I've created…", `|>` leaks). Fix: **GBNF-constrained decoding** added to the runtime (`SamplerKnobs.grammar` → `llama_sampler_init_grammar` in the sampler chain) forcing the model to emit a bare-JSON tool call (`ToolGrammar`); **single-shot, pure-emitter flow** (`AssistantController`) — one constrained turn → parse → validate (1 retry) → confirm card → EventKit → **deterministic** result line. Model never writes user-facing prose. System prompt simplified (no wrapper/JSON rules — grammar enforces). Keyboard dismisses on scroll; dim raw-output line for debugging. Multi-step agentic loop retained + tested but not used by v1 UI. 21/21 tests green.
- **Phase 3 (code-complete, not yet built/run)** — `RuntimeAgentModel` (streams one turn, collects tokens, surfaces download/load status, maps `.tool` → labeled user turn); `EventKitToolRouter` (confirm-then-execute; calendar write-only, reminders/lists full access; auto-creates a named reminder list); `AssistantController` (`@Observable`, bridges the router's confirm step to a SwiftUI sheet via a continuation); `AssistantView` (streaming activity log + summary + confirm sheet — the non-chatbot surface). Info.plist usage strings added. `ContentView` probe removed. **Not compiled by me (per request); awaiting your first build/run.**

## 1. Objective & mental model

A local, **offline, agentic** assistant for iOS that executes first-party device
tasks via tool calling. Mental model: *Claude Code for iPhone* — but instead of
writing code it runs device actions. **Outcome-focused, not conversational.**

- 100% on-device after a one-time model download. No account, no cloud, no egress.
- The privacy claim is structural: a cloud assistant *can't* make it; LFM2 on-device is built for it.
- v1 acts on **Calendar + Reminders** (EventKit). Photos / Files / Contacts are v1.1+.

## 2. Locked parameters

| | Value |
|---|---|
| Model | `LFM2.5-1.2B-Instruct-Q4_K_M`, llama.cpp (vendored LlamaCPP b9775), download-on-first-run |
| Context size | 4096 (bumped from 2048; fall back to 2048 if prefill latency hurts on old devices) |
| Tool-call format | **Forced JSON** via system-prompt override of LFM2's default Pythonic; GBNF-hardened (Phase 5) |
| Sampler — routing turn | temp 0.15 / top_p 0.9 / top_k 40 / min_p 0.05 / repeat 1.05 / max_tokens ≤128 |
| Sampler — terminal/summary turn | temp 0.4 / max_tokens 256 |
| `MAX_STEPS` | hard **6**; soft warn at 5; exceed → surface to user, never continue silently |
| Gating | **confirm every write**; reads auto-run (v1 has no reads — all 3 tools are writes) |
| Reuse | KodaiKernel + KodaiRuntime + LlamaCPP only (drop KodaiPersistence + all educational UI) |
| Calendar access | `requestWriteOnlyAccessToEvents()` → create-only, **no reads** |
| Reminders access | `requestFullAccessToReminders()` → read + write |
| Input | Text only in v1; voice decoupled and deferred |

## 3. The agentic loop (engine spec)

Each loop = 1 inference + (at most) 1 tool call + 1 result fed back into context.
Loop continues until the model emits a terminal (non-tool-call) response.

```
state = StateAnchor(original_task: userTask, steps_completed: [], next: nil)
messages = [systemPrompt(tools, datetime), user(userTask)]
step = 0

while step < MAX_STEPS:
    messages.inject(state)                       // re-anchor every loop
    resp = lfm.infer(messages, profile: .routing)
    call = ToolCallParser.parse(resp)            // JSON-in-tokens, Pythonic fallback

    if call == nil:                              // terminal response → done
        return Summary(resp, state)

    if !ToolValidator.validate(call):            // garbage → 1 silent retry, else error step
        messages.append(errorResult); step += 1; continue

    // confirm-all-writes (every v1 tool is a write)
    decision = await ConfirmSheet(call)          // accept / edit / cancel
    if decision == .cancel { state.note("cancelled \(call.name)"); continue }
    call = decision.editedCall

    result = ToolRouter.execute(call)            // EventKit / structured error
    messages.append(ToolResult.format(result))   // deterministic compact JSON
    state.update(completed: call, result: result)
    step += 1

return BudgetExceeded(state)                      // surface, never silently loop
```

**Invariants:** state anchor re-injected each loop (goal never drifts) · terminal =
model stops calling tools · tool results are structured JSON, never free text (model
can't hallucinate an outcome it can read back) · loop pauses synchronously on every write.

### State anchor (re-injected each loop)
```json
{"original_task":"add eggs and milk to groceries",
 "steps_completed":["added Eggs to Groceries"],
 "next":"add Milk to Groceries"}
```

### Deterministic tool-result format (fed back, truncated)
```json
{"tool":"create_reminder","status":"ok","result":{"title":"Call mom","due":"2026-06-26T09:00"}}
{"tool":"create_calendar_event","status":"error","error":"permission_denied"}
```

## 4. Tool layer — v1 (trimmed to 3 creates, all confirm)

| Tool | Args | Class | Access |
|---|---|---|---|
| `create_calendar_event` | title, start_iso, end_iso?, location?, notes? | write → confirm | calendar write-only |
| `create_reminder` | title, due_iso?, list?, notes? | write → confirm | reminders full |
| `add_to_list` | list, item | write → confirm | reminders full (named list) |

Tiny toolbox = highest routing accuracy on a 1.2B. Reads (`get_reminders`,
`complete_reminder`, etc.) and the Photos/Files/Contacts frameworks are deferred.

## 5. Prompt design

System prompt (~400 tok budget): persona ("you DO tasks; call exactly one tool per
step; emit JSON only") → **forced-JSON rule overriding Pythonic** → injected **current
datetime + tz** → **tool defs as JSON array** (`{name, description w/ negations, parameters}`)
→ 2–3 multi-step few-shot examples → state-anchor slot.

GBNF grammar (Phase 5): `response := tool_call_json | terminal_text`, with
`tool_call_json` constrained to exactly the 3 tool schemas.

## 6. Runtime changes (KodaiRuntime — the only shared-package edits)

1. Tools-aware system-turn rendering (inject JSON tool defs).
2. Register `<|tool_call_end|>` as a stop string + tool-call boundary detection.
3. Fix `formatChatPrompt` to honor LFM2's embedded chat template instead of the
   hard-coded ChatML in `LlamaContextWrapper.swift` — **first task: verify the
   template by dumping `tokenizer.chat_template` from the GGUF.**
4. Grammar sampler (`llama_sampler_init_grammar`) — Phase 5.
5. Per-turn sampler profiles via existing `SamplerKnobs` (no change needed).

## 7. UI — task surface (not a chatbot)

- **TaskLogView**: streaming steps, each with a status icon (running / done /
  awaiting-confirm / error) → collapses to a **SummaryCard** on completion.
- **ConfirmSheet**: appears on every write — shows the proposed action, allows inline
  edit, accept/cancel.
- **AmbiguitySheet**: only when the agent needs disambiguation.
- **InputBar**: text in v1.
- No persistent chat thread.

## 8. Module layout (new app code)

`Agent/` (AgentLoop, StateAnchor, LoopBudget, TerminalDetector) ·
`Tools/` (ToolSchema, ToolCallParser + Pythonic normalizer, ToolValidator, ToolRouter,
EventKitTools, ToolResultFormatter) ·
`Prompt/` (SystemPromptBuilder, FewShot) ·
`Inference/` (InferenceService over `LocalModelRuntime`, SamplerProfiles) ·
`UI/` (TaskLogView, SummaryCard, ConfirmSheet, AmbiguitySheet, InputBar, OnboardingPermissions) ·
`Store/` (lightweight action/run log).

## 9. Phased build sequence

| Phase | Goal | Exit gate |
|---|---|---|
| **0 — Engine** | Wire KodaiKernel+Runtime into the project, strip template, download+prewarm, stream a reply | Cold launch → on-device stream; offline after download; zero egress |
| **1 — Single tool-call** | Runtime tools-rendering + stop-token + template fix; ToolSchema; SystemPromptBuilder; Parser+Validator; render parsed call (no exec) | Canonical prompts → correct typed EventKit calls; garbage recovers via retry |
| **2 — Loop engine** | AgentLoop: state anchor, result feedback, terminal detect, MAX_STEPS, error/retry (tools mocked) | Multi-step task runs N loops, terminates, no drift; budget enforced |
| **3 — EventKit exec + confirm** | EventKitTools (3 creates), permissions + Info.plist, ConfirmSheet on every write wired into loop, deterministic results fed back | Real end-to-end; every write confirmed; items appear in system apps |
| **4 — Task-log UI** | Streaming steps + status icons → summary card; ambiguity modal; remove chat paradigm | Full non-chatbot surface |
| **5 — Hardening** | GBNF (tool_call \| terminal) constrained to schema; sampler profiles; eval harness | ~100% valid-call rate; routing/task-success above bar; loop metrics captured |
| **6 — Polish + ship** | Onboarding/priming, states, egress audit, privacy label, TestFlight | TestFlight build; privacy claims verifiable on device |

## 10. Known hard problems → mitigations

| Problem | Mitigation |
|---|---|
| Goal drift @1.2B | State anchor re-injected each loop + MAX_STEPS + low-temp routing + GBNF |
| Tool-result hallucination | Structured compact JSON results fed back; never free-text outcomes |
| Destructive / write gating | Confirm-every-write; loop pauses synchronously on writes |
| Mid-loop tool failure | Structured error result → 1 bounded retry → surface to user; clean abort |
| Context overflow across loops | Result truncation/summarization + compact anchor + 4096 ctx + trim oldest results |
| Non-termination | Grammar allows terminal text + TerminalDetector + hard MAX_STEPS |
| Calendar write-only ⇒ no reads | Reschedule/conflict flows out of v1 scope |

## 11. Acceptance metrics (Phase 5 eval harness, reusing KodaiBenchKit pattern)

Routing accuracy · arg correctness · valid-JSON rate · **task-success rate** (correct
end state) · goal-drift rate · avg loops/task · p50/p95 first-token & full-task latency —
all measured on a real device.

## 12. Out of scope for v1

Shortcuts integration · third-party app actions · multi-turn open chat · Photos / Files /
Contacts frameworks · voice input · calendar reads / rescheduling.
