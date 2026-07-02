# kodai-consumer: An Essay in Two Parts

*A technical report and a plain-language summary of a private, offline, on-device iOS action agent.*

---

## Part I — Technical Report

### 1. What it is

kodai-consumer is a standalone iOS application that turns natural-language requests into real actions on the device — calendar events, reminders, contacts, files, clipboard, notifications, and web fetches — using a language model that runs entirely on the phone. There is no server, no account, no analytics, and no data egress. The model is not the product; it is the parser. The product is a reliable pipeline from "what the user typed" to "a confirmed, executed, auditable device action."

It is deliberately **not a chatbot**. The interface is a command surface: a feed of structured action cards, not a scrolling wall of assistant prose. The closest analogues are Raycast on macOS, or what Siri was supposed to be.

### 2. The model and inference stack

The agent runs **LFM 2.5 1.2B Instruct**, quantized to Q4_K_M GGUF (~700 MB), executed through llama.cpp via the shared **KodaiCore** Swift package (`KodaiKernel` for inference/context/tool schemas, `KodaiRuntime` for the `LocalModelRuntime` wrapper). Cold start is roughly 2–4 seconds on an iPhone 14 or newer. The model ships bundled in the binary (or as an optional one-time download with progress UI), after which the app is fully functional in airplane mode.

A 1.2B-parameter model is small by contemporary standards, and that is the point: the engineering problem is not making a small model eloquent, but making it *reliable* as a tool-call emitter. Three mechanisms carry that load:

1. **Grammar-constrained decoding.** Tool calls are sampled under a GBNF grammar matched to the model's native dialect, which eliminated parse failures outright — 100% of tool calls now parse in the native format, with zero fallback events in evaluation. The grammar must track the model's actual emission dialect; a mismatched grammar is worse than none.

2. **A three-tier parser with confidence tracking.** `ToolCallParser` accepts LFM2's native `<|tool_call_start|>…<|tool_call_end|>` format first, then bare JSON, then a Pythonic call format, recording which tier matched via `ParseConfidence` (.native / .json / .pythonic). With grammar sampling on, the fallbacks are now a belt-and-suspenders layer rather than a load-bearing one.

3. **Deterministic repair and routing rules.** A post-parse pass normalizes the failure modes a small model actually exhibits — drifted file-path roots, near-miss argument shapes — before validation. Combined with a routing-rule layer, this took the ACTIONS benchmark from 77.5% to 90.0% task success without touching the model.

### 3. The agent loop

Execution follows a bounded multi-step loop in `AgentLoop.swift`:

```
infer → parse → validate → (confirm if write) → execute → feed result back
```

- The model may chain up to **6 tool calls** per task before it must emit a terminal response.
- An invalid call gets **one silent retry**; a failed tool execution (not user-cancelled) also retries once automatically, with live retry activity surfaced in the UI.
- A `StateAnchor` injects current task state into each turn so the small model stays grounded across steps.
- Tool results return as structured `ToolResult` values, not free text, and are fed back into context.

Dispatch goes through a `ToolRouter` protocol to six domain routers (EventKit, Contacts, File, Clipboard, Notification, System). Hard limits — no silent SMS, no reading Mail, no settings changes, no arbitrary code — are enforced **at the router level**, not merely stated in the prompt. The prompt asks for good behavior; the routers make bad behavior impossible.

### 4. Confirmation as an architectural primitive

Every write action (create event, save file, schedule notification, …) produces a **confirm card** the user must accept before execution. Read/query tools skip confirmation and render directly. This is the app's core trust contract: the model proposes, the human disposes. Resolved parameters (e.g., normalized file paths) are shown *before* confirmation, so the user approves what will actually happen, not what the model loosely said.

### 5. Persistence and UI

State lives in **SwiftData** via `ActionStore` (deliberately opted out of CloudKit — actions never sync off-device). The UI is a three-tab layout:

- **Feed** — the activity stream: action cards with domain icon, one-line summary, timestamp, and status chip (Done / Pending / Failed / Cancelled); user prompts as compact rows; agent clarifications as indented notes.
- **Upcoming** — a grouped timeline (Today / Tomorrow / This Week / Later) merging agent-created and pre-existing events and reminders.
- **Archive** — the audit log: completed actions grouped by collapsible session, filterable by domain.

