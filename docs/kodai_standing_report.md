# KodAi — Current Standing Report

> A living survey of what KodAi has become, with a focus on the **iOS** build,
> where the on-device `llama.cpp` engine and the inspection ("glass-box")
> surfaces have seen the most recent work.
>
> Each feature is described as **what it is**, **its elements**, and then read
> through three lenses — **Artistic**, **Educational**, and **AI/ML
> Engineering** — because KodAi is simultaneously a private workspace, a
> teaching instrument, and a real local inference stack.
>
> This document is **append-only by intent**. New features get new sections;
> existing sections get revised in place. See the changelog at the bottom.

---

## Report metadata

| Field | Value |
|---|---|
| Report date | 2026-06-19 |
| Scope | KodAi iOS (`kodai_ios/kodAI_chatbot_dev`) |
| Inference backend | `llama.cpp` (vendored `llama.xcframework`, build b5200), C++ via Swift bridge |
| Bundled model | `LFM2.5-1.2B-Instruct-Q4_K_M.gguf` (Liquid Foundation Model 2.5, 1.2B params, 4-bit K-quant) |
| Lightweight build variant | `SmolLM2-135M-Instruct-Q8_0.gguf` (device-debug builds) |
| Context window | 2,048 tokens |
| Default sampler | temp 0.45 · top-K 40 · top-P 0.92 · repeat-penalty 1.05 |
| Sister platform | macOS build runs on Apple Foundation Models (shared product brain, different engine) |

> Note: `AGENTS.md` still lists the iOS model family as Qwen2.5; the code bundles
> **LFM2.5** today. This report reflects the code.

---

## The shape of the app

KodAi iOS is a **local-first AI workspace in a glass box**. Everything the model
does runs on the phone — no API keys, no network round-trips for inference — and
almost every internal decision is made *inspectable*. The product splits into
two halves that share one spine:

1. **The workspace** — chat, projects, tasks, memory, context assembly. The
   useful, day-to-day assistant.
2. **The observatory** — a family of visualizations that turn one generation
   into something you can fly through, scrub, and learn from.

The observatory is what makes KodAi unusual, and it is where the recent
iOS work concentrated.

---

## 1. The local inference engine

**What it is.** The on-device brain. KodAi runs a quantized GGUF model directly
through `llama.cpp`, with a Swift actor layer wrapping the C++ context so the
rest of the app can ask for a reply without touching raw pointers.

**Its elements.**
- `LocalModelRuntime` — owns model configuration (file name, context size,
  default sampler knobs) and lifecycle.
- `LlamaRuntime` / `LlamaContextWrapper` — validate the GGUF header, load the
  model, build the sampler chain, tokenize, prefill the KV cache, and decode
  token-by-token.
- `InferenceService` — the actor the UI talks to; it assembles the prompt stack,
  folds in ambient + constraint context, and streams events back.
- `BundledModelFileResolver` / `ModelDownloader` — locate the `.gguf` in the app
  bundle (or fetch one).
- **Sampler chain** (llama.cpp order): repetition/frequency/presence penalties →
  top-K → min-P → top-P → temperature → stochastic pick. A `deterministic` flag
  short-circuits to greedy (argmax) so the same prompt yields the same output.

**Artistic lens.** The engine is the unseen tide under everything else. It never
shows itself directly — it is felt through the warmth or coolness of a token's
color, the width of a river, the glow of a bead. The decision to keep it
*entirely on device* is itself an aesthetic stance: KodAi is a closed, private
instrument, a "glass box" you carry, not a window onto someone else's server.

**Educational lens.** This is a complete, honest LLM pipeline in miniature:
tokenize → prefill → autoregressive decode → sample → detokenize. Because it is
small (1.2B, 4-bit) and local, a learner can watch each stage fire (the app emits
`phase` events: *formatting prompt, tokenizing, prefilling, decoding*) and build
an accurate mental model of how a transformer actually produces text, one token
at a time, conditioned on everything before it.

