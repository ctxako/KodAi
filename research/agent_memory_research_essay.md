# Agent Memory: How AI Systems Offload, Organize, and Use Memory for Adaptivity and Automation

## Thesis

A language model does not truly “remember” in the human sense. By default, it only works with the text placed inside its current context window. An agent becomes useful over time only when memory is engineered around the model: captured, filtered, compressed, organized, retrieved, updated, and connected to actions. The strongest agent systems treat memory less like a chat history and more like an operating layer: part journal, part database, part filing cabinet, part task manager, and part automation engine.

For a personal assistant like Kodai, the goal should not be to save everything blindly. The goal should be to preserve the smallest useful version of what happened, why it matters, what should happen next, and when that information should be recalled.

---

## 1. Model Memory Versus Agent Memory

A model’s “memory” is mostly an illusion unless the system gives it persistent information. The model can reason over whatever is currently in the prompt, but once the session ends, it needs stored context injected back into the next request. This is why serious agent systems separate the model from the memory layer.

A model is the reasoning engine. An agent is the full loop around it: model, tools, memory, state, permissions, scheduling, retrieval, and action. The model answers. The agent remembers, checks files, searches, schedules, updates tasks, calls tools, and decides what context should be brought back.

This distinction matters because making the model “smarter” is not always the same as making the system better. A small local model with clean memory, structured task files, summaries, and good retrieval can outperform a larger model that is forced to reread messy raw chat logs. For personal software, the memory system is often more important than model size.

---

## 2. Why Models Offload Memory

Models offload memory because context windows are limited, expensive, fragile, and polluted by irrelevant information. When too much raw history is shoved into a prompt, the model may become slower, less focused, and more likely to retrieve the wrong detail. Long context helps, but it is not a complete solution. Memory has to be selected, compressed, and managed.

There are five major reasons to offload memory:

1. **Context windows have limits.** A local on-device model especially cannot carry an unlimited life history, project history, source-code map, user preference file, task list, and live tool output all at once.
2. **Raw history is noisy.** Most conversations contain typos, abandoned ideas, duplicate thoughts, corrections, emotions, and temporary decisions. The model should not treat every sentence as permanent truth.
3. **Memory needs structure.** “User mentioned X once” is not the same as “User has an active project called Kodai macOS, currently building a local-first AI assistant with project memory.”
4. **Agents need action state.** Automation requires knowing not just facts, but pending tasks, deadlines, triggers, permissions, tool access, and what happened last time.
5. **Memory must be inspectable.** A private assistant should let the user see what it stored, why it stored it, and how it is using it. Hidden memory creates trust problems.

---

## 3. The Main Types of Agent Memory

A strong memory system should not be one giant database. It should have several layers.

### Working Memory

Working memory is the live context used for the current response. It includes the user’s latest message, recent turns, selected summaries, relevant files, active task state, and tool results. This should be small, sharp, and temporary.

For Kodai, working memory is what gets injected into the prompt right now.

### Session Memory

Session memory is the current conversation’s transcript and running summary. It helps the assistant understand what has already happened in the thread. This can be saved as raw messages plus a rolling summary.

For Kodai, every chat should have a `chat_summary.md`, `raw_messages.json`, and maybe `important_turns.md`.

### Episodic Memory

Episodic memory stores events: what happened, when it happened, who was involved, and what changed. It is useful for remembering sequences, decisions, and project progress.

Example:

```text
2026-06-10 — User decided Kodai should store project context in local files instead of relying only on chat history.
```

This is different from a general fact. It is an event.

### Semantic Memory

Semantic memory stores stable knowledge: user preferences, project definitions, app architecture, recurring rules, and concepts.

Example:

```text
Kodai is a local-first macOS AI assistant built with SwiftUI and Apple Foundation Models.
```

This should be clean, concise, and relatively stable.

### Procedural Memory

Procedural memory stores how the agent should do things. These are workflows, routines, coding rules, style guides, and preferred processes.

Example:

```text
When the user finishes a coding work session, suggest committing changes with a clear git message.
```

This is important for automation because it tells the assistant how to behave repeatedly.

### Reflective Memory

Reflective memory stores higher-level lessons synthesized from lower-level events.

Example:

```text
The user prefers building features in small files with clear folder structure before adding complex automation.
```

Reflection is where adaptivity starts. The system is no longer just remembering facts; it is compressing patterns.

### Automation Memory

Automation memory stores triggers, conditions, schedules, task states, and permissions.

Example:

```text
Trigger: If user mentions “Kodai project structure,” retrieve project_summary.md, file_map.md, active_tasks.md, and memory_rules.md.
```

Without automation memory, the assistant can remember information but cannot reliably act on it.

---

## 4. The Best Way to Store Agent Memory

The best storage system is hybrid: raw logs for truth, summaries for speed, structured files for control, embeddings for search, and links for reasoning.

