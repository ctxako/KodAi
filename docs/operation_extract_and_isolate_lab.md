# Operation: Extract & Isolate Lab

*Engineering summary — June 23, 2026*

## The problem we set out to solve

Benchmarking lived *inside* the shipping iOS app. To answer a basic question — "is this model fast enough on an iPhone?" — you had to build the app, tap through the UI by hand, and eyeball numbers that were never recorded anywhere. Research code and product code were tangled in the same target, which meant every experiment risked the production build, and no result was reproducible or comparable across runs.

Bottom line: we had an inference engine but no instrument to measure it, and no system of record for what we learned.

## What we built

A clean separation into four independent pieces, each with one job:

| Piece | What it is | What it gives you |
|---|---|---|
| **Product app** | The iOS app, now runtime-only | Ships lean — zero benchmark baggage |
| **`kodai-bench`** | A macOS CLI harness | Reproducible measurements, one command |
| **D1 + Worker** | Cloudflare database + API | A permanent, queryable system of record |
| **Dashboard** | Private web view at `ctxa.ltd/lab/kodai/bench/` | See every experiment at a glance |

## The architectural keystone

The win that made everything else possible: we lifted the llama.cpp inference stack out of the app into a shared **KodaiRuntime** package. The exact same code now powers *both* the phone and the benchmark harness. We're no longer measuring a copy of the engine — we're measuring the real one.

The runtime's API was redrawn around neutral types (`KodaiRuntimeMessage` + a system prompt) so it has no idea whether it's talking to a chat UI or a test rig — and a `ModelFileResolver` seam lets each environment supply models its own way (app bundle on iOS, file path on the CLI).

```
KodaiKernel      Foundation-only value types (SamplerKnobs, configs, messages)
KodaiRuntime     llama.cpp-backed actors (LocalModelRuntime, LlamaRuntime, …)
KodaiPersistence SwiftData models
KodaiCore        umbrella re-export
```

## Proof it works — end to end

We ran a real baseline and watched the data flow the whole way through:

- **Measured:** qwen2.5-1.5B (Q4_K_M) on an Apple M4 — **57.1 tok/s avg, ~168 ms time-to-first-token, ~194 MB** across 5 fixed prompts, with a warmup pass so cold-start never pollutes the numbers.
- **Captured:** the CLI POSTed results through the Worker into D1, Bearer-authenticated.
- **Served:** the dashboard pulls them back and renders summary cards, a tokens/sec chart, and a sortable table.
- **Secured:** the dashboard sits behind Cloudflare Access — login-gated to one email — while the API stays token-protected.

## What this unlocks

- **Hypotheses become records.** Every experiment starts with a written hypothesis and ends with durable, comparable data — not a screenshot.
- **One command, repeatable.** Swap a model or a quant, rerun, and the dashboard updates. No rebuild, no manual tapping.
- **It already earned its keep.** The harness immediately surfaced that the vendored llama.cpp (b5200) *couldn't even load* the app's intended LFM2.5 model — a production-blocking gap that hand-testing had missed. Now fixed (bumped to b9775 with lfm2 support).

## Running an experiment

```bash
/Users/ctxa/kodai/KodaiCore/.build/release/kodai-bench \
  --model-path <gguf> \
  --prompts /Users/ctxa/kodai/kodai_ios/kodAI_chatbot_dev/KodAiBench/prompts.json \
  --experiment-id <id> --device "Apple M4" \
  --endpoint https://bench-api.ctxa.ltd --token <BENCH_TOKEN>
```

New experiment ids need a row in the `experiments` table first (foreign key). Without `--endpoint`, results print to stdout (local-only mode).

## Component reference

| Component | Location |
|---|---|
| Shared runtime | `KodaiCore/Sources/KodaiRuntime/` |
| Shared value types | `KodaiCore/Sources/KodaiKernel/` |
| CLI harness | `KodaiCore/Sources/KodAiBench/` |
| Prompt set | `kodai_ios/kodAI_chatbot_dev/KodAiBench/prompts.json` |
| Worker API | `~/CTXA.LLC/kodai-bench-worker/` (D1 `kodai-bench`, uuid `bf92524c-…`) |
| Dashboard | `~/CTXA.LLC/ctxa-site/lab/kodai/bench/` + `js/bench.js` |