**AI/ML engineering lens.** A real quantized deployment: Q4_K_M weights, a
2,048-token context, an explicit sampler chain with documented stage ordering,
KV-cache prefill in batches, EOG/stop-string handling, and cancellation. The
sampler is reconstructed from live `SamplerKnobs` each generation, so penalty →
truncation → temperature ordering is faithful to llama.cpp convention rather than
hand-waved. Determinism is a first-class switch (greedy after penalties).

---

## 2. Glass-box telemetry capture

**What it is.** The layer that makes inspection possible. At every decode step,
KodAi reads the model's raw logits *before* the stochastic pick and records what
the model was actually weighing — not just what it emitted.

**Its elements.**
- `readTopAlternatives` — softmaxes the full vocabulary logits, keeps the **top-5
  candidates** plus the chosen token's probability.
- `TokenDecision` → `TokenSnapshot` — per-token record: chosen text, chosen
  probability, the top alternatives, and derived measures.
- Derived measures: **entropy** (spread of the distribution, in nats),
  **margin** (gap between the top two candidates), **surprise** (−log p of the
  chosen token), and **raw-argmax divergence** (did sampling emit something other
  than the model's single most-likely token?).
- `TokenTraceStore` — persists the most recent response traces across relaunch so
  the observatory still works after you reopen the app.

**Artistic lens.** This is the pigment. Every visual in the app is painted from
these four or five numbers — color *is* probability, size *is* entropy, gold *is*
divergence. The restraint matters: only measured quantities become marks on the
screen; decorative motion is kept separate from data-bearing motion.

**Educational lens.** It operationalizes the slogan **"probability is not
correctness."** A confident token can be wrong; an uncertain one can be right.
By surfacing entropy, margin, and surprise as distinct readings — each with a
plain-language gloss ("~4 nats ≈ a uniform choice over ~55 tokens") — KodAi
teaches the difference between *the model was sure* and *the model was right*.

**AI/ML engineering lens.** This is interpretability telemetry done correctly:
probabilities captured **pre-sampling** (before temperature/truncation distort
them), with the raw argmax tracked separately from the emitted token so you can
see exactly where the sampler overrode greedy decoding. Entropy/margin/surprise
are the standard uncertainty diagnostics, computed per token, persisted, and
reused identically across every view — one source of truth for "confidence."

---

## 3. The Globe View — Atlas and Globe

This is the feature the user called out, and it is really **two zoom levels of
one idea**: the **Thread Atlas** (the whole conversation) and the **Token Globe**
(a single response). They share geometry, palette, and telemetry, so moving
between them feels like zooming a camera, not switching apps.

### 3a. Token Globe — the "Decision Globe" (`GlobeView`)

**What it is.** One assistant response wrapped onto a transparent glass sphere.
Every analyzed token becomes a bead on a pole-to-pole spiral; the path the model
actually took is the ribbon threading them.

**Its elements.**
- **Beads** — one per token, placed on a spiral from north pole (step 0) to
  south. Color = chosen-token probability; size = entropy (uncertainty).
- **The tracer** — a strand threading the emitted path in generation order,
  tinted by each token's probability so the trajectory itself carries heat.
- **Gold satellites** — a small gold diamond on any token where sampling chose
  something *other* than the raw most-likely token.
- **Vessels** — when you focus a token, faint filaments bloom from it to each
  top alternative the model weighed but did not emit; the raw argmax glows gold
  when it differs from what was chosen.
- **The playhead** — a fixed crosshair at screen center. You don't move the
  camera; you *spin the globe* so the active token rotates to front-center.
- **The scrubber / timeline** — replay generation in order; completed decisions
  stay as a quiet trail, the newest segment glows, the future recedes.
- **The focused card** — plain-language takeaway + raw metrics (chosen p,
  entropy, top-two gap, surprise, full candidate list).

**Artistic lens.** A "decision trace through probability space — not thoughts."
The globe is deliberately astronomical: a dark observatory, a glass orb, beads
like stars, gold like a rare astronomical event. Only the token you are looking
at blooms into vessels — everything else stays a clean dot — so the sphere never
becomes confetti. It rewards exploration without overwhelming.

**Educational lens.** It makes *sampling* visible. The gold satellite is the
teachable moment: "here the model's favorite was X, but the dice landed on Y."
Scrubbing turns generation back into a *process* with time, not a finished
paragraph. The reading guide and the "before-sampling telemetry · probability is
not correctness" banner keep the interpretation honest.

**AI/ML engineering lens.** This is a faithful per-step decode visualization: the
spiral is generation order, the tracer is the emitted sequence, the vessels are
the top-K distribution at each step, and the gold marks raw-argmax/emitted
divergence. It is rendered in SceneKit with depth cues (back-hemisphere beads
fade through the glass), accessible hit-targets, and reduce-motion respect —
production-grade, not a toy plot.

### 3b. Thread Atlas (`ThreadGlobeView`)

**What it is.** The *whole conversation* wrapped onto one glass globe. Each
traced user→assistant exchange becomes a **continent**.

**Its elements.**
- **Continents** — one spherical-cap region per exchange. **Area** ≈ that
  exchange's share of context capacity (stable: new continents are added, old
  ones never resize). **Tint** = mean token probability for that exchange.
