# kodai-consumer — Stabilization + chatbot-dev UI Port (working prompt)

> Hand this to a fresh thread: "read `docs/kodai_consumer_rebuild_prompt.md` and execute it."
> Work happens **primarily in `kodai-consumer/`**. "Direct port" = copy/adapt the counterpart
> in `kodai_ios/kodAI_chatbot_dev/kodAI_chatbot_dev/`.

## Context (what this app is, where it's at)

- **kodai-consumer** is an on-device, offline tool-calling assistant for iOS. Mental model: a private
  assistant that turns plain requests ("remind me to text mom at 6") into real device actions
  (Reminders / Calendar) via EventKit. Model: **LFM2.5-1.2B-Instruct (GGUF, llama.cpp)** through the
  shared **KodaiCore** package (`KodaiKernel` + `KodaiRuntime`). See `docs/kodai_consumer_plan.md` for
  the full v1 plan.
- **Built + working:** `ToolCallParser`, `ToolCallValidator`, `EventKitToolRouter`, the single-shot
  "pure emitter" flow, confirm card, deterministic result copy. 21 unit tests green.
- **The flow:** one model turn emits a tool call → parse → validate (1 retry) → confirm card →
  EventKit → deterministic result line. The model produces **no** user-facing prose.

## Confirmed crash (do not re-litigate — GBNF is removed, not fixed)

A GBNF grammar was added to force tool calls. It crashed via an **uncaught C++ exception**:

```
llama_grammar_accept_token → llama_sampler_chain_accept → LlamaContextWrapper.decode
libc++abi: terminating due to uncaught exception of type std::runtime_error:
  Unexpected empty grammar stack after accepting piece: [ (568)
```

Swift cannot catch C++ exceptions, so any grammar dead-end is an unrecoverable hard crash.
**GBNF must be removed.** Reliable tool-calling comes instead from LFM2's native trained format.

---

## Items 1–3 — logic (in kodai-consumer + shared KodaiRuntime)

### 1. Remove GBNF entirely (stops the crash)
- Delete `kodai-consumer/kodai-consumer/Assistant/ToolGrammar.swift`.
- `Agent/RuntimeAgentModel.swift`: remove the `grammar` property and the `knobs.grammar` / temp /
  maxTokens override. Keep a fixed tool-turn knobs (temperature ~0.3, **no grammar**).
- `UI/AssistantController.swift`: remove `model.grammar = ToolGrammar.toolCall`.
- **Shared** `KodaiCore/Sources/KodaiRuntime/LlamaContextWrapper.swift`: remove the grammar-sampler
  block in `makeSamplerChain` and revert its signature to `makeSamplerChain(_ knobs:)`; revert the two
  call sites (drop the `model:` argument).
- **Shared** `KodaiCore/Sources/KodaiKernel/Inference/SamplerKnobs.swift`: revert the `grammar` field.
- **Accept:** no `llama_sampler_init_grammar` reference remains anywhere.

### 2. Restore LFM2's native tool prompt
- `Assistant/SystemPromptBuilder.swift`: rebuild in the format LFM2 was **trained** on — a terse
  instruction + injected current datetime/timezone + tools rendered as `List of tools: [<json>]`
  using the existing `AssistantToolCatalog.toolDefinitionsJSON`. This mirrors the GGUF chat template's
  `{%- if tools -%}` branch. Drop the "reply in plain text" escape.
- Parsing is unchanged: `ToolCallParser` already extracts `<|tool_call_start|>…<|tool_call_end|>`,
  bare JSON, and Pythonic; `DisplayText.strippingModelTokens()` cleans any leaked special tokens.
- `AssistantController`: single-shot stays. If the parser returns nil (model chatted instead of
  calling) → graceful fallback: "I can only set reminders, calendar events, and lists right now."
- Update `kodai-consumerTests/SystemPromptBuilderTests.swift` to assert the native format.
- **Accept:** "remind me to text mom at 6" → model emits a tool call the parser catches → confirm
  card appears. *(Reliability is the key risk — see Risks.)*

### 3. Generation watchdog (nothing can freeze again)
- `Agent/RuntimeAgentModel.swift`: expose `cancel()` → `InferenceService.cancel()` → `runtime.cancel()`.
- `UI/AssistantController.swift`: race each `model.complete` against a ~45 s timeout; on timeout,
  cancel the runtime and surface "That took too long — try again." Tear down the stream/continuation
  cleanly (no leaks).
- **Accept:** a hung or slow turn surfaces a graceful error instead of freezing.

---

## Items 4–7 — direct ports from kodAI_chatbot_dev

### 4. Bundle the GGUF (no download, instant load)
- Copy `kodai_ios/kodAI_chatbot_dev/kodAI_chatbot_dev/LFM2.5-1.2B-Instruct-Q4_K_M.gguf`
  → `kodai-consumer/kodai-consumer/` (Xcode synchronized group auto-bundles it as a resource).
- Add `*.gguf` to the consumer `.gitignore` — **do not commit ~700 MB.**
- `ConsumerModelFileResolver.swift`: keep the bundle as a resolve source (already present).
- **Shared** `KodaiCore/Sources/KodaiRuntime/LocalModelRuntime.swift` `loadContextWithStatus`:
  **skip `ensureDownloaded`** when the model already exists — check the Application-Support path OR
  `Bundle.main` resource first; only download if neither exists. Don't emit `.downloadingModel` when
  skipping. (This also benefits the educational app, which bundles too.)