A practical architecture should include these layers:

```text
Memory/
  inbox/
    raw_events.jsonl
    raw_chat_logs/
  summaries/
    daily_summary.md
    weekly_summary.md
    chat_summaries/
  semantic/
    user_profile.md
    preferences.md
    stable_facts.md
  projects/
    KodaiMac/
      project_summary.md
      file_map.md
      active_tasks.md
      decisions.md
      triggers.md
      behavior_notes.md
      source_notes/
      summaries/
  procedural/
    coding_rules.md
    git_workflow.md
    design_rules.md
    response_style.md
  automations/
    triggers.yaml
    schedules.yaml
    permissions.yaml
    action_log.jsonl
  reflections/
    daily_reflections.md
    project_reflections.md
    recurring_patterns.md
  retrieval_index/
    vector_index
    keyword_index
    graph_links.json
```

This structure works because each type of memory has a job. Raw logs preserve evidence. Summaries reduce token cost. Project files give the model a stable map. Trigger files decide what to load. Reflection files help the system adapt. Action logs make automation auditable.

The core rule is simple: never make the model search a pile of unorganized memory if a short structured file can answer the question.

---

## 5. Memory Should Be Written Through a Filter

Bad memory systems save too much. Good memory systems decide what deserves to be remembered.

Every new memory should pass through a write filter:

1. Is this stable or temporary?
2. Is this useful in the future?
3. Does it belong to a project?
4. Does it change an existing fact?
5. Is it a task, preference, rule, decision, or event?
6. Does it need a trigger?
7. Should it expire?
8. Should the user approve it?

For Kodai, memory should be stored in small “memory notes,” not giant blobs. A good memory note should include:

```yaml
id:
created_at:
updated_at:
type: semantic | episodic | procedural | task | trigger | reflection
project:
confidence:
source:
summary:
details:
tags:
related:
expires_at:
user_visible: true
```

This makes memory useful for both the model and the app UI.

The important part is `type`. A user preference should not be stored the same way as a task. A project decision should not be stored the same way as a random chat comment. A trigger should not be buried inside a paragraph.

---

## 6. Retrieval Is Not Just Vector Search

Vector search is useful because it finds information by meaning, not just exact words. But vector search alone is not enough.

A good agent should retrieve memory using multiple methods:

- **Keyword search** finds exact things: project names, filenames, commands, errors, people, dates.
- **Vector search** finds related ideas even when the words differ.
- **Metadata filtering** narrows memory by project, type, date, confidence, or status.
- **Graph links** connect related memories, like decisions linked to tasks, files, and summaries.
- **Recency ranking** helps the model prefer newer information when old information may be stale.
- **Manual pinning** keeps critical facts always available.

For Kodai, retrieval should be routed. If the user asks about code, retrieve `file_map.md`, recent coding decisions, active tasks, and relevant source summaries. If the user asks about personal planning, retrieve active goals, reminders, schedule state, and preference notes. If the user asks about a project, load the project’s summary first before searching everything else.

The memory system should not ask, “What memories are similar to this prompt?” only. It should ask, “What kind of situation is this, and what memory package does this situation require?”

---

## 7. Adaptivity Comes From Reflection, Not Just Storage

Saving memory does not automatically make an assistant adaptive. Adaptivity requires consolidation.

A system becomes adaptive when it periodically reviews events and updates higher-level summaries. This is similar to a daily or weekly review. The assistant should ask:

- What changed?
- What did the user decide?
- What mistake repeated?
- What task moved forward?
- What preference became clearer?
- What should be retrieved next time?
- What trigger should be created?

For Kodai, reflection should happen at multiple levels:

- **Chat-level reflection:** summarize what happened in one conversation.
- **Project-level reflection:** update the project’s current direction, active tasks, and decisions.
- **Daily reflection:** summarize the day’s work, unfinished tasks, and notable patterns.
- **Behavior reflection:** notice workflow habits, not personal judgment.
- **Automation reflection:** detect repeated actions that could become shortcuts.

Example:

```text
Observation:
User repeatedly asks whether to commit after finishing a coding session.

Reflection:
Git commit guidance should become a procedural rule.

Automation:
When a coding task is marked complete, suggest git status, git add, git commit, and git push.
```

That is real adaptivity. The system noticed a repeated need, compressed it into a rule, and connected it to a future trigger.

---

## 8. Automation Requires Memory Plus Permission

Memory alone does not make an agent useful. Automation requires memory, tools, and permission boundaries.

A safe automation system should have:

```text
Intent detection:
What does the user seem to want?

State check:
What is already known?

Trigger match:
Does this match a saved trigger?

Tool plan:
What action would be needed?

Permission check:
Is the assistant allowed to do it?

Execution:
Run the tool or prepare the action.

Action log:
Record what happened.

Follow-up:
Update memory and tasks.
```

