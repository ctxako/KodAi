# KodAi

On-device LLM research lab for macOS and iOS.

KodAi breaks LLMs down into their most basic pieces. It's a study environment where context assembly, token sampling, and tool-call parsing are exposed and manipulable instead of hidden behind an API. What started as a deep dive into how those systems actually work evolved into proving that a 1.2B parameter model can be genuinely useful through grammar-constrained generation and structured tool routing. Observatory views render token flows and probability distributions as visual instruments. Everything runs on-device. No cloud, no API keys, no data leaves the machine.

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

The app targets (macOS, iOS, kodai-consumer) are in active development and not available for public use.

**KodaiCore**: `swift build && swift test`

## Screenshots

<!-- TODO -->

