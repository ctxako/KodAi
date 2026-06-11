# KodAi Progress Log

Date: 2026-06-11

## P0 to P11end — ELI5 Build History

Here's an ELI5 of every commit from P0 to P11end:

### P0 baseline

The starting point, like a blank canvas before anything new was built.

### 1. Wire ChatViewModel / remove duplicate code

The chat screen and the AI brain were talking to each other in two different ways at once. This cleaned that up so they only talk one way. Less confusion, fewer bugs.

### 2. Single source of truth / fix double history

The app was accidentally sending the conversation history to the AI twice — like reading the same diary to someone twice before asking a question. This made one authoritative place that holds the history, and only sends it once.

### 3. KodaiCore package — canonical models

You built a shared "library" called KodaiCore. Think of it like a LEGO parts box. It defines all the important building blocks — what a chat message looks like, what a task is, what a project is, what a memory entry is — so every part of the app agrees on the same definitions.

### 4. Inference abstraction layer — FoundationModels backend

Instead of the app talking directly to Apple's AI, you added a middleman translator. Now the app says "please answer this" to a generic interface, and that talks to Apple's on-device model. Makes it easy to swap the AI engine later without rewriting everything.

### 5. Ledger manifest + glass-box spine

Every time the AI answers, the app now writes a little receipt — what context was sent, how many tokens, what the answer was. Like a flight recorder for each AI conversation turn. "Glass-box" means you can see inside what happened, not just the output.

### 6. Context engine

The app now smartly assembles what to tell the AI before each message. Instead of dumping everything, it picks: current time, who you are/persona, active tasks, project summaries, and recent history — all within a token budget. Like packing a lunchbox with only the right stuff instead of the whole fridge.

### 7. Per-turn pipeline + "Why this answer" panel

Two things happened here:

1. The context assembly and ledger now fire together on every single message — the pipeline.
2. A UI panel was added that lets you tap a chat bubble and see why the AI said what it said — which context blocks were used, how many tokens, and related turn details.

Like showing your work on a math test.

### 8. Project CRUD

You can now create, rename, and delete Projects in the sidebar. Projects are like folders that group conversations together. The sidebar got a big overhaul to show project headers and let you manage them.

### 9. Summary model + ContextAssembler wired up

A new SummaryEngine was added. It can generate a short summary of a chat session and save it. The ContextAssembler from the context engine phase is now actually wired into the live app so project summaries flow into what the AI sees before each reply.

### 10. P11end — Tasks CRUD

You can now create, complete, and delete Tasks inside a project. The project header panel got a full task list UI — add a task, check it off, delete it. Tasks are persisted in SwiftData so they survive restarts.

## TL;DR Arc

KodAi went from a basic chat app to a cleaner architecture with a shared core, model abstraction, smart context assembly, glass-box observability, projects, summaries, and persisted tasks.

The app is no longer just a chat interface. It is becoming a local-first project assistant with memory, context, and inspectable AI behavior.
