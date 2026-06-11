# KodAi Roadmap

## Roadmap philosophy

KodAi should be built in layers.

Do not jump straight to agents, tools, web access, or complicated memory until the base app is stable.

The correct order is:

1. stable chat
2. persistent sessions
3. projects
4. summaries
5. file context
6. memory engine
7. tools
8. agent workflows

## Phase 0 — Documentation and source of truth

Goal: create a clean top-level product brain before expanding the app.

Tasks:

- Create top-level `docs/`
- Add `vision.md`
- Add `roadmap.md`
- Add `architecture.md`
- Add `decisions.md`
- Keep macOS implementation docs separate
- Keep iOS implementation docs separate later
- Commit docs to GitHub

Success criteria:

- There is one shared KodAi product direction.
- macOS and iOS can both refer back to the same vision.
- Future model sessions have clear context.

## Phase 1 — Stabilize KodAi macOS

Goal: make the existing macOS app clean, reliable, and easy to extend.

Current foundation:

- SwiftUI app
- Apple Foundation Models
- on-device responses
- SwiftData chat persistence
- sidebar
- persistent chat history
- markdown rendering
- assistant modes
- context estimate

Tasks:

- Clean current file structure
- Keep all app Swift files in the canonical source folder
- Improve README
- Keep `CLAUDE.md` accurate for coding agents
- Ensure chat persistence is stable
- Ensure new chat, rename, delete, and switch flows work cleanly
- Keep the app fully local
- Improve visual polish without changing architecture every session

Success criteria:

- App builds cleanly.
- Basic chat feels stable.
- Chat history survives app relaunch.
- The codebase is understandable to a coding agent.

## Phase 2 — Project layer

Goal: move KodAi from loose chat sessions to project-based work.

Tasks:

- Add `KodaiProject` model
- Let each chat optionally belong to a project
- Add project list in sidebar
- Add project detail view
- Add project title, description, created date, updated date
- Add active/inactive/archive status
- Add per-project summary field
- Add per-project task list placeholder
- Add per-project file references placeholder

Success criteria:

- User can create a project.
- User can create chats inside a project.
- User can switch between project and global chats.
- Each project has a durable summary area.

## Phase 3 — Summaries and memory compression

Goal: preserve important information without overloading the context window.

Tasks:

- Add chat summary generation
- Add project summary generation
- Add manual "summarize this chat" action
- Add automatic summary after a chat becomes long
- Store summaries separately from raw messages
- Create `active_tasks.md` style project summary inside the app data model
- Add "memory preview" or "context preview" UI

Success criteria:

- KodAi can summarize a chat into useful project memory.
- Project summaries become more useful than raw chat history.
- The user can see what memory exists before using it.

## Phase 4 — Context engine

Goal: assemble the right context before each model request.

Tasks:

- Define context budget
- Separate always-injected context from optional context
- Inject selected mode prompt
- Inject recent messages
- Inject project summary
- Inject active tasks
- Inject relevant file summaries later
- Add context usage display
- Add context source inspection

Success criteria:

- Every response can show what context was used.
- Project-aware responses feel better than generic chat.
- Context does not blindly include everything.

## Phase 5 — File context

Goal: let KodAi understand files without freezing the app.

Tasks:

- Add file import or drag/drop
- Store file metadata
- Generate file summaries
- Store file summaries separately from full content
- Allow file selection per chat
- Add project file map
- Avoid injecting full files unless explicitly needed

Success criteria:

- User can attach files to a project.
- KodAi can use file summaries as context.
- The app stays fast.

## Phase 6 — iOS companion

Goal: build KodAi iOS after the shared brain is clearer.

Tasks:

- Create separate iOS repo/project
- Reuse product docs, not macOS implementation docs
- Design compact project list
- Add quick capture
- Add recent project status
- Add lightweight chat
- Consider widgets later
- Consider Shortcuts later

Success criteria:

- iOS does not become a cramped clone of macOS.
- iOS supports fast capture and review.
- macOS remains the main command center.

## Phase 7 — Tools and agent workflows

Goal: allow KodAi to take structured actions safely.

Possible tools:

- create task
- summarize project
- rename chat
- organize project
- search project memory
- inspect file summary
- generate checklist
- export markdown
- open local file references
- future web search
- future calendar/reminder integration

Success criteria:

- Tools are visible and inspectable.
- User stays in control.
- KodAi can help complete workflows, not just talk about them.

## Phase 8 — Long-term operating system

Goal: make KodAi a private AI operating layer.

Possible future capabilities:

- project health dashboard
- autonomous daily summary
- stale task detection
- weekly project review
- memory cleanup
- confidence tracking
- model performance telemetry
- local/cloud model routing
- source-aware answers
- multi-device sync

Success criteria:

- KodAi helps continue work across days and weeks.
- It reduces re-explaining.
- It becomes a serious personal system, not just a cool UI.
