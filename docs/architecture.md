# KodAi Top-Level Architecture

## Purpose of this document

This is the shared product and system architecture for KodAi.

This file is not the same as the macOS implementation architecture.

The macOS architecture explains how the current SwiftUI app works.

This document explains the larger KodAi system that both macOS and iOS should eventually follow.

## Architecture principle

KodAi should be built as a layered local-first system:

```text
User Interface
  ↓
Conversation Layer
  ↓
Project Layer
  ↓
Context Engine
  ↓
Memory Engine
  ↓
Model Layer
  ↓
Persistence Layer
```

Each layer should have a clear job.

The app should not become a giant view model that knows everything forever.

## Workspace structure

Recommended top-level workspace:

```text
KodAi/
├── docs/
│   ├── vision.md
│   ├── roadmap.md
│   ├── architecture.md
│   └── decisions.md
│
├── kodai_macos/
│   ├── README.md
│   ├── CLAUDE.md
│   ├── kodai_macos.xcodeproj/
│   └── kodai_macos/
│       ├── *.swift
│       └── docs/
│           └── architecture.md
│
├── kodai_ios/
│   ├── README.md
│   ├── CLAUDE.md
│   └── kodai_ios.xcodeproj/
│
├── research/
├── designs/
├── prompts/
└── experiments/
```

## Core objects

### KodaiProject

A durable workspace for a goal, app, research thread, or life area.

Suggested fields:

```swift
KodaiProject
- id: UUID
- title: String
- summary: String
- status: ProjectStatus
- createdAt: Date
- updatedAt: Date
- chats: [KodaiChatSession]
- memories: [KodaiMemory]
- tasks: [KodaiTask]
- files: [KodaiFileReference]
```

### KodaiChatSession

A conversation thread.

Suggested fields:

```swift
KodaiChatSession
- id: UUID
- title: String
- createdAt: Date
- updatedAt: Date
- project: KodaiProject?
- messages: [KodaiChatMessage]
- summary: String?
```

### KodaiChatMessage

A single user or assistant message.

Suggested fields:

```swift
KodaiChatMessage
- id: UUID
- role: ChatRole
- content: String
- createdAt: Date
- tokenEstimate: Int?
- contextUsed: [KodaiContextSource]?
```

### KodaiMemory

A compressed, durable piece of knowledge.

Suggested fields:

```swift
KodaiMemory
- id: UUID
- title: String
- content: String
- type: MemoryType
- source: MemorySource
- confidence: Double?
- createdAt: Date
- updatedAt: Date
- project: KodaiProject?
```

Memory types:

- projectSummary
- decision
- userPreference
- taskInsight
- fileSummary
- researchNote
- architectureNote

### KodaiTask

A lightweight actionable item.

Suggested fields:

```swift
KodaiTask
- id: UUID
- title: String
- notes: String?
- status: TaskStatus
- priority: TaskPriority
- createdAt: Date
- updatedAt: Date
- project: KodaiProject?
```

### KodaiFileReference

A reference to a local file or imported document.

Suggested fields:

```swift
KodaiFileReference
- id: UUID
- name: String
- path: String?
- fileType: String
- summary: String?
- createdAt: Date
- updatedAt: Date
- project: KodaiProject?
```

## Conversation lifecycle

A KodAi conversation should follow this flow:

```text
1. User sends message
2. App identifies active project
3. Context Engine assembles context pack
4. Model Layer streams response
5. UI displays response
6. Persistence Layer saves messages
7. Memory Engine decides whether summary/task/decision updates are needed
8. User can inspect what changed
```

## Context Engine

The Context Engine decides what gets sent to the model.

It should avoid dumping everything into the prompt.

Recommended context order:

```text
1. App identity and mode prompt
2. Current project summary
3. Active tasks
4. Relevant durable memories
5. Relevant file summaries
6. Recent chat messages
7. Current user message
```

## Context budget strategy

Context should be treated as a limited resource.

Suggested tiers:

### Always included

- selected mode prompt
- current user message
- recent message window

### Included when project exists

- project summary
- active tasks
- recent project decisions

### Included only when relevant

- file summaries
- older chat summaries
- research notes
- archived memories

### Never blindly included

- entire old conversations
- entire source files
- every project note
- every memory

## Memory Engine

The Memory Engine turns raw conversations into durable structure.

It should answer:

- Did this conversation create a new decision?
- Did it create a task?
- Did it change the project summary?
- Did it reveal a user preference?
- Did it create a reusable technical note?
- Should this information be archived instead of kept active?

## Memory hierarchy

```text
Raw messages
  ↓
Chat summary
  ↓
Project summary
  ↓
Durable memories
  ↓
Archived memory
```

Raw messages are the least efficient form of memory.

Summaries and decisions are more valuable for long-term use.

## Model Layer

Initial model layer:

- Apple Foundation Models
- on-device
- private
- no API keys
- no network calls

Future model layer:

```text
KodaiModelRouter
├── AppleFoundationModelProvider
├── LocalLLMProvider
└── CloudModelProvider
```

The router should decide which model to use based on:

- privacy requirement
- task difficulty
- context size
- tool need
- availability
- user preference

## Tool Layer

Tools should be explicit, inspectable, and safe.

Early internal tools:

- create chat
- rename chat
- delete chat
- create project
- update project summary
- create task
- mark task complete
- summarize chat
- summarize project
- attach file summary

Future tools:

- file search
- web search
- calendar
- reminders
- GitHub
- Xcode/source editor workflows

## UI architecture

macOS should remain the command center.

Possible macOS layout:

```text
Sidebar
├── New Chat
├── Modes
├── Projects
├── Chats
└── Settings

Main Area
├── Project/Chat Header
├── Message Stream
├── Context Inspector
└── Composer
```

iOS should be a companion.

Possible iOS layout:

```text
Tabs or compact stack
├── Today
├── Projects
├── Chat
└── Capture
```

## Key rule

Shared product architecture belongs in the top-level `docs/`.

Platform-specific implementation architecture belongs inside each app repo.

Do not duplicate implementation docs across macOS and iOS.
