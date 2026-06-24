# KodAi iOS — Ship Plan (v1)

> Scope-of-record for shipping KodAi iOS. Supersedes the "local chatbot" framing.
> Decided 2026-06-24. Read alongside `vision.md`, `kodai_beta_piece.md`,
> and `kodai_standing_report.md`.

---

## The reframe (the whole strategy in one line)

> **KodAi iOS is not a chatbot. It is an instrument for watching an AI think —
> privately, in your hand.**

Chat is demoted from *the product* to *the thing that generates traces for the
observatory.* The small model (LFM2.5‑1.2B, 4‑bit, 2,048 ctx) is not an apology —
it is the **premise**: small enough to read end‑to‑end, honest enough to be wrong
in front of you. "Probability is not correctness" is only demonstrable on a small
local model. **The constraint is the brand.**

We compete in **AI literacy + wonder + privacy**, not assistant/productivity.
Target user: AI/ML learners (the "builder"), educators, the AI‑curious, and the
privacy‑minded. App Store subtitle direction:

> *"A language model that runs entirely on your iPhone — and lets you watch it think."*

---

## The funnel: web demos → iOS instrument

| Layer | Role |
|---|---|
| **Web (CTXA site)** — `riverview.html`, `token-atlas.html` ("see the model think") | The **demo**. Pre‑baked traces, no install, draws people in. Top of funnel. |
| **iOS app** | The **real instrument**. *Your* prompt, *your* model, live, private, offline. The thing the demo makes you want. |

iOS's job is not to showcase — it's to deliver what the demo promises:
**"now do it with your own words, privately."**

---

## The home model: two lenses on the kept ChatView

`ChatView` stays as the home (we love it — do **not** strip it). It is reframed
from "chatbox" to "instrument": a prompt bar + a lens toggle. The two modes are
**lenses / zoom levels on one conversation**, not two separate apps.

- **Tracer = the moment lens** (DEFAULT, the hook): one response, rendered live as
  the river/globe instead of a flat bubble. You can flip the same response
  river ↔ globe. Hero of the first prompt.
- **Atlas = the journey lens** (the payoff you *zoom out* to): the whole
  conversation as a planet; each exchange lands as a continent. Accrues over the
  session — it is the reward for staying, not the cold first‑prompt view.

**Flow:** open → ChatView (prompt bar: "give it something to think about") →
send prompt → the reply streams into a live, confidence‑colored bubble (thinking
visible inline) → a prominent **"Watch it think →"** affordance under the reply
opens the immersive view for the selected lens (River/Globe in Tracer, the planet
in Atlas). No hard two‑tile chooser; default Tracer, toggle to Atlas.

**Pure click‑into — the views never auto‑open** (decided 2026‑06‑24). An
auto‑modal-on-every-reply proved too jarring; and the immersive views (River is a
full‑screen scroll, Globe is SceneKit 3D) are built for full‑screen, so they
belong as click‑into destinations, not inline widgets or surprise modals. The chat
stays the calm spine; the instrument is one obvious tap away.

**Design note — the asymmetry that drove this:** Tracer is single‑response (great
first prompt); Atlas is whole‑conversation (anticlimactic on prompt #1). Giving
each its natural job resolves it.

---

## Finalized v1 scope (move, don't strip)

| Surface | v1 decision |
|---|---|
| **ChatView** | **Keep** as home — reframe to instrument: prompt bar + Tracer/Atlas lens toggle |
| **River + Globe** (`RiverView`, `GlobeView`) | **Tracer lens** — response renders here live; flip between them |
| **Thread Atlas** (`ThreadGlobeView`) | **Atlas lens** — the zoom‑out; accrues over the session |
| **Inspector / live trajectory color** | Keep — the "deeper layer" tap‑in |
| **Sampler Playground** (`SamplerPlaygroundView`) | **Keep in‑app**, demoted to an "advanced / dials" surface, out of the first‑run path. **Also on web.** Core to the cause‑and‑effect lesson (raise temp → more gold). |
| **Projects / tasks / memory / workspace** | **Demote** behind "Workspace (beta)" — present, not the front door |
| **First‑run** | Light coachmark that drops a *starter prompt* so the user watches **their own** action immediately (not a passive canned demo) |

The two cuts from the **front door** are sampler‑knobs and the workspace — both
**kept in the app**, just no longer what a new user hits first.

---

## Ship vehicle

**TestFlight beta first** → validate the wedge with a curated AI‑curious / student
audience and catch iPhone‑14 perf/crashes → then App Store.

---

## Engineering gates before submit

- **Model delivery:** keep the 697 MB GGUF **bundled** for v1 (offline‑from‑second‑one
  is the whole pitch; no `ModelDownloader` to build/maintain). Revisit size later.
- **iPhone‑14 perf pass** (constraint device): cold‑start, peak memory, thermal.
  First‑run animation must not stutter while the model loads in background.
- **Airplane‑mode launch test** — crash‑free with no network. It is the brand.
- **Reduce‑motion path** for the animated first‑run + live Tracer render.
- **KodaiKernel / SwiftData (K2) stability** — continues in parallel; does **not**
  gate the glass‑box launch.

---

## Build sequence

1. **Tracer/Atlas lens toggle on ChatView** + "response renders as the instrument"
   (the home rebuild). *First code task.*
2. **First‑run coachmark** with a starter prompt → watch‑their‑own‑action.
3. **Demote** sampler + workspace out of the front‑door path (behind advanced /
   "Workspace (beta)").
4. **Perf + airplane‑mode pass** on iPhone 14.
5. **TestFlight assets**: subtitle, screenshot captions (5 = the views as lessons),
   "No Data Collected" privacy label, beta notes from `kodai_beta_piece.md`.
6. Submit to TestFlight.

---

## Changelog

- **2026-06-24** — Initial ship plan. Reframe to "instrument, not chatbot";
  web=demo / iOS=real‑instrument funnel; two‑lens (Tracer/Atlas) home on kept
  ChatView; sampler kept in‑app (demoted) + web; workspace demoted; TestFlight
  first. Locked with the user.
