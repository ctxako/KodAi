# KodAi Inference Bench — Test Plan

> Private research bench for measuring on-device AI inference performance.
> Covers macOS (Apple Foundation Models) and iOS (llama.cpp) benchmarking.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    KodaiCore Package                        │
│                                                             │
│  KodaiBenchKit (shared)                                     │
│  ├── BenchmarkRun        — D1 row model                     │
│  ├── BenchPrompt         — prompt set (embedded + JSON)      │
│  ├── ResultUploader      — POST runs to bench Worker         │
│  ├── MemoryMeasurement   — task_vm_info memory footprint     │
│  ├── DeviceInfo          — sysctl device identifier          │
│  └── BenchmarkRunner     — llama.cpp runner (iOS/CLI)        │
│                                                             │
│  KodAiBench (CLI)         — llama.cpp bench (GGUF models)    │
│  KodaiBenchMac (CLI)      — Apple FM bench (macOS 26+)       │
│  KodaiBenchServer (local) — SSE server for live dashboard    │
└─────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
   bench-api.ctxa.ltd            Dashboard (browser)
   (Cloudflare Worker)           ctxa.ltd/lab/kodai/bench/
         │
         ▼
   D1: kodai-bench
   (experiments + runs)
```

### Targets

| Target             | Platform | Backend               | Model Source        |
|--------------------|----------|-----------------------|---------------------|
| `KodAiBench`       | macOS    | llama.cpp             | Local GGUF file     |
| `KodaiBenchMac`    | macOS    | Apple Foundation Model| Built into macOS 26 |
| `KodaiBenchServer` | macOS    | Apple Foundation Model| Built into macOS 26 |
| iOS XCTest         | iOS      | llama.cpp             | Bundled in app      |

---

## 2. Prerequisites

- **Hardware**: MacBook Air M4 (macOS 26.0+)
- **Xcode**: Latest with Swift 6.2+
- **Tokens**: `BENCH_TOKEN=kodai-kodi-22`
- **API**: `https://bench-api.ctxa.ltd` (Cloudflare Worker)

---

## 3. Test Procedures

### 3.1 macOS CLI Bench (Apple Foundation Models)

**Purpose**: Batch-run the standard prompt set through Apple FM and upload results.

```bash
# Build
swift build --target KodaiBenchMac -c release

# Run (local only — no upload)
swift run kodai-bench-mac --experiment-id mac-baseline-001

# Run (with upload to D1)
swift run kodai-bench-mac \
  --experiment-id mac-baseline-001 \
  --endpoint https://bench-api.ctxa.ltd \
  --token kodai-kodi-22
```

**Expected output**:
- 5 prompts run with warmup pass
- Each line: `[n/5] prompt_id — X tok/s, TTFT Xms, XMB`
- JSON results printed
- "Uploaded 5 runs." if endpoint provided

**Verify**:
- [ ] Builds without errors
- [ ] All 5 prompts complete
- [ ] tok/s values > 30
- [ ] TTFT values < 500ms
- [ ] Upload succeeds (no HTTP errors)

---

### 3.2 macOS CLI Bench (llama.cpp)

**Purpose**: Batch-run prompts through llama.cpp with a GGUF model file.

```bash
swift run kodai-bench \
  --model-path /path/to/model.gguf \
  --experiment-id baseline-001 \
  --device "Apple M4" \
  --endpoint https://bench-api.ctxa.ltd \
  --token kodai-kodi-22
```

**Verify**:
- [ ] Builds without errors
- [ ] Model loads and warmup completes
- [ ] All 5 prompts complete
- [ ] Results upload successfully

---

### 3.3 Live Bench Server

**Purpose**: Stream real-time inference stats to the dashboard via SSE.

```bash
# Start server (default port 8788)
swift run kodai-bench-server

# Custom port
swift run kodai-bench-server --port 9000
```

**Manual test with curl**:
```bash
curl -N -X POST http://localhost:8788/run \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Say hello","system":"Be brief."}'
```

**Expected SSE output**:
```
data: {"text":"Hello!","tps":42.5,"ttft_ms":280,...,"done":false}
data: {"text":"Hello!","tps":45.1,"ttft_ms":280,...,"done":true}
```

