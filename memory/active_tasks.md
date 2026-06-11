# KodAi Active Tasks

## Tonight's objective

Prepare KodAi's shared docs and memory structure so a high-quality model session can design the next-generation architecture around projects, memory, context, and files.

## Priority 1 — Top-level docs

Status: in progress

Tasks:

- [x] Create shared `docs/` folder concept
- [x] Create `docs/vision.md`
- [x] Create `docs/roadmap.md`
- [x] Create `docs/architecture.md`
- [x] Create `docs/decisions.md`
- [ ] Move generated docs into the real KodAi workspace
- [ ] Commit docs to GitHub

Notes:

The shared docs are for product vision and system architecture. They are not replacements for the macOS app README, CLAUDE.md, or current code architecture docs.

## Priority 2 — Memory folder

Status: in progress

Tasks:

- [x] Create `memory/project_summary.md`
- [x] Create `memory/active_tasks.md`
- [x] Create `memory/file_map.md`
- [ ] Move memory files into the real KodAi workspace
- [ ] Keep these files updated before major model sessions

Purpose:

The memory folder gives future model sessions a quick way to understand the current state of KodAi without rereading every chat or source file.

## Priority 3 — Workspace cleanup

Status: pending

Tasks:

- [ ] Decide final local folder layout
- [ ] Keep macOS app code in `kodai_macos/`
- [ ] Create or prepare separate `kodai_ios/` later
- [ ] Keep shared docs at the top level
- [ ] Keep memory files at the top level
- [ ] Avoid duplicating shared docs inside app-specific folders

Recommended structure:

```text
KodAi/
├── docs/
├── memory/
├── research/
├── designs/
├── prompts/
├── experiments/
├── kodai_macos/
└── kodai_ios/
```

## Priority 4 — Fable preparation

Status: pending

Tasks:

- [ ] Gather top-level docs
- [ ] Gather memory files
- [ ] Add any important screenshots if useful
- [ ] Prepare final Fable prompt
- [ ] Ask Fable for architecture critique and redesign
- [ ] Ask Fable for implementation sequence
- [ ] Save Fable output into `research/` or `docs/`

Best Fable use:

Use Fable to design the KodAi brain, not minor UI polish.

The goal is to get a serious architecture for:

- projects
- memory
- context engine
- file summaries
- retrieval
- model routing
- tools
- agent workflows

## Priority 5 — macOS app next steps

Status: pending

Tasks:

- [ ] Review current Swift files
- [ ] Confirm chat persistence works
- [ ] Confirm chat switching works
- [ ] Confirm rename/delete works
- [ ] Improve README if needed
- [ ] Keep CLAUDE.md current
- [ ] Add project model only after current chat system is stable

## Priority 6 — iOS planning

Status: pending

Tasks:

- [ ] Do not copy macOS docs directly into iOS
- [ ] Create iOS-specific README only when iOS project starts
- [ ] Design iOS as a compact companion
- [ ] Reuse shared vision, roadmap, architecture, and decisions
- [ ] Avoid forcing macOS sidebar layout onto iPhone

## Open questions

- What exactly counts as a project?
- Should every chat require a project, or can global chats exist?
- When should a chat summary be generated?
- What should be injected into every prompt?
- How should the user inspect context?
- Should memory updates be automatic, manual, or both?
- How much should iOS do before macOS is mature?

## Next immediate action

Move the generated files into the local KodAi workspace:

```text
KodAi/
├── docs/
└── memory/
```

Then commit:

```bash
git add docs memory
git commit -m "Add shared KodAi docs and memory files"
git push
```
