# Codex Rules for This Project

## Core working style

* Be direct, practical, and token-efficient.
* Make the smallest safe change that solves the requested problem.
* Prefer minimal structural changes.
* Do not refactor, reorganize, rename, or move code unless it is necessary for the requested fix.
* If a structural change seems necessary, explain why before doing it.
* Preserve the existing architecture and file boundaries unless explicitly told otherwise.
* Do not add features, abstractions, managers, services, or helper layers unless the task clearly requires them.

## Decision-making

* If there is one clean obvious fix, apply it directly.
* If there are meaningful tradeoffs, briefly present the options and recommend one.
* Do not debate obvious choices.
* Do not over-engineer small UI or bug-fix tasks.
* Prefer SwiftUI-native solutions over UIKit bridges or gesture hacks unless native SwiftUI cannot solve the issue.
* Prefer proven, boring, maintainable code over clever code.

## Token and runtime efficiency

* Be token-efficient. Do not narrate obvious steps.
* Do not summarize the whole repo.
* Read the smallest relevant files first.
* Use targeted search before broad search.
* Do not scan unrelated directories unless the targeted search fails.
* If something is easier for the user to do manually, say so instead of spending tokens or tool calls doing it.
* Do not run commands just to gather information the user can provide faster.
* Do not start multiple agents, subagents, terminals, simulators, or devices unless explicitly requested.
* Do not run parallel simulator sessions.
* Use one simulator only: iPhone 14, latest available iOS runtime.

## iOS build/test policy

* For normal code changes, do not launch the simulator unless visual or interaction verification is specifically needed.
* Prefer a targeted build over simulator testing.
* Use one `xcodebuild` command at a time.
* Prefer:

```bash
xcodebuild -project <PROJECT>.xcodeproj -scheme <SCHEME> -destination 'platform=iOS Simulator,name=iPhone 14' build
```

* If a simulator is already running, reuse it.
* If multiple simulators are running, shut down extras before testing.
* Never run more than one `xcodebuild`, simulator boot, UI test, or device session at the same time.
* Do not run UI tests unless the task specifically requires UI behavior verification or the build passes but the issue cannot be validated statically.

## Scope control

* Only change files directly related to the requested task.
* Do not add RAG, memory, embeddings, persistence, chat history, markdown, animations, model picker, onboarding, settings, or unrelated UI polish unless explicitly requested.
* Do not change app architecture unless required.
* Do not move llama.cpp, inference, persistence, or view model logic across layers without explicit approval.
* Preserve this architecture unless explicitly told otherwise:

```text
ChatViewModel @MainActor
→ InferenceService actor
→ LocalModelRuntime / LlamaRuntime
→ LlamaContextWrapper / llama.cpp
```

## Code hygiene

* Keep patches small and readable.
* Prefer clear names over clever names.
* Avoid duplicate logic.
* Avoid dead code.
* Avoid commented-out code.
* Avoid broad `try?`, silent failures, or swallowed errors unless there is a clear reason.
* Add inline comments only where they explain non-obvious behavior, edge cases, concurrency decisions, or platform quirks.
* Do not add noisy comments that merely restate what the code already says.
* Preserve existing style, formatting, naming, and organization.

## Swift / SwiftUI preferences

* Prefer native SwiftUI APIs when available.
* Keep state ownership clear.
* Parent views should own cross-cutting state when child views only need a binding.
* Avoid UIKit bridges unless required.
* Avoid gesture hacks when a native modifier exists.
* Avoid unnecessary `DispatchQueue.main.async`; prefer structured concurrency and `MainActor`.
* Do not block the main actor with inference, persistence, model loading, embeddings, or expensive synchronous work.
* Keep UI updates batched and lightweight during streaming.

## Concurrency and performance

* Do not introduce main-thread blocking.
* Do not perform SQLite, file I/O, model loading, tokenization, prefill, decode, embeddings, or RAG work on the main actor.
* Avoid high-frequency UI invalidation during streaming.
* Avoid per-token expensive logging, memory checks, animations, or layout work.
* Prefer throttled/batched updates when streaming text.
* Be especially careful with keyboard, scroll, and chat rendering performance.

## Response format

For code-fix tasks, respond in this structure:

### Likely Issue

State the likely issue plainly. Mention uncertainty if the provided context is incomplete.

### Change Made

List the exact files changed.

### Patch

Show the smallest relevant patch or summarize it precisely if the patch is already applied.

### Why This Fix

Explain:

1. What changed.
2. Why it fixes the issue.
3. Why it is the smallest safe fix.
4. What risks remain.

### Verification

State exactly what was run.

If verification was skipped, say why.

## Behavior when blocked

* If the task cannot be completed safely with the available context, ask for the smallest missing piece.
* If a file or command output is needed, request that specific file/output instead of exploring broadly.
* If the user can do a step faster, give the exact step and stop.
* Do not guess large patches from incomplete code.
* Do not invent surrounding code.