- **Latitude = chronology** — earliest exchange near the north pole, latest near
  the south, along a pole-to-pole spiral.
- **The vine** — a toggleable strand threading continents in conversation order.
- **Gold beacon** — a continent containing any non-top (sampled-over-argmax)
  choice gets a single gold marker, rather than turning the whole region yellow.
- **Focus + drill-through** — focusing a continent scatters *its* tokens as a
  local spiral; tapping a token blooms the same vessels as the Globe; "Open token
  replay" drills all the way into the per-response `GlobeView`.

**Artistic lens.** A conversation rendered as a small planet you can turn in your
hand. The metaphor of *continents* gives a thread geography — big landmasses are
the heavy exchanges, the vine is the river of conversation connecting them. The
far side stays faint through the glass, so the orb always reads as one object.

**Educational lens.** It teaches **context as a finite, spatial resource**.
Watching continents accumulate and fill the globe is a visceral lesson in why
context windows fill up and why long chats cost more. It also shows, at a glance,
which parts of a conversation the model was confident or shaky on.

**AI/ML engineering lens.** Continent area is a real estimate of context
footprint (prompt tokens estimated + response tokens counted exactly, divided by
the 2,048-token capacity, area-accurate via spherical-cap math). It is an
overview→detail (atlas→trace) information architecture over the same telemetry,
with pinch-zoom LOD and the per-response globe as the deepest tier.

---

## 4. Follow the River (`RiverView`)

**What it is.** The same single-response trace, told as a **flowing current**
instead of a sphere — a scroll-driven, full-screen channel of water.

**Its elements.**
- **The spine** — the chosen path, running down the center of the channel.
- **Channel width** — driven by entropy: turbulent (uncertain) stretches widen.
- **Tributaries** — rejected candidates fan off the side.
- **Forks** — where sampling didn't follow the model's strongest current, the
  channel bends and leaves a ghost branch behind; successive forks alternate
  sides so a noisy passage reads as *meander*, not a runaway diagonal.
- **The playhead** — fixed at screen center; scrolling "follows" the river one
  decision at a time.

**Artistic lens.** The signature expression of KodAi's "nocturnal field guide"
visual language (midnight water, luminous currents). Generation becomes a
*journey downstream*: wider water = more possibility, brighter = stronger
probability, a fork = the moment of choice. It is the most poetic of the views.

**Educational lens.** Width-as-uncertainty and fork-as-sampling are two of the
hardest ideas to convey, and the river makes them physical: you can *feel* a
turbulent passage and *see* the moment the current split. Color is never the only
signal — brightness and line width also carry confidence (color-blind-friendly).

