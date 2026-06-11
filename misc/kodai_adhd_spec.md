# kodAi — ADHD + Gen Z Design Spec Addendum

**Purpose:** This document extends the kodAi v1 roadmap with ADHD-optimized design patterns, reward systems, and organizational intelligence. These are not cosmetic — they address the core reason someone with ADHD would use (or abandon) this app.

**Design thesis:** The software must be smarter about organization than the user. If a user with no organizational skills opens this app, the app should impose gentle structure automatically. The UI should feel slightly muted and minimal, but alive — color emerges from *your* activity, not from decoration.

-----

## 1. The Color Card System ("Habit Gradient")

Inspired by Apple Card's dynamic spending visualization. Each habit gets a unique color. As you complete tasks, habits, and blocks, your daily "card" fills with those colors proportional to effort.

### How It Works

**The card** is a rounded rectangle displayed at the top of the Today view (replacing or sitting above the current date header). It starts each day as a muted dark gray — essentially "empty."

**Color sources:**
- Each Habit has an assigned color (from the app's palette, user-selectable).
- Each Project inherits its linked Habit's color. Unlinked projects use the project's own color.
- Tasks inherit their project's color.

**The fill equation:**

The card's gradient is a weighted blend of all habit colors, where each habit's contribution is determined by:

```
habit_weight = (tasks_completed_today / total_active_tasks) × streak_multiplier
```

Where `streak_multiplier` is:
- Days 1–3: 1.0× (base)
- Days 4–7: 1.2× (warming up)
- Days 8–14: 1.5× (building momentum)
- Days 15–30: 1.8× (on fire)
- Days 31+: 2.0× (locked in)

This means habits you've been consistent with contribute MORE color to the card. A 30-day coding streak makes the coding color dominate. Miss a day? The multiplier drops back to 1.0× and the color contribution shrinks.

**Color decay on missed tasks:**
- If tasks in a habit group go incomplete, that habit's color contribution fades by 20% per missed day.
- If ALL habits are missed for a day, the card dims overall (lower saturation, not removal — the card should look "tired," not punishing).
- The card never goes fully dark once you've started. A faint ghost of yesterday's colors remains, so there's always something to build on. Shame kills ADHD apps — the card should whisper "pick up where you left off," not scream "you failed."

**Visual behavior:**
- Colors blend as a soft gradient, not hard segments. Two active habits = a two-tone gradient. Five = a rich, unique blend.
- Over weeks, your card becomes visually unique to you — a fingerprint of your habits.
- The 30-day heatmap (streaks panel) uses these same colors per-square instead of a single accent color, making the heatmap itself a mosaic of your habit activity.

### Data Model Addition

**Daily Color Snapshot** (new entity):

Fields: date (date-only, primary key), habit color weights (dictionary: habit ID → computed weight), overall saturation (float 0.0–1.0).

Computed at end of day (during day rollover) and stored so historical cards can be reconstructed for the heatmap.

-----

## 2. Subtask Breakdown (Inline Chunking)

When creating or viewing a task, the user can break it into steps without leaving the flow.

### Interaction Design

**On the task creation input (quick-add bar):**
- User types a task name and presses return → task is created (current behavior).
- NEW: After pressing return, a brief toast/prompt appears: "Break it down? ↵" — tapping it (or pressing return again while input is empty) enters **breakdown mode**.
- In breakdown mode, the input placeholder changes to "Step 1…" and each return adds a subtask (step) to the parent task. Steps are numbered automatically.
- Pressing return on an empty line, or tapping "Done," exits breakdown mode.
- This is entirely optional. Most tasks won't need it. But "Write final paper" absolutely does.

**On existing tasks (via the expand action row):**
- Add a "Steps" icon (≡ or ⊞) to the inline action row that appears when tapping a task.
- Tapping it reveals an inline list of steps below the task. Each step has:
  - A small checkbox (tap to complete).
  - The step text.
  - A delete button (✕).
- An "+ Add step" input at the bottom.
- Steps are ordered by creation. No drag-reorder (keep it simple for v1).

**Visual on the task row:**
- If a task has steps, show a small progress indicator next to the task text: "2/5" in muted text, or a thin mini progress bar.
- Completed steps show strikethrough.

### Data Model Addition

**Task Step** (new entity):

Fields: unique ID, text (string), done (boolean), sort order (integer), task ID (foreign key), creation date.

Cascade delete: deleting a Task deletes all its Steps.

**Task completion behavior with steps:**
- A task with steps is NOT auto-completed when all steps are done. The user still checks the parent task's checkbox. This prevents accidental completion and gives an intentional "I'm done" moment (dopamine hit).
- However, if all steps are complete, the parent task's checkbox could pulse or glow subtly to say "ready to check off."

-----

## 3. Focus 3

A "what to do right now" section at the top of the Today view, below the color card.

### Behavior

- Shows up to 3 tasks, selected by the user via a "pin" action.
- The pin action is added to the task's inline action row (📌 icon). Tapping it adds the task to Focus 3. Tapping again removes it.
- If more than 3 tasks are pinned, the oldest pin is bumped (FIFO). Or: block pinning beyond 3 with a brief "Unpin one first" message.
- Focus 3 tasks appear as larger, more prominent cards compared to the regular task feed below. Each card shows:
  - The task text (larger font).
  - Its project color indicator (left border stripe).
  - Step progress if applicable (e.g., "2/5 steps").
  - A checkbox to complete.
- When all 3 are completed, the Focus 3 section shows a brief congratulatory message ("All 3 done 🎯") and collapses. The user can pin 3 more, or just work from the regular feed.

### Auto-suggestion (v1.5 / stretch goal)

If the user hasn't pinned anything by a configurable time (e.g., 9 AM), the app could auto-suggest 3 tasks based on: highest star rating → longest-active recurring tasks → oldest incomplete tasks. The user can accept or dismiss.

-----

## 4. Reward & Haptics System

### Haptic Vocabulary

Standardize haptic patterns so they become *meaningful* — the user learns what each vibration means without looking at the screen.

| Action | Haptic | Rationale |
|---|---|---|
| Toggle habit complete | Medium impact | Satisfying "stamp" feel |
| Check off a task | Light impact + 50ms delay + light impact | Double-tap feel = "done done" |
| Complete all Focus 3 | Heavy impact (single) | Achievement moment |
| Pomodoro session complete | Three light impacts in quick succession | Celebration pattern |
| Add a new task | Soft impact | Confirmation, not celebration |
| Streak milestone (7d, 14d, 30d) | Success notification haptic | iOS's built-in "success" pattern |
| Delete something | Rigid impact | Intentional, slightly jarring |

### Points System (Lightweight)

Not XP-and-levels gamification (that's a different app). Instead, a simple daily score that feeds the color card saturation.

**Point sources:**
- Complete a task: +1 point
- Complete a recurring task: +2 points (they're harder because they're every day)
- Complete a habit: +3 points
- Complete a Focus 3 task: +1 bonus point (on top of the task point)
- Complete a pomodoro session: +2 points
- Complete a time block: +1 point
- Complete ALL habits in a day: +5 bonus
- Complete ALL Focus 3: +3 bonus

**What points do:**
- They feed the color card saturation. More points = more vivid/saturated card colors. Zero points = muted grays.
- They're displayed as a small daily counter on the Today header: "✦ 14" — nothing flashy.
- Weekly total appears in the Log view's weekly breakdown.
- They do NOT persist as a lifetime score (avoid anxiety about maintaining a number). They reset daily. The color card captures the *feeling* of accumulation without the pressure of a permanent counter.

### Achievement System (Scope-Managed)

Achievements are pre-defined milestones. They unlock a badge and a one-time haptic celebration. They live in the Log view under a new "Achievements" section.

**v1 achievements (keep it to ~10, add more over time):**

1. **First Step** — Complete your first task.
2. **On a Roll** — Complete 3 tasks in one day.
3. **Five Alive** — Complete 5 tasks in one day.
4. **Week Warrior** — Complete at least 1 task every day for 7 days.
5. **Deep Work** — Complete 4 pomodoro sessions in one day (100 minutes of focus).
6. **Marathon** — Accumulate 24 hours of pomodoro time (lifetime).
7. **Creature of Habit** — Maintain a 14-day streak on any habit.
8. **Full House** — Complete all habits in a single day.
9. **Color Burst** — Have 5+ active habits contributing color to your card.
10. **Architect** — Create 5 projects.

**Visual:** Each achievement is a small card showing an icon, the achievement name, a one-line description, and either a locked state (grayed, dashed border) or unlocked state (color, date earned). Unlocked achievements could use the habit color of the most relevant habit.

**Important:** Achievements should feel like surprises, not obligations. No "you're 80% of the way to X" progress bars. They either happened or they didn't. This avoids the anxiety of "almost there" that derails ADHD brains.

### Data Model Addition

**Achievement** (new entity):

Fields: achievement key (string enum), unlocked (boolean), unlock date (nullable).

Checked during day rollover and after relevant actions (task completion, pomodoro end, etc.).

-----

## 5. Placement & Layout Revisions

### Quick-Add Bar → Bottom

Move the quick-add bar from the top of the scroll area to a fixed position at the bottom, just above the tab bar. This is the most-used interaction in the app — it must be in the thumb zone.

**Layout:** A floating bar with rounded corners, slight elevation (shadow or border), containing:
- The text input (fills most of the width).
- The project picker (compact, to the left or as a leading icon that opens a small menu).
- The draft toggle (small pill, to the right of the input or below).

When the keyboard opens, the bar rises with it (standard iOS behavior). When typing, the task feed scrolls so the user can see recently added tasks above the input.

### Streaks Panel Trigger → Bottom-Accessible

Replace the top-right 🔥 button with one of:
- A swipe-down gesture on the color card (pull down = reveal streaks).
- A tap on the color card itself (tap = expand to show streaks + heatmap below it).
- A long-press on the date header.

The panel itself can still slide in from the top, but the trigger must be reachable.

### Today View Revised Layout (Top to Bottom)

1. **Date label** — "TUE, JUN 3" (small, top-left).
2. **Color card** — The dynamic gradient card. Shows daily points counter (✦ 14) in the corner. Tap to expand streaks panel.
3. **Focus 3** — Up to 3 pinned task cards. Collapsible when empty or all complete.
4. **Habits row** — Horizontal scroll of habit pills (unchanged, but with per-habit colors).
5. **Task feed** — Grouped by habit, sorted as specified. Each group header uses its habit's color as a left border accent.
6. **Quick-add bar** — Fixed at bottom, above tab bar.

### "Now" Line in Blocks View

Add a horizontal red line at the current time position on the hourly timeline. The line spans the full width, with a small circle on the left edge and the current time as a label (e.g., "2:34p"). This line should update in real-time (every minute). If the current time is outside the 6AM–10PM range, the line doesn't show.

-----

## 6. Color & Theming Philosophy

### The "Slightly Dull, Then Alive" Principle

The base UI is intentionally muted — near-black backgrounds, dark gray surfaces, muted text. This is the canvas. Color comes from YOUR data:

- Habit pills glow with their assigned colors when completed.
- Project groups in the task feed have colored left-border accents.
- The color card fills with YOUR habit colors based on YOUR activity.
- Completed tasks get a brief color flash (the project color) before fading to a muted "done" state.
- The heatmap squares use YOUR habit colors, not a generic green.

**The result:** A new user sees a clean, minimal, monochrome app. A user who's been active for 2 weeks sees an app that's rich with *their* colors. The app literally becomes more colorful as you use it. This is the reward — not points, not badges, but the app itself coming alive.

### User-Selectable Accent Colors

Each habit gets a color from a curated palette (8–12 options). Each project can inherit its linked habit's color or pick its own. The accent color for the app chrome (tab bar highlights, buttons) defaults to indigo (#635BFF) but could be user-selectable in a future settings screen.

**Palette suggestion (dark-mode optimized, distinct from each other):**

| Name | Hex | Use |
|---|---|---|
| Indigo | #635BFF | Default accent, services |
| Coral | #FF6B6B | Health, wellness |
| Amber | #F59E0B | Learning, study |
| Emerald | #10B981 | Exercise, outdoors |
| Sky | #38BDF8 | Creative, writing |
| Violet | #A78BFA | Mindfulness, rest |
| Rose | #FB7185 | Social, relationships |
| Teal | #2DD4BF | Finance, career |
| Orange | #FB923C | Side projects |
| Slate | #94A3B8 | Chores, maintenance |

-----

## 7. Organizational Intelligence

The app must organize FOR the user, not ask the user to organize. Key behaviors:

### Auto-Sorting That Actually Helps

The current spec sorts by stars → creation date. Add these intelligent layers:

- **Overdue recurring tasks surface first.** If a recurring task hasn't been completed today and it's past noon, bump it above other tasks in its group.
- **Stale tasks get flagged.** If a non-recurring task has been incomplete for 7+ days, show a subtle indicator (⚠️ or a dimmed clock icon). After 14 days, show a gentle prompt: "Still relevant?" with options to keep, draft, or delete. This prevents the graveyard of abandoned tasks that makes ADHD users give up on the app entirely.
- **Recently completed tasks briefly show a "done" state** at the top of their group (for 30 seconds, with a fade) before disappearing. This gives the user visual confirmation and a micro-reward before the task vanishes from Today.

### Smart Defaults

- New tasks default to the project the user most recently added a task to (not always "first project").
- If a user creates 3+ tasks in rapid succession (within 60 seconds), they're probably brain-dumping. Show a brief, non-intrusive label: "Brain dump mode 🧠" — it's validating, not functional, but it tells the user "the app gets you."
- When a project has 0 incomplete tasks, collapse it automatically in the Focus view to reduce visual clutter.

### The "What Now?" Fallback

If the user opens the Today view and has:
- No Focus 3 pinned
- No habits completed
- No tasks in progress

Show a single, calming prompt instead of an empty state: **"Pick one thing."** Below it, show the random task button (🎲) and the top-starred incomplete task. Don't show the full task feed until after the first interaction. This prevents the "open app → see 47 tasks → close app" doom loop.

-----

## Build Priority for These Additions

**Phase 1 (build with v1 — low complexity, high impact):**
- Quick-add bar at bottom
- Haptic vocabulary (standardized patterns)
- Per-habit colors on pills and group headers
- "Now" line in Blocks view
- Focus 3 (pin system)
- Stale task flagging

**Phase 2 (build after core v1 is stable):**
- Color card system (gradient rendering, weight calculation)
- Subtask/steps breakdown
- Points system (daily counter)
- Smart defaults (recent project, brain dump detection)
- "What Now?" empty state

**Phase 3 (post-launch, based on usage):**
- Achievements system
- Color decay/streak multiplier tuning
- Auto-suggestion for Focus 3
- Historical color card heatmap
- User-selectable accent color
