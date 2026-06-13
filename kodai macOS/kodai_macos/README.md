# Kodai macOS

Kodai macOS is a native macOS AI chatbot built with SwiftUI and Apple's Foundation Models framework. It runs entirely on-device — no API keys, no network calls.

## Requirements

| Requirement | Version |
|---|---|
| macOS | **26.0+** |
| Xcode | **26.0+** |
| Apple Intelligence | Enabled on device |

Apple's Foundation Models framework is only available on macOS 26+. The app will not build on earlier toolchains.

## Description

Kodai is an early-stage macOS app focused on local AI assistance. The goal is to create the private and local assistant that exposes its "thinking" and work as its made by and used by an AI engineer. It should priorize fast/smooth performance and and stay useful while experimenting with Apple's on-device AI capabilities.

This project is a personal development experiment.

## What the App Does Right Now

A macOS chatbot with a collapsible sidebar, persistent chat history, markdown rendering, and five assistant modes (Chat, Organize, Summarize, Checklist, Debug). Responses stream token-by-token from `LanguageModelSession`.

## Tech Stack

* Swift + SwiftUI
* Apple Foundation Models (`LanguageModelSession`)
* SwiftData (persistent chat history)
* macOS 26 / Xcode 26

## Current Features

* Native macOS SwiftUI app
* Streaming on-device AI responses
* Five output modes with distinct system prompts
* Persistent chat history via SwiftData
* Collapsible sidebar with thread list and mode picker
* Markdown rendering for assistant messages
* Dark, glass-inspired visual style
* Context usage estimate (token meter)
* Stop generation mid-stream

## Planned Features / Roadmap

* Code block syntax highlighting
* Local memory and conversation summaries
* File drag-and-drop context
* Search across chat history
* Better app development organization tools
* Future Xcode / source editor workflow support

## Setup

```
git clone <repo>
open KodAiMacOS.xcodeproj   # requires Xcode 26
```

Select the `KodAi macOS` scheme, then build and run (⌘R). No additional setup needed.

## Project Structure

```
kodai_macos/
  KodAiMacOS.xcodeproj/
  kodai_macos/            ← all Swift source files
    docs/
      architecture.md     ← component map and data flow
  kodai_macosTests/
  kodai_macosUITests/
  CLAUDE.md               ← context for AI coding agents
  README.md
```

## Project Status

Early development. Main priority is a clean, stable local chat experience before expanding into developer workflow features.

## Note

Experimental personal project. Built as a learning exercise and foundation for a future local developer assistant.
