# kodAI Consumer — Implementation Plan (v1)

Status: **Phases 0–3 ✅ · native tool-calling design (no GBNF) · WORKING END-TO-END ON DEVICE — "remind me tomorrow 6am to feed the dogs" → confirm card → reminder written to Apple Reminders** · Last updated: 2026-06-25

> **Design note (supersedes the GBNF/forced-JSON language below):** the shipped
> app uses **LFM2's native Pythonic tool-calling** — `[tool(arg="…")]` between
> `<|tool_call_start|>`/`<|tool_call_end|>` — not a GBNF grammar and not
> forced-JSON. Reliability comes from three runtime/prompt facts, not a grammar:
> (1) the prompt is tokenized with `parse_special=true` so the ChatML control
> tokens are real; (2) a **firm** system prompt ("always call exactly one tool;
> never refuse"); (3) the assistant turn is **primed with `<|tool_call_start|>`**
> so the model continues straight into a call. Measured on the real LFM2.5-1.2B:
> soft prompt ≈ 3–5/12 valid calls → firm prompt + primer = **24/24**. Tool
> surface is **5 tools** (the 3 creates + `save_file`/`read_file`), all writes
> confirmed. Sections 2/4/5/6 below are updated to this design; older GBNF notes
> are kept only as history.

### Progress log
- **Phase 0** — KodaiKernel+KodaiRuntime linked into the Xcode project; template stripped; engine probe builds. Download-on-first-run wired via `LocalModelConfiguration.downloadURL` → `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` (verified live, 731 MB).
- **Phase 1** — LFM2 chat template verified from the GGUF (ChatML + native `<|tool_call_*|>` tokens + `List of tools:` system rendering). Built `Assistant/`: `AssistantTool` (3-tool schema + JSON defs), `SystemPromptBuilder` (datetime + forced-JSON + tools + few-shot), `ToolCallParser` (wrapped/bare JSON + Pythonic fallback), `ToolCallValidator` (typed + future-date + end>start). 15 unit tests pass on iPhone 17 sim. Probe wired end-to-end (system prompt → stream → parse → validate → typed call).
- **Phase 2** — `Agent/`: `StateAnchor` (compact JSON, re-injected each turn), `ToolResult` (deterministic structured feedback), `AgentLoop` (infer→parse→validate→execute→feed-back; terminal detection; `maxSteps=6`; one silent retry then error step). Built against `AgentModel`/`ToolRouter` protocols. 6 loop tests pass (single/multi-step termination, budget cap, retry-then-recover, retry-then-error, state injection).
- **Pending live-model gate** (Phases 0–2): run the app once to download the GGUF and confirm real streaming + canonical prompts → correct typed calls, then drive the loop end-to-end.
- **Phase 5 hardening — GBNF attempt, later REVERTED** *(historical)* — first device runs showed the 1.2B *chatting* instead of tool-calling. The first fix tried **GBNF-constrained decoding** (`SamplerKnobs.grammar` → `llama_sampler_init_grammar`) forcing bare-JSON. The standalone rebuild then **dropped the grammar** in favour of LFM2's native tool format — but shipped it *without* the reliability scaffolding, so the model refused/narrated again (see the two "Something went wrong" device screenshots). The grammar plumbing no longer exists in KodaiRuntime.
- **Phase 3 (code-complete)** — `RuntimeAgentModel`, `EventKitToolRouter` (confirm-then-execute; calendar write-only, reminders/lists full), `AssistantController` (`@Observable`, bridges confirm to a SwiftUI sheet via a continuation), `AssistantView` (activity log + summary + confirm sheet). Info.plist usage strings added.
- **2026-06-25 — moved into the `kodai` monorepo + tool-calling reliability fixed (commit 931bb08 and follow-up).** kodai-consumer's stray nested `.git` was removed and its files committed to `kodai`. Root-caused why tool-calls never fired and fixed it in the **shared** `KodaiRuntime` + the consumer prompt:
  1. **`parse_special=true`** in `LlamaContextWrapper.tokenize` — the hand-built ChatML prompt's `<|im_start|>`/`<|im_end|>` were being tokenized as literal text, so the model never saw turn boundaries (chat tolerates it; tool-calling collapses).
  2. **Prompt whitespace aligned** to LFM2's embedded chat template (verified by dumping `tokenizer.chat_template` from the GGUF — it's ChatML + inlined `List of tools:`).
  3. **Stop decode on `<|tool_call_end|>`** (LFM2 doesn't mark it EOG) — halves generation length.
  4. **Firm system prompt** (always call exactly one tool; never refuse) + **assistant primed with `<|tool_call_start|>`** via a new optional `assistantPrimer` threaded through `generate`/`formatChatPrompt`. This is the big reliability lever: ~40% → **24/24** measured.
  - Verified against the real model on macOS via a throwaway harness.
- **2026-06-25 — EventKit save fixed (commit 97c725e).** With tool-calls working,
  confirming a reminder failed with `no_reminder_list_available`: the model omits
  `list`, so the save took the nil-list path which only returned
  `defaultCalendarForNewReminders()` — nil when no *default* list is set (even
  with writable iCloud lists present). Fix in `EventKitToolRouter`: one
  long-lived `EKEventStore` (static, not per-call) + fallback default → first
  writable reminders list → create a "kodAI" list on the best source; friendly
  error string. **Requires Reminders enabled in the user's iCloud.**
- **2026-06-25 — CONFIRMED WORKING ON A REAL iPhone.** "Create me a reminder to
  feed the dogs tomorrow at 6am" → confirm card (correct title/date/notes) →
  Confirm → the reminder appears in Apple Reminders ("Feed the dogs · Tomorrow
  6:00 AM"). Phase 3 exit gate met. Next: Phase 4 task-log UI polish → Phase 6
  TestFlight.

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
| Tool-call format | **LFM2 native Pythonic** — `[tool(arg="…")]` inside `<|tool_call_start|>…<|tool_call_end|>`; assistant turn primed with `<|tool_call_start|>` to force it. No GBNF, no forced-JSON. `ToolCallParser` accepts native-wrapped, bare-JSON, and Pythonic |
| Sampler — routing turn | temp 0.3 / max_tokens 200 (firm prompt + primer make this near-deterministic; greedy also works) |
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

## 4. Tool layer — v1 (5 tools; all writes confirm, reads auto-run)

| Tool | Args | Class | Access |
|---|---|---|---|
| `create_calendar_event` | title, start_iso, end_iso?, location?, notes? | write → confirm | calendar write-only |
| `create_reminder` | title, due_iso?, list?, notes? | write → confirm | reminders full |
| `add_to_list` | list, item | write → confirm | reminders full (named list) |
| `save_file` | name, content | write → confirm | Files app (security-scoped) |
| `read_file` | purpose | read → auto-run picker | Files app (security-scoped) |

Small toolbox = high routing accuracy on a 1.2B. Definitions live in
`AssistantToolCatalog.toolDefinitionsJSON`; descriptions carry negations
("NOT for…") to keep the two date-ish tools apart. Reads (`get_reminders`,
`complete_reminder`, etc.) and the Photos/Contacts frameworks are deferred.

## 5. Prompt design (`SystemPromptBuilder` + the runtime primer)

System turn = **firm persona** ("Complete the request by calling exactly one
tool. You ALWAYS call a tool — never refuse, never apologize, never reply in
prose, never say what you 'can only' do.") → injected **current datetime + tz**
→ **`List of tools: [<json>]`** (exactly how LFM2's chat template renders tools).
No few-shot needed once primed; no JSON/wrapper rules (the native format + primer
handle structure).

The decisive piece is **not** in the prompt text — it's the runtime priming the
assistant turn with `<|tool_call_start|>` (`RuntimeAgentModel.toolCallPrimer` →
`formatChatPrompt(assistantPrimer:)`). The model resumes *inside* a tool call, so
its first move can't be a refusal. Firm prompt alone ≈ 5/12; **+ primer = 24/24**.

> Trade-off: priming forces a tool call on *every* input, including unsupported
> ones ("what's the weather"). For an outcome-focused v1 that's acceptable — the
> confirm card is the safety net. A terminal-text escape would need the GBNF
> `tool_call | terminal_text` design, which v1 intentionally drops.

## 6. Runtime changes (KodaiRuntime — shared-package edits, all shipped 2026-06-25)

1. **`parse_special=true`** in `LlamaContextWrapper.tokenize` — the one-line root
   cause; without it the ChatML control tokens are literal text and tool-calling
   collapses to prose.
2. **Prompt whitespace** in `formatChatMLPrompt` aligned to LFM2's embedded
   template (`<|im_start|>{role}\n{content}<|im_end|>\n` + trailing assistant
   newline). The hand-rolled ChatML now matches the template; tools are inlined
   as `List of tools:` exactly as the template does (verified from the GGUF).
3. **Stop decode on the `<|tool_call_end|>` token id** (resolved once at load via
   `singleSpecialTokenID`; LFM2 doesn't mark it EOG) — clean cut, ~half the tokens.
4. **`assistantPrimer`** optional param threaded `generate → formatChatPrompt`;
   the consumer passes `<|tool_call_start|>`. Default nil keeps the educational
   iOS + macOS chat apps unaffected.
5. Per-turn sampler profiles via existing `SamplerKnobs` (temp 0.3 routing turn).

> The earlier plan listed a grammar sampler here; it is **not** in the codebase.
> Native format + primer replaced it.

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
| Goal drift @1.2B | State anchor re-injected each loop + MAX_STEPS + low-temp routing (v1 UI is single-shot, so drift is mostly moot) |
| Model refuses / narrates instead of calling a tool | **`<|tool_call_start|>` primer** (forces a call) + firm prompt + `parse_special=true` — the actual v1 failure mode; measured ~100% fixed |
| Tool-result hallucination | Structured compact JSON results fed back; never free-text outcomes |
| Destructive / write gating | Confirm-every-write; loop pauses synchronously on writes |
| Mid-loop tool failure | Structured error result → 1 bounded retry → surface to user; clean abort |
| Context overflow across loops | Result truncation/summarization + compact anchor + 4096 ctx + trim oldest results |
| Non-termination | Single-shot v1 UI (one call → confirm → done); multi-step loop keeps TerminalDetector + hard MAX_STEPS |
| Calendar write-only ⇒ no reads | Reschedule/conflict flows out of v1 scope |

## 11. Acceptance metrics (Phase 5 eval harness, reusing KodaiBenchKit pattern)

Routing accuracy · arg correctness · valid-JSON rate · **task-success rate** (correct
end state) · goal-drift rate · avg loops/task · p50/p95 first-token & full-task latency —
all measured on a real device.

## 12. Out of scope for v1

Shortcuts integration · third-party app actions · multi-turn open chat · Photos / Files /
Contacts frameworks · voice input · calendar reads / rescheduling.
