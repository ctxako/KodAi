# KodAi

On-device LLM research lab for macOS and iOS.

I built this to break down the world of LLMs into the most basic pieces. As a visual learner studying CS with a focus on AI, I needed an environment where the internals are exposed and manipulable — not hidden behind an API. This started as a study into how context assembly, token sampling, and tool-call parsing actually work, and evolved into proving that a 1.2B parameter model can be genuinely useful through techniques like grammar-constrained generation and structured tool routing. The idea was to clash LLMs and art — token flows rendered as rivers, probability spaces as globes — while keeping the whole thing within scope as a research and educational experiment. Everything runs on-device. No cloud, no API keys, no data leaves the machine.

## Targets

### macOS — Workspace

SwiftUI workspace powered by Apple Foundation Models. Chat with persistent sessions, project organization, a context inspector that shows exactly what the model sees before each generation, and a daily briefing engine. Optional Ollama backend for local models. Dark glass UI.

### iOS — Observatory

Inference instrument built around llama.cpp. Token trace views, a sampler playground for tuning temperature / top-p / top-k in real time, and context-visibility overlays. The idea is to watch the model think, not just read its output.

### kodai-consumer — Action Agent

Standalone offline iOS agent. 20 tools across 7 domains (calendar, reminders, contacts, files, clipboard, notifications, system). Grammar-constrained tool calls via GBNF ensure the model's output is always valid JSON — no parse failures. Multi-step agent loop chains up to 6 tool calls per task. Write actions require user confirmation. Runs LFM 2.5 1.2B (Q4_K_M GGUF) entirely on-device.

## Architecture

```
KodaiCore (shared Swift package)
├── KodaiKernel      — inference types, context assembly, tool-call grammar/parsing/validation
├── KodaiRuntime     — llama.cpp wrapper (tokenization, prefill, decode, sampling)
├── KodaiPersistence — SwiftData models, schema migrations, context block providers
└── KodaiBenchKit    — benchmark harness (tokens/sec, time-to-first-token, memory)
```

## Stack

- Swift 6.2, SwiftUI, SwiftData
- llama.cpp (vendored xcframework, build b9775)
- Apple Foundation Models (macOS 26+)
- GBNF grammar-constrained generation
- No third-party Swift packages, no network calls

## Building

**macOS**: `kodai macOS/kodai_macos/KodAiMacOS.xcodeproj` — Xcode 26+, macOS 26+.

**iOS observatory**: `kodai_ios/kodAI_chatbot_dev/kodAI_chatbot_dev.xcodeproj` — requires a bundled GGUF model.

**kodai-consumer**: `kodai-consumer/kodai-consumer.xcodeproj` — iOS 26+, KodaiCore at `../KodaiCore`.

**KodaiCore**: `swift build && swift test`

## Screenshots

<!-- TODO -->

---

Built by ctxa.
