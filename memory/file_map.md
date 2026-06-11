# KodAi File Map

## Purpose

This file explains where important KodAi files live and what each area is for.

It should help a model, coding agent, or future user quickly understand the workspace without guessing.

## Recommended top-level workspace

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

## Top-level folders

### `docs/`

Shared product and architecture docs.

These docs apply to both macOS and iOS.

```text
docs/
├── vision.md
├── roadmap.md
├── architecture.md
└── decisions.md
```

Responsibilities:

- define what KodAi is
- define long-term direction
- define architecture principles
- record durable decisions
- provide context for future model sessions

Do not put platform-specific implementation details here unless they affect the whole product.

### `memory/`

Current project memory for model sessions.

```text
memory/
├── project_summary.md
├── active_tasks.md
└── file_map.md
```

Responsibilities:

- summarize current state
- track active work
- explain file structure
- reduce repeated explanation
- prepare context for Fable/Claude/GPT sessions

These files should stay short enough to paste into a model prompt.

### `research/`

Research notes, references, and model outputs.

Suggested structure:

```text
research/
├── apple_hig.md
├── foundation_models.md
├── local_llm_notes.md
├── memory_systems.md
└── fable_runs/
```

Responsibilities:

- Apple HIG research
- Foundation Models notes
- local LLM experiments
- memory/context system research
- saved model outputs

### `designs/`

Visual references, screenshots, UI ideas, and design concepts.

Suggested structure:

```text
designs/
├── screenshots/
├── inspiration/
└── concepts/
```

Responsibilities:

- app screenshots
- UI inspiration
- glass/dark theme references
- icon/logo concepts
- layout experiments

### `prompts/`

Reusable prompts.

Suggested structure:

```text
prompts/
├── fable_architecture_prompt.md
├── claude_code_prompt.md
├── ui_refactor_prompt.md
└── research_prompt.md
```

Responsibilities:

- store prompts worth reusing
- keep Fable prompts clean
- prevent wasting model sessions rewriting setup context

### `experiments/`

Prototype notes and throwaway tests.

Suggested structure:

```text
experiments/
├── model_tests/
├── context_tests/
├── ui_tests/
└── file_context_tests/
```

Responsibilities:

- benchmark notes
- context experiments
- UI tests
- architecture trials
- failed ideas worth remembering

## macOS app folder

Current app code lives in the macOS project folder.

```text
kodai_macos/
├── kodai_macos.xcodeproj/
├── kodai_macos/
│   ├── kodai_macosApp.swift
│   ├── ContentView.swift
│   ├── chatviewmodel.swift
│   ├── kodaimodel.swift
│   ├── kodaichatsession.swift
│   ├── outputmode.swift
│   ├── composerview.swift
│   ├── chatbubble.swift
│   ├── chatmessage.swift
│   ├── chatscrollview.swift
│   ├── kodaisidebar.swift
│   ├── kodaisettings.swift
│   ├── kodaibackground.swift
│   ├── kodaiglass.swift
│   ├── kodaimarkdowntext.swift
│   ├── Assets.xcassets/
│   └── docs/
│       └── architecture.md
├── kodai_macosTests/
├── kodai_macosUITests/
├── README.md
└── CLAUDE.md
```

### Important macOS files

#### `README.md`

Public project intro.

Use for:

- app description
- requirements
- current features
- setup
- status
- roadmap summary

#### `CLAUDE.md`

Coding-agent context.

Use for:

- build requirements
- file conventions
- project structure
- what not to do
- AI coding warnings

Do not use it as the main product vision.

#### `kodai_macos/docs/architecture.md`

Current macOS implementation architecture.

Use for:

- current data flow
- Swift file responsibilities
- SwiftData models
- Foundation Models integration
- UI architecture

This is not the same as the top-level `docs/architecture.md`.

## iOS app folder

Future iOS app should live separately.

```text
kodai_ios/
├── kodai_ios.xcodeproj/
├── kodai_ios/
├── kodai_iosTests/
├── kodai_iosUITests/
├── README.md
└── CLAUDE.md
```

Responsibilities:

- mobile companion app
- quick capture
- compact project view
- lightweight chat
- widgets/shortcuts later

Do not copy the macOS architecture doc directly into iOS.

## Source-of-truth rules

### Shared product direction

Source of truth:

```text
docs/
```

### Current project state

Source of truth:

```text
memory/
```

### macOS implementation

Source of truth:

```text
kodai_macos/
```

### iOS implementation

Source of truth:

```text
kodai_ios/
```

### Research/model output

Source of truth:

```text
research/
```

## Current known app source files

| File | Purpose |
|---|---|
| `kodai_macosApp.swift` | App entry point and SwiftData container setup |
| `ContentView.swift` | Root layout and main composition |
| `chatviewmodel.swift` | Central state/business logic coordinator |
| `kodaimodel.swift` | Foundation Models wrapper |
| `kodaichatsession.swift` | SwiftData chat/session persistence models |
| `outputmode.swift` | Assistant mode enum and system prompts |
| `composerview.swift` | Chat input composer |
| `chatbubble.swift` | Individual message bubble |
| `chatmessage.swift` | In-memory message model |
| `chatscrollview.swift` | Scrollable chat list |
| `kodaisidebar.swift` | Sidebar, modes, chats |
| `kodaisettings.swift` | Settings popover |
| `kodaibackground.swift` | Background visuals |
| `kodaiglass.swift` | Reusable glass surfaces |
| `kodaimarkdowntext.swift` | Markdown rendering |
| `Assets.xcassets` | App assets |

## Rule for future model sessions

When asking a model to help with KodAi architecture, provide:

```text
docs/vision.md
docs/roadmap.md
docs/architecture.md
docs/decisions.md
memory/project_summary.md
memory/active_tasks.md
memory/file_map.md
```

When asking a coding model to edit macOS code, also provide:

```text
kodai_macos/CLAUDE.md
kodai_macos/README.md
kodai_macos/kodai_macos/docs/architecture.md
relevant Swift files
```