**Verify**:
- [ ] Server starts and prints listening message
- [ ] `GET /health` returns `{"status":"ok"}`
- [ ] `POST /run` streams SSE events
- [ ] Each event has: text, tps, ttft_ms, memory_mb, elapsed_ms, thermal, done
- [ ] Final event has `done: true`
- [ ] CORS headers present (Access-Control-Allow-Origin: *)

---

### 3.4 Dashboard — Historical Data

**URL**: `http://localhost:8787/lab/kodai/bench/` (local) or `ctxa.ltd/lab/kodai/bench/`

**Verify**:
- [ ] Token prompt appears on first visit
- [ ] Experiments load in dropdown
- [ ] Summary cards show averages (tok/s, TTFT, memory, run count)
- [ ] Hint text appears under each card value
- [ ] Hovering a card shows educational tooltip
- [ ] Platform tabs (All / macOS / iOS) filter data
- [ ] "macOS" tab shows context banner for Apple FM
- [ ] "iOS" tab shows "No runs" when no iOS data exists
- [ ] Tok/s chart renders with correct values
- [ ] TTFT chart renders with correct values
- [ ] Run log table is sortable (click column headers)
- [ ] Backend column shows "Apple FM" or "llama.cpp"
- [ ] Glossary section ("What am I looking at?") renders 6 cards

---

### 3.5 Dashboard — Live Run

**Pre-req**: `kodai-bench-server` running on localhost:8788

**Verify**:
- [ ] Green dot + "Server connected" when server is running
- [ ] Red dot + "Server offline" when server is stopped
- [ ] Type prompt → click Run → response streams in
- [ ] Gauges update live: tok/s, TTFT, Memory, Elapsed, Thermal
- [ ] Run button shows "Running…" during inference
- [ ] Run button re-enables after completion
- [ ] Response text renders in the output area

---

## 4. D1 Experiments

| Experiment ID         | Purpose                                          |
|-----------------------|--------------------------------------------------|
| `baseline-001`        | llama.cpp on Mac (qwen2.5-1.5b Q4_K_M)          |
| `temp-sweep-001`      | Temperature sweep on llama.cpp                   |
| `iphone-baseline-001` | iOS on-device baseline (awaiting first run)       |
| `mac-baseline-001`    | Apple FM on MacBook Air M4 (macOS 26)            |

---

## 5. File Map

```
KodaiCore/
├── Package.swift
└── Sources/
    ├── KodaiBenchKit/          # Shared types (both platforms)
    │   ├── BenchmarkRun.swift
    │   ├── BenchmarkRunner.swift
    │   ├── BenchPrompt.swift
    │   ├── DeviceInfo.swift
    │   ├── MemoryMeasurement.swift
    │   └── ResultUploader.swift
    ├── KodAiBench/             # llama.cpp CLI
    │   ├── main.swift
    │   └── FilePathModelResolver.swift
    ├── KodaiBenchMac/          # Apple FM CLI
    │   ├── main.swift
    │   └── AppleModelRunner.swift
    └── KodaiBenchServer/       # Live SSE server
        ├── main.swift
        ├── BenchServer.swift
        └── LiveRunner.swift

ctxa-site/
├── lab/kodai/bench/index.html  # Dashboard
├── js/bench.js                 # Dashboard logic
└── css/style.css               # Styles (bench section)
```

---

## 6. Quick Reference

| Action                         | Command                                                |
|--------------------------------|--------------------------------------------------------|
| Build all bench targets        | `swift build --target KodAiBench --target KodaiBenchMac --target KodaiBenchServer` |
| Run macOS bench (Apple FM)     | `swift run kodai-bench-mac --experiment-id mac-baseline-001` |
| Run macOS bench (llama.cpp)    | `swift run kodai-bench --model-path <gguf> --experiment-id baseline-001 --device "Apple M4"` |
| Start live server              | `swift run kodai-bench-server`                         |
| Serve dashboard locally        | `python3 -m http.server 8787 -d /path/to/ctxa-site`   |