For a personal local assistant, automation should start conservatively. The assistant can suggest, prepare, and organize before it acts independently. Early automation should be low-risk:

- summarize a finished chat
- update a project task list
- create a reminder draft
- suggest a git commit message
- refresh a file map
- mark a project decision
- detect when context is getting too full
- propose archiving a completed thread

Higher-risk automation should require approval:

- sending messages
- deleting files
- editing source files
- running shell commands
- changing calendar events
- committing code
- purchasing anything
- contacting people

The old-school rule is still the right rule: log everything, ask before destructive actions, and keep the user in control.

---

## 9. The Best Memory Design for Kodai

Kodai should use a local-first memory system built around files, summaries, and visible state. The model should not be trusted to “just remember.” The app should own memory. The model should read and write memory through controlled tools.

The best design is:

```text
1. Raw transcript saved automatically.
2. Short chat summary generated after meaningful turns.
3. Important facts extracted into typed memory notes.
4. Project files updated when the conversation clearly affects a project.
5. Trigger rules created only from repeated or explicit patterns.
6. Active tasks stored separately from passive knowledge.
7. Reflections generated daily or per work session.
8. Retrieval package assembled before each model response.
9. User can inspect, edit, pin, delete, or disable memory.
10. Every tool/action writes to an action log.
```

This gives Kodai three major abilities.

First, **reference ability**: it can find the right context without stuffing entire old chats into the prompt.

Second, **adaptivity**: it can learn project direction, preferred workflows, repeated problems, and better defaults.

Third, **automation**: it can connect remembered state to actions, reminders, tools, and triggers.

The most important design choice is separating memory into “what happened,” “what is true,” “what matters now,” and “what should happen next.” Most weak AI memory systems fail because they blur these categories.

---

## 10. Guardrails

Agent memory needs guardrails because bad memory can make an assistant worse.

The assistant should not permanently store every emotional statement, half-formed idea, or temporary frustration. It should not overwrite stable facts without evidence. It should not create automations from one-off behavior. It should not hide memory from the user. It should not act without permission in high-risk areas.

A practical memory system should support:

- user-visible memory
- memory deletion
- memory editing
- memory confidence levels
- source links back to original chat or file
- expiration dates
- project scoping
- private/offline storage
- action logs
- permission levels
- conflict detection

Conflict detection is especially important. If one memory says “use Foundation Models on macOS” and another says “use GGUF on iOS,” the system should not collapse them into one vague fact. It should preserve the distinction:

```text
macOS: Foundation Models
iOS: GGUF / smaller local model
Reason: device capability and platform constraints
```

Good memory is not just recall. Good memory preserves context.

---

## Conclusion

The future of personal AI agents will not be won by raw model size alone. It will be won by memory architecture. The best agents will know what to save, what to summarize, what to forget, what to retrieve, what to reflect on, and what to turn into action.

For Kodai, the right path is clear: build a local memory operating layer around the model. Store raw truth, summarize aggressively, organize by project, separate facts from tasks, create visible triggers, and keep automation permissioned. The model should not be the memory. The model should be the interpreter of a memory system that the app controls.

The best version of Kodai is not a chatbot with a long chat history. It is a local assistant with a structured working memory, project awareness, visible reasoning state, and a disciplined automation loop.

---

## Source Notes

- [MemGPT: Towards LLMs as Operating Systems](https://arxiv.org/abs/2310.08560) — frames memory as OS-like virtual context management across memory tiers.
- [Generative Agents: Interactive Simulacra of Human Behavior](https://arxiv.org/abs/2304.03442) — supports the observation, reflection, and planning model for adaptive agents.
- [Letta Archival Memory Documentation](https://docs.letta.com/guides/core-concepts/memory/archival-memory/) — describes intentional long-term memory and archival storage.
- [A-MEM: Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110) — supports linked memory notes, tags, context, and evolving relationships.
- [MemoryBank: Enhancing Large Language Models with Long-Term Memory](https://arxiv.org/abs/2305.10250) — explores selective reinforcement, forgetting, and adaptation from user interaction history.
- [RAG vs Long Context and Long-Range Memory Limitations](https://arxiv.org/abs/2402.17753) — supports the warning that long context and RAG alone do not fully solve memory.
- [A Survey on the Memory Mechanism of Large Language Model Based Agents](https://arxiv.org/abs/2603.07670) — describes agent memory as a write, manage, and read loop tied to action.
- [Memori: Structured Memory for LLM Agents](https://arxiv.org/abs/2603.19935) — argues for structured representations such as summaries and semantic triples.
- [Apple Foundation Models Framework WWDC Session](https://developer.apple.com/videos/play/wwdc2025/286/) — relevant to Kodai because of on-device, private, structured, tool-capable model use.
- [Model Context Protocol Introduction](https://modelcontextprotocol.io/docs/getting-started/intro) — useful reference for connecting models to tools, data, and workflows.
