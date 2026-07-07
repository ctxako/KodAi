# Kodai macOS — Claude Code Context

## Requirements

- **macOS 26+** and **Xcode 26+** are required. The app uses Apple's Foundation Models framework (`import FoundationModels`), which is only available on macOS 26. Builds will silently fail on older toolchains.
- No third-party Swift packages. Everything runs on-device using Apple frameworks only.

## Project structure

```
kodai_macos/                  ← repo root
  KodAiMacOS.xcodeproj/       ← Xcode project
  kodai_macos/                ← all app source files (canonical location)
    kodai_macosApp.swift
    ContentView.swift
    chatviewmodel.swift
    kodaimodel.swift
    kodaichatsession.swift
    outputmode.swift
    composerview.swift
    chatbubble.swift
    chatmessage.swift
    chatscrollview.swift
    kodaisidebar.swift
    kodaisettings.swift
    kodaibackground.swift
    kodaiglass.swift
    kodaimarkdowntext.swift
    Assets.xcassets/
  kodai_macosTests/
  kodai_macosUITests/
  docs/
  README.md
```

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-discovers every file inside `kodai_macos/`. You do **not** need to manually add files to the Xcode project; just drop Swift files into that directory.

## How to build

Open `KodAiMacOS.xcodeproj` in Xcode 26, select the `KodAi macOS` scheme, and build (⌘B) or run (⌘R). No setup steps required.

## Bundle identifiers

- macOS app: `com.ctxa.kodai.macos`
- iOS app: `com.ctxa.kodai.ios`
- Shared CloudKit container (future): `iCloud.com.ctxa.kodai`
- macOS workspace CloudKit: deferred to K2G (currently disabled)

## Architecture

All app logic runs on `@MainActor`. The core data flow is:

```
ContentView
  └── ChatViewModel (@Observable, @MainActor)   — central state coordinator
        ├── KodaiModel                          — wraps LanguageModelSession
        │     └── SystemLanguageModel.default   — Apple Foundation Models
        └── ModelContext (SwiftData)            — persistence
```

See `docs/architecture.md` for full details.

## Key conventions

- **Files**: all lowercase, no spaces, no prefixes (`chatviewmodel.swift` not `ChatViewModel.swift`)
- **Actors**: `@MainActor` on both `ChatViewModel` and `KodaiModel`. Build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is active.
- **Observable**: use `@Observable` macro (not `ObservableObject`) for new state classes
- **SwiftData**: persistence models live in `kodaichatsession.swift`. Add new `@Model` classes there.
- **Mode system**: all output modes live in `outputmode.swift`. Adding a new mode means adding a case + `systemPrompt` + an icon in `kodaisidebar.swift`
- **Design**: dark glass aesthetic — `.ultraThinMaterial`, white-on-opacity foreground, `RoundedRectangle(cornerRadius:, style: .continuous)`, `.spring(response: 0.32, dampingFraction: 0.86)` for animations

## What NOT to do

- Do not add network calls or external API keys — this app is fully on-device by design. The single exception is localhost Ollama (`127.0.0.1:11434`): kb_search embeddings and the optional Ollama chat engine talk to it, and nothing ever leaves the machine. Never add a remote host.
- Do not add SPM packages without discussing first
- Do not create Xcode navigator groups without immediately renaming them (unnamed groups create "New Group" folders on disk)
- Do not change `MACOSX_DEPLOYMENT_TARGET` below 26.4
- Do not use `ObservableObject`/`@Published` — the project uses the `@Observable` macro