- **Accept:** launch loads the bundled model with **zero network**; phases go Loading → Thinking
  (no Downloading).

### 5. ThinkingDotsView (port)
- Port `ThinkingDotsView` + `BouncingDot` from `MessageBubble.swift:542` into a new
  `kodai-consumer/kodai-consumer/UI/ThinkingDotsView.swift` (dependency-free: SwiftUI + Color.secondary).
  Drive `isAnimated` from `@Environment(\.accessibilityReduceMotion)`.
- Show it in `AssistantView` during the `.thinking` phase, paired with "Thinking…" (optionally the
  elapsed-seconds counter pattern at `MessageBubble.swift:156`).
- **Accept:** animated bouncing dots while generating.

### 6. InputBar (port, trimmed)
- Port a trimmed `InputBar.swift` → `kodai-consumer/kodai-consumer/UI/ConsumerInputBar.swift`.
- **Keep:** multi-line `TextField(axis: .vertical)` with `lineLimit(1...6)`; send button
  (`arrow.up` in a circle, accent fill when enabled); stop button (`stop.fill`, red) while generating;
  the `.smooth(duration: 0.18)` animations on `canSend` / `isGenerating`.
- **Drop:** `GlassEffectContainer`, `.liquidGlassPanel`, the `AssistantMode` menu, quick chips,
  slash-command picker, mic/speech.
- **Replace styling:** add a small `ConsumerPalette` with the 3 needed colors from `ChatPalette.swift`
  — `accentBlue (0.184, 0.490, 0.965)`, `elevatedSurface (0.094, 0.106, 0.122)`,
  `inputField (0.125, 0.141, 0.161)`. Field background = `RoundedRectangle(cornerRadius: 20).fill(inputField)`.
- **Wire:** `$controller.input`, `controller.isRunning`, `onSend → controller.run()`,
  `onStop → controller.cancel`, `@FocusState` for the keyboard.
- **Accept:** a polished input bar matching chatbot-dev's feel, no educational dependencies.

### 7. Keyboard dismiss (port behavior)
- Mirror `ChatView.swift:378`: `.scrollDismissesKeyboard(.interactively)` on the activity scroll, and
  make that scroll `frame(maxHeight: .infinity)` so the swipe registers.
- Add a tap-to-dismiss backup: an `@FocusState` bound to the field; tapping the scroll/background
  sets it false.
- **Accept:** swipe-down on content and tap-outside both dismiss the keyboard.

---

## Sequencing
1 (stop crash) → 4 (bundle, reliable load) → 2 (native prompt) → 3 (watchdog) → 5, 6, 7 (UI) →
`xcodebuild build` + unit tests → device run.

## Risks
- **#2 is the real unknown.** Without grammar, the 1.2B may still chat instead of tool-calling.
  Mitigation: native trained format + terse prompt + deterministic fallback + confirm/validate
  scaffolding (so "usually-right" is enough). If it underperforms, the only remaining lever is a
  C++/Obj-C++ exception shim to make GBNF safe — **explicitly out of scope here.**
- Shared-runtime edits (remove grammar, skip download) touch the educational app — keep them
  additive/guarded; skip-download is a net positive there.
- Bundling: gitignore the gguf; ~700 MB app size accepted for release.
- Concurrency: the watchdog must actually cancel the runtime stream and not leak the confirm
  continuation.

## Out of scope
Multi-step agentic loop (single-shot stays; `AgentLoop` retained but unused), GBNF / C++ shim, voice
input, Photos / Files / Contacts tools, inline confirm-card editing, download progress UI.

## Verification
- **Headless:** `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk
  iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test` — keep the
  parser/validator/prompt unit tests green (update the prompt test for the native format).
- **Device (user runs):** launch → bundled load, no download → "remind me to text mom at 6" →
  thinking dots → tool call → confirm card → appears in Reminders → deterministic result line;
  swipe/tap dismisses the keyboard.

## Key file map
- Consumer logic: `kodai-consumer/kodai-consumer/Assistant/{SystemPromptBuilder,ToolCallParser,ToolCallValidator,AssistantTool,DisplayText}.swift`
- Consumer agent: `kodai-consumer/kodai-consumer/Agent/{RuntimeAgentModel,AgentLoop,StateAnchor,ToolResult}.swift`
- Consumer UI: `kodai-consumer/kodai-consumer/UI/{AssistantView,AssistantController}.swift`
- Consumer runtime glue: `kodai-consumer/kodai-consumer/{InferenceService,ConsumerModelFileResolver}.swift`
- Shared package: `KodaiCore/Sources/KodaiRuntime/{LlamaContextWrapper,LocalModelRuntime,ModelDownloader}.swift`, `KodaiCore/Sources/KodaiKernel/Inference/{SamplerKnobs,LocalModelConfiguration}.swift`
- Port sources (chatbot-dev): `kodai_ios/kodAI_chatbot_dev/kodAI_chatbot_dev/{InputBar,MessageBubble,ChatView,ChatPalette}.swift` + the bundled `LFM2.5-1.2B-Instruct-Q4_K_M.gguf`
