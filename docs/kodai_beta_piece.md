# KodAi — A Beta, and a Glass Box

*On the technical work so far, written from the belief that what we have is*
*educational and earns its place.*

There are two KodAis, and they share a brain but not an engine.

The **macOS** build runs on **Apple Foundation Models** — the on-device model
Apple ships with the system. That's the right answer for the Mac, and it's the
whole of what needs saying here: same product mind, native engine, no further
mystery to manufacture. The interesting, hard-won work — the part worth opening
up — is on **iOS**.

---

## The premise

KodAi iOS is a local-first AI workspace built inside a **glass box**. The model
runs entirely on the phone through a quantized `llama.cpp` engine
(LFM2.5‑1.2B, 4‑bit, a 2,048‑token window) — no keys, no server, no round trip.
And almost every decision the model makes on its way to a word is made
*inspectable*.

That second part is the thesis. Most chat apps show you the answer. KodAi shows
you the **deciding** — and it does it honestly, by reading the model's raw
probabilities *before* the sampler picks, at every single step. Four numbers
fall out of each token and end up carrying the entire visual language:

- **probability** of the chosen token — *color*
- **entropy**, the spread of the distribution — *size / width*
- **margin**, the gap between the top two candidates
- **surprise**, −log p of what was actually emitted

And one event worth its own color: when sampling lands on something *other* than
the model's single favorite token. That gets **gold**, and gold is rationed
everywhere — it is the only warm note in an otherwise nocturnal palette, reserved
for the genuinely exceptional moment where the dice overruled the favorite.

This is the educational core, and it's why the project earns its keep. It
operationalizes one stubborn, important idea: **probability is not correctness.**
A confident token can be wrong; a hesitant one can be right. You can't lecture
someone into feeling that. You can let them watch it.

Everything I build on this thing accumulates into the same place. The engine, the
telemetry, the three visualizations, the sampler controls, the context engine —
they're not separate features so much as different windows onto one organism. Add
a measure in one place and three views light up. That accumulation *is* the
entity. And honestly, that's also where the mystery lives: there's far more we
could say about what these surfaces reveal than we actually understand yet. We're
reading a 1.2‑billion‑parameter mind one decision at a time and finding it has
geography, weather, and weather we didn't put there.

It is, at the end of the day, a **beta**. That's not a hedge — it's the frame.
This is an instrument early in its life, and saying so is part of being a glass
box.

---

## The three views — globe tracing, the river, the token atlas

All three are painted from the *same* per-token telemetry. That's the discipline
that makes them coherent: one source of truth, three radically different
expressions. Cyan always means "probable," gold always means "the sampler
overrode the favorite," width/size always means "uncertain" — in every view.
Learn the grammar once, read all three.

### Globe tracing — the Decision Globe (`GlobeView`)

One response, wrapped onto a transparent glass sphere. Each analyzed token is a
**bead** on a pole-to-pole spiral, north (step 0) to south. Color is the chosen
token's probability; size is its entropy. The path the model actually walked is a
**tracer** ribbon threading the beads in generation order, tinted by heat as it
goes. Where sampling diverged from the favorite, a tiny **gold satellite** marks
the spot. Focus a token and faint **vessels** bloom out to the alternatives it
weighed but didn't say — the raw most-likely choice glowing gold when it differs
from what came out.

You don't fly a camera. There's a fixed crosshair at center, and you *spin the
globe* to bring the active token to front. A scrubber replays the generation in
order: the past stays as a quiet trail, the present glows, the future recedes.

What it teaches is **sampling, made visible**. The gold satellite is the whole
lesson in one mark: *here the model's favorite was X, but the dice landed on Y.*
Scrubbing turns a finished paragraph back into a process that happened in time.

### The river — Follow the River (`RiverView`)

The same single response, told as moving water instead of a sphere — a
scroll-driven, full-screen nocturnal channel. The **spine** is the chosen path
down the center. **Channel width** is entropy: turbulent, uncertain stretches
widen; confident ones run narrow. Rejected candidates fan off as **tributaries**.
And where sampling didn't follow the model's strongest current, the channel
**forks** and leaves a ghost branch behind — successive forks alternate sides so
a noisy passage reads as a *meander*, not a runaway diagonal. The playhead sits
fixed at center; scrolling follows the current one decision at a time.

This is the most poetic of the three, and it carries the two hardest ideas
physically: *width-as-uncertainty* and *fork-as-sampling*. You can feel a
turbulent passage. You can see the exact moment the current split. And nothing
relies on color alone — brightness and width carry the same signal, which keeps
it legible for color-blind readers.

### The token atlas — Thread Atlas (`ThreadGlobeView`)

Zoom all the way out. Where the globe is one response, the **atlas** is the
*whole conversation* on one glass planet. Each traced user→assistant exchange
becomes a **continent**. Its **area** is that exchange's share of the
2,048-token context window (real math — prompt tokens estimated, response tokens
counted exactly, laid down as area-accurate spherical caps); its **tint** is the
exchange's mean confidence. **Latitude is chronology** — earliest near the north
pole, latest near the south. A toggleable **vine** threads the continents in
order, and a continent holding any sampled-over-favorite choice gets a single
**gold beacon** rather than turning the whole region yellow. Focus a continent
and its tokens scatter into a local spiral; tap one and you get the same vessels
as the globe; "open token replay" drills all the way down into the per-response
`GlobeView`.

What the atlas teaches is **context as a finite, spatial resource**. Watching
continents accumulate and crowd the planet is a visceral answer to "why do long
chats fill up and cost more?" It's the same telemetry as the other two views,
arranged as overview→detail: a whole conversation you can hold in your hand and
then dive into, exchange by exchange, token by token.

---

## Where this leaves us

The globe, the river, and the atlas are three faces of one honest idea: that a
language model's output is the visible tip of a long chain of probabilistic
decisions, and that those decisions can be made beautiful, spatial, and
*teachable* without lying about them. That's the case for KodAi having a place —
not as a better chatbot, but as a working instrument for seeing how one actually
thinks in probabilities, running privately in your hand.

The macOS sibling rides Apple's Foundation Models and shares the product mind.
The iOS build is where the glass box is real.

And it's a beta. The accumulation has only started.
