# KodAi Project Summary

## Current identity

KodAi is a local-first Apple-native AI assistant/workspace.

The current working app is KodAi macOS: a native SwiftUI chatbot powered by Apple Foundation Models, using SwiftData for persistent chats and a dark glass-inspired interface.

KodAi is evolving from a simple chatbot into a project-based personal AI operating layer with memory, summaries, files, tasks, and context management.

## Current platform focus

### Primary platform

macOS is the main command center.

Focus areas:

- stable local chat
- persistent sessions
- project organization
- memory/context inspection
- file-aware workflows
- developer workflow support

### Secondary platform

iOS will eventually become the companion app.

Focus areas:

- quick capture
- lightweight chat
- project status
- reminders/widgets/shortcuts later

iOS should not be a direct copy of the macOS interface. It should share the same product brain but use a smaller mobile-first interaction model.

## Current stack

- Swift
- SwiftUI
- SwiftData
- Apple Foundation Models
- macOS 26+
- Xcode 26+
- Local-first, no required network calls

## Current macOS features

- On-device AI chat
- Streaming responses
- Persistent chat history
- Collapsible sidebar
- Thread list
- Assistant modes
- Markdown rendering
- Context usage estimate
- Stop generation
- Dark glass-style UI

## Current known docs

Shared top-level docs:

- `docs/vision.md`
- `docs/roadmap.md`
- `docs/architecture.md`
- `docs/decisions.md`

macOS-specific docs:

- `kodai_macos/README.md`
- `kodai_macos/CLAUDE.md`
- `kodai_macos/kodai_macos/docs/architecture.md`

## Product direction

KodAi should become:

- a private thinking workspace
- a project manager
- a memory system
- a context engine
- a file-aware assistant
- a local-first Apple Intelligence experiment
- eventually, a personal AI operating system

## Important principles

- Do not turn KodAi into a generic chatbot clone.
- Do not duplicate shared docs separately for macOS and iOS.
- Do not let UI polish outrun architecture.
- Do not blindly store everything as memory.
- Memory should be compressed into summaries, decisions, tasks, and reusable notes.
- Projects should become the main unit of organization.
- The assistant should expose what context it used.

## Near-term priority

The near-term priority is to prepare a clean architecture/context package for a high-quality model session.

Before using Fable, KodAi should have:

- clean shared docs
- memory files
- current project summary
- active task list
- file map
- final Fable prompt

## Current build strategy

1. Stabilize KodAi macOS.
2. Add project structure.
3. Add summaries.
4. Add context assembly.
5. Add file summaries.
6. Then build iOS companion.
7. Only later add tools/agents.