Additional surfaces reuse the same tool layer rather than duplicating it: an input-only **WidgetKit** widget deep-linking via `kodai://task?q=`, and **App Intents** exposing the tools to Siri, Shortcuts, and Spotlight. Work in progress on the current branch adds **Toolflows** — user-composable multi-step tool sequences with their own store, UI, and App Intents — plus a How-To view for discoverability.

### 6. Testing and verification posture

The parser, validator, repair passes, and stores carry unit tests (including the new `ToolflowStoreTests`); routing quality is measured against an ACTIONS benchmark suite through a separate bench-lab harness with a CLI runner and dashboard. Verification on this project favors compile-only device builds over simulators.

### 7. Honest constraints

The iOS sandbox draws the boundary: no silent messaging, no inbox reading, no system-settings changes, no app installation, file access limited to the app sandbox / iCloud Drive / user-shared folders. A 1.2B model will still occasionally misread intent — which is exactly why confirmation cards, deterministic repair, bounded loops, and the audit trail exist. The system is designed so that the *cost* of a model error is a declined confirm card, never a wrong action.

---

## Part II — Marketing Summary (in regular-people terms)

### The one-sentence version

**kodai is an assistant that lives on your iPhone instead of in someone's data center — you tell it what to do in plain English, it shows you what it's about to do, and nothing you say ever leaves your phone.**

### What that actually means for you

Every mainstream AI assistant works the same way: you speak or type, your words are shipped to a company's servers, processed there, and the answer is shipped back. That's true of Siri for many requests, and of ChatGPT, Gemini, and Alexa for essentially all of them. Your reminders, your calendar, the names of the people you call — it all transits someone else's computers, under someone else's privacy policy.

kodai flips that. The entire AI — the actual "brain" — is a compact model stored on your phone, like a photo or a song. When you type *"remind me to call mom tomorrow at 9"* or *"what's on my calendar Friday?"*, everything happens on the device in your hand. There is:

- **No account.** No sign-up, no email, no password. Install it and use it.
- **No tracking.** Zero analytics, zero telemetry, zero third-party code phoning home.
- **No internet needed.** Turn on airplane mode; nothing changes.
- **No surprise actions.** Before kodai creates an event, saves a file, or changes anything at all, it shows you a card describing exactly what it's about to do. You tap to approve. Nothing happens without your OK.

### Who this helps

- **Anyone who's privacy-conscious** — journalists, lawyers, therapists, executives, or just people who don't love the idea of their to-do list living in a cloud. There's no data to breach because no data is collected.
- **People who fly, commute, or live with bad signal.** The assistant works identically at 35,000 feet, in the subway, or off-grid.
- **People burned by assistants that "helpfully" do the wrong thing.** The confirm-first design means the worst case is you tap "cancel" — not discovering a meeting was created on the wrong day.
- **Anyone who wants Siri to actually do things.** It handles calendars, reminders, contacts, files, notes, clipboard, and alerts — and it plugs into Siri, Shortcuts, and your home screen widget, so it fits how you already use your phone.
- **People who like a record.** Every action lands in a feed and an archive: what you asked, what was done, and when. Your assistant keeps receipts.

### Why it's believable

The hard part of an on-device assistant isn't the AI sounding smart — it's the AI being *dependable* with a brain small enough to fit on a phone. That's where the engineering went: the model is constrained so it can only produce valid commands, its common slip-ups are automatically corrected before you ever see them, and everything it wants to change is held for your approval. In benchmark testing, the current build completes 9 out of 10 real-world action tasks correctly, and every command it produces is machine-valid — and when it does misunderstand, the design guarantees you catch it before anything happens.

### The bottom line

Cloud assistants ask you to trade privacy for convenience. kodai's bet is that with the right engineering, you shouldn't have to trade anything: a genuinely useful assistant, running entirely on hardware you own, that treats your permission as the final word.

*Free. No in-app purchases. No cloud. Your AI, entirely on-device.*

---

*Prepared July 2, 2026 · Based on the kodai-consumer codebase, README, and App Store submission package.*