**AI/ML engineering lens.** Same `TokenSnapshot` data as the globe and inspector,
re-encoded: `entropy → channel`, `greedy-vs-selected gap → fork strength`,
`probability → confidence color`. Three views, one telemetry contract — proof the
instrumentation is decoupled from presentation.

---

## 5. Token Inspector & live heatmap (`TokenInspectorView`, `MessageBubble`)

**What it is.** The flat, analytical reading of a response — the heatmap and the
candidate tables — plus the *live* coloring of tokens as they stream in.

**Its elements.**
- **`TokenVisuals`** — the shared rendering contract: the observatory color scale
  (dim indigo → blue → luminous cyan as probability rises), the reserved
  divergence gold, the rose channel for alternatives, and the whitespace/newline
  glyphs (`␣`, `⏎`, `⇥`).
- **Live trajectory** — tokens are tinted by confidence *as they generate* in the
  chat bubble, so the heatmap exists before you ever open a dedicated view.
- **Inspector** — per-token candidate lists, entropy/margin/surprise, and the
  alternatives the model weighed.

**Artistic lens.** The "weather-radar" palette (recently retheme'd) gives the raw
data a calm, legible identity that still feels like part of the night-observatory
world. Gold is rationed — it is the only warm color, reserved for the exceptional.

**Educational lens.** This is the entry-level reading: see, inline, where the
model was confident and where it hesitated, without leaving the conversation. It
is the bridge from "chatbot" to "I can see the model thinking in probabilities."

**AI/ML engineering lens.** The canonical encoding layer. Every other view
imports `TokenVisuals` so "what does this color mean" has exactly one answer
across the whole app. Entropy and surprise reference maxima (~4 nats) are defined
here, once, and normalized consistently.

---

## 6. Sampler Playground (`ModelTuningCard` / `SamplerPlaygroundView`)

**What it is.** Live controls for the sampler. Every knob edits the real
`SamplerKnobs` bound to the chat — there is no mock; changes steer the *next*
actual generation.

**Its elements.**
- **Core knobs** — Temperature, Top-K, Top-P (with a deterministic/greedy mode).
- **Advanced** — Min-P, repetition / frequency / presence penalties, max output
  tokens, seed.
- **Per-knob ⓘ helpers** — a plain-language card explaining each control.

**Artistic lens.** The tuning lives behind the "kodAI" title pill as a liquid-
glass card — controls feel like part of the instrument, not a settings dump.

**Educational lens.** Cause and effect you can feel: raise temperature and watch
more gold satellites appear in the globe; drop to deterministic and watch them
vanish. The playground + observatory together form a closed feedback loop for
*understanding* sampling, not just using it.

**AI/ML engineering lens.** Direct, faithful exposure of llama.cpp sampler
parameters with correct semantics and a documented chain order. The deterministic
switch is genuinely greedy-after-penalties; seed is settable for reproducibility.

---

## 7. Context Engine & Ambient Context

**What it is.** The layer that decides *what the model sees* before it generates —
KodAi's answer to "memory through compression, not hoarding."

**Its elements.**
- **`ModelPromptStack`** — the assembled prompt: app/mode identity, local project
  context, runtime constraints, and ambient context.
- **`AmbientContextProvider` / `AmbientContext`** — real-world grounding: local
  date/time, time-of-day bucket, weekday, timezone, and (when available) a
  weather summary, surfaced as a prompt block with cache/fresh/failed status.
- **`ConstraintSnapshot`** — runtime constraints (e.g. context pressure %) turned
  into an explicit prompt block, with diagnostics streamed to the UI.
- **Context pressure** — how full the 2,048-token window is, fed back into both
  the prompt and the Atlas's footprint visualization.

**Artistic lens.** Context is treated as *atmosphere* — the model wakes up
knowing it's a Friday evening, the weather, where it left off — which is why the
Atlas can render a conversation as a place with weather and geography.

**Educational lens.** It demystifies "the system prompt": you can see the
distinct blocks (identity, project, constraints, ambient) rather than one opaque
preamble, reinforcing the architecture's recommended context order.

**AI/ML engineering lens.** A real context-budget strategy: tiered inclusion
(always / when-project-exists / when-relevant / never-blindly), a token estimator
for the budget, ambient grounding with graceful degradation (cached vs. fresh vs.
failed weather), and diagnostics emitted as first-class stream events.

---

## 8. Tool proposals

**What it is.** The beginning of the agentic layer — the model can *propose* an
action (e.g. "create this task") and the user confirms it, rather than the app
silently acting.

**Its elements.**
- `KodaiPendingToolProposalValue` / `KodaiCreateTaskProposalValue` — the proposal
  value models (now living in the shared `KodaiKernel`).
- `ToolProposalCard` — the iOS confirmation UI; execution stays iOS-owned.

**Artistic lens.** Action is presented as a *card you approve*, keeping the calm,
deliberate, inspectable feeling — the assistant suggests, the human decides.

**Educational lens.** A clean illustration of human-in-the-loop tool use: the
model's intent is made explicit and reviewable before anything happens.

**AI/ML engineering lens.** Tool calls modeled as typed, inspectable proposals
with a confirmation gate — the safe, explicit foundation the architecture doc
calls for before broader agent workflows.

---

## 9. The visual language (cross-cutting)

**What it is.** The "nocturnal field guide" aesthetic that unifies every surface:
midnight backgrounds, luminous currents, restrained **liquid glass**, and warm
uncertainty accents.

**Its elements.**
- `LiquidGlassBackground`, `liquidGlassPanel`, `GlassEffectContainer` — the
  iOS 26 glass material system.
- `ChatPalette` / `TokenVisuals` — the shared accent and data-encoding colors.
- `GlobeChrome` / `GlobeObservatoryBackdrop` — the observatory shell, wireframe
  globe, and silhouette ring reused by both globe views.
- Accessibility throughout — reduce-motion, reduce-transparency, Dynamic Type,
  generous hit-targets, and "color is never the only signal."

**Artistic lens.** The thesis view of the whole project: *inspection as
expedition*. Scientific fieldwork at night — calm, spatial, tactile, rewarding to
explore — instead of a diagnostics dashboard.

**Educational lens.** Consistency *is* pedagogy: because cyan always means
"probable" and gold always means "the sampler overrode the favorite," the user
learns one visual grammar and can read every view with it.

**AI/ML engineering lens.** A disciplined design system separating *measured data
encodings* from *decorative motion*, with one palette source and one telemetry
contract — the reason three radically different visualizations can stay perfectly
consistent.

---

## Where this stands

KodAi iOS today is a genuinely **local** LLM (llama.cpp + LFM2.5-1.2B-Q4_K_M)
wrapped in an unusually deep **glass box**: pre-sampling telemetry captured at
every decode step and re-rendered as a per-response **Globe**, a whole-thread
**Atlas**, a **River**, and a flat **heatmap/inspector** — all painted from one
consistent set of measures, all steerable live from the **Sampler Playground**,
all grounded by a tiered **Context Engine** with ambient awareness. The agentic
layer (tool proposals) and the workspace layer (projects, tasks, memory) exist
and are migrating onto the shared `KodaiKernel`/SwiftData spine.

It is, by design, three things at once: a private workspace (artistic), a
teaching instrument (educational), and a faithful local inference deployment
(AI/ML engineering).

---

## Future appending

Planned/expected additions to track in later revisions of this report:
- CloudKit sync once chat/workspace configs are split (per the K2 migration plan).
- Per-token vessels and pinch-zoom LOD tiers inside Atlas continents (Phase 2).
- Expanded tool layer (file search, web, calendar/reminders) per the roadmap.
- Model router (LFM2.5 / smaller SmolLM2 / future cloud) selection logic.

## Changelog

- **2026-06-19** — Initial standing report. Covers iOS inference engine,
  telemetry capture, Token Globe + Thread Atlas, River, Inspector/heatmap,
  Sampler Playground, Context/Ambient engine, tool proposals, and visual
  language across artistic / educational / AI-ML lenses.
