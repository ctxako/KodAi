# KodAi Decisions

This file records product and architecture decisions that should not be re-litigated every session.

Use this as the durable decision log.

## Decision 001 — Keep macOS and iOS codebases separate

Status: accepted

KodAi macOS and KodAi iOS should remain separate app projects.

Reason:

- macOS and iOS have different interface needs.
- macOS should be the command center.
- iOS should be the compact companion.
- Forcing one shared Xcode project too early will create friction.

Implication:

- Share product docs and concepts.
- Do not blindly copy macOS UI into iOS or vice versa.
- Reuse ideas, not entire layouts.

## Decision 002 — Create one shared top-level docs folder

Status: accepted

The top-level `docs/` folder is the source of truth for shared KodAi product direction.

Files:

- `vision.md`
- `roadmap.md`
- `architecture.md`
- `decisions.md`

Reason:

- Prevent duplicated docs between platforms.
- Give future model sessions a clean context pack.
- Keep the product brain separate from implementation details.

Implication:

- macOS docs explain macOS implementation.
- iOS docs explain iOS implementation.
- Top-level docs explain what KodAi is.

## Decision 003 — Keep KodAi local-first across platforms

Status: accepted

KodAi should prefer local/on-device AI and local persistence by default.

Local-first does not mean every platform must use the same model backend. It means the assistant should run privately on the user's device whenever possible.

Current platform direction:

* macOS uses Apple Foundation Models as the primary local model layer.
* iOS uses a local GGUF model path for now, currently focused around Liquid AI due to iPhone 14 hardware constraints.
* Future versions may support a model router that chooses between Apple Foundation Models, GGUF/local LLMs, or optional cloud models based on task needs, privacy level, and device capability.

Reason:

* Privacy is part of the product identity.
* The app should work without API keys for core features.
* macOS and iOS have different hardware and model-runtime realities.
* Apple Foundation Models are central to the macOS direction.
* GGUF/local models allow iOS experimentation even when Foundation Models are not the best available path for the device.

Implication:

* No required network calls in the base app.
* No cloud dependency for basic chat.
* Model providers should be abstracted behind a clean interface.
* Platform-specific model choices are allowed.
* Future cloud models must be optional, explicit, and clearly routed.
* The product identity remains local-first even if macOS and iOS use different local model engines.


## Decision 004 — Build projects before advanced agents

Status: accepted

KodAi should add projects before attempting advanced agent behavior.

Reason:

- Agents need structure.
- Memory needs a place to live.
- Tools need a target.
- A project gives context, tasks, summaries, and files a home.

Implication:

- Project model comes before complex automation.
- Chat sessions should eventually belong to projects.
- Project summary becomes a core context source.

## Decision 005 — Memory should be compressed, not dumped

Status: accepted

KodAi should not treat raw chat history as the main memory system.

Reason:

- Raw chat is too large. Too diluted.
- Context windows are limited.
- Useful memory is usually a summary, decision, task, or reusable note. Concentrated.

Implication:

- Add chat summaries.
- Add project summaries.
- Add decisions.
- Add active tasks.
- Avoid injecting entire old conversations.

## Decision 006 — The assistant should expose its context

Status: accepted

KodAi should make context visible to the user.

Reason:

- The user is learning AI engineering.
- Debugging context is part of the product.
- Trust improves when the assistant shows what it used.

Implication:

- Add a context inspector later.
- Show project memory used.
- Show file summaries used.
- Show estimated context usage.
- Show tool calls when tools exist.

## Decision 007 — UI polish should not outrun architecture

Status: accepted

Visual polish matters, but architecture comes first.

Reason:

- A beautiful app with weak state, memory, and project structure will collapse.
- UI can be iterated quickly.
- Bad data architecture is expensive to fix later.

Implication:

- Stabilize chat and persistence first.
- Add project and memory layers before chasing every visual idea.
- Keep design system reusable.

## Decision 008 — macOS is the main build target first

Status: accepted

KodAi macOS should mature before KodAi iOS becomes serious.

Reason:

- macOS supports larger workspaces.
- File/project workflows are easier on desktop.
- Developer workflows fit macOS better.
- The current app already exists on macOS.

Implication:

- iOS planning can happen now.
- iOS build should wait until the shared architecture is clearer.
- macOS remains the command center.

## Decision 009 — `CLAUDE.md` is for coding agents, not product vision

Status: accepted

`CLAUDE.md` should stay implementation-focused.

Reason:

- Coding agents need build requirements, file structure, conventions, and warnings.
- Product vision belongs in top-level docs.
- Mixing them makes both worse.

Implication:

- Keep `CLAUDE.md` short and practical.
- Link to docs if needed.
- Do not turn `CLAUDE.md` into the whole product manifesto.

## Decision 010 — Fable should be used for architecture, not minor UI

Status: accepted

A limited high-quality model session should be spent on KodAi's brain and product architecture.

Reason:

- UI can be iterated later with screenshots and small prompts.
- The memory/context/project architecture will shape the whole product.
- A strong architecture document can guide months of work.

Implication:

- Prepare docs before using Fable.
- Feed Fable the top-level docs.
- Ask for critique, redesign, and implementation sequencing.
