# Route-eval results log

Harness: `KodaiCore` → `swift run -c release kodai-route-eval --model-path <gguf> [--k N] [--only cats] [--verbose]`
Model: LFM2.5-1.2B-Instruct Q4_K_M · temp 0.3 · primed native format · 79 cases, K=1 unless noted.
**K=1 is noisy** (±5% category swings run-to-run) — use K=2/3 before declaring a prompt change a win or loss.

## 2026-07-01 — v2 surface bring-up (4 iterations)

| Iteration | Routing overall | ACTIONS e2e | First-try-valid | Unsupported→respond |
|---|---|---|---|---|
| 1. v2 baseline (post-rebuild) | 70.9%* | 43.3% | — | 92.9% |
| 2. + hybrid-format parser fixes, past-due-date sanity | 70.9% | 60.0% | 89.9% | 92.9% |
| 3. + routing-rules prompt block | 78.5% | 73.3% | 89.9% | 50.0% ⚠ |
| 4. + respond-anchor rule, files/notification arg aliases | 78.5% | 71.7% | 91.1% | 64.3% |
| 5. + positional/colon-arg parser support | **79.7%** | **76.7%** | **97.5%** | 71.4% |

*Iteration 1 ran before the alternates-aware scorer; roughly comparable.

### What moved the numbers

- **Parser robustness was worth +33 points of ACTIONS.** The model emits four
  call shapes: kwargs `tool(k="v")`, JSON-in-parens `tool({"k": "v"})`, the
  same with a dropped closing paren, and positional+colon
  `tool("v", "k": "v")`. Only the first was parsed before; the rest lost all
  arguments and failed validation as "missing field".
- **The routing-rules block fixed calendar (50%→100%)** — same finding as v1:
  explicit prompt rules beat tool-description wording on this 1.2B.
- **Rules made the model over-eager** (unsupported 93%→50%); the
  "everything else → respond" anchor claws back to ~71%. Still below the v1
  bar — next lever, carefully (negative enumerations have regressed before).

### Known remaining gaps (model-level, for the next session)

- `id_flow` 25%: "mark X done / cancel my 3pm" should call the list tool
  first for the id; model jumps to create/complete with invented ids.
- `open_url` vs `web_fetch`: "open apple.com" routes to web_fetch (0/2).
- `reminders_list` vs `create`: "what do I need to do today" sometimes creates.
- list-item arg quality: list_name often wrong/missing on informal phrasing.
- "what's 15% of 200" → parse NONE (model tries math, emits garbage).

### Bar (PRODUCTION_PLAN M4)

>90% single-step end-to-end. Not met yet (76.7%). Next steps: K=3 baseline,
id-flow + open/fetch prompt rules, then re-measure; if the bar stays out of
reach, evaluate Q5_K_M against the iPhone 12 memory ceiling.
