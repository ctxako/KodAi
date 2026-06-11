# kodAi — Product Roadmap & Build Spec

**Platform:** iOS (SwiftUI, native)
**Persistence:** Local only (SwiftData)
**Architecture:** Single-app, four tabs, one shared data layer
**Design philosophy:** Zero friction. Every interaction is one tap. No modals unless destructive. No multi-step flows. The app gets out of your way.

-----

## Data Model

Before building any view, the shared data layer must be scaffolded. Everything below references these entities.

### Habit

A trackable daily behavior. Persists indefinitely. Completion resets daily.

Fields: unique ID, name (string), icon (emoji string), creation date, sort order.

### Habit Completion

A join record: one Habit completed on one date.

Fields: habit ID, date (date-only, no time), timestamp of completion.

### Project

A container for related tasks, linked to one Habit (optional). Projects live in the Focus tab and surface their tasks on Today.

Fields: unique ID, name, color (hex string), linked habit ID (nullable), creation date, sort order.

### Task

A to-do item that belongs to one Project.

Fields: unique ID, text (string), done (boolean), stars (integer 0–5, default 0), recurring (boolean, default false), draft (boolean, default false), project ID (foreign key), creation date, completion date (nullable).

Key behaviors:

- **Draft tasks** are saved but not “live.” They appear grayed out and do not count toward completion stats. A draft can be published (draft → false) with a single tap.
- **Recurring tasks** are never permanently “done.” Their completion is tracked per-day via a separate DailyTaskCompletion record. Each new day, they appear unchecked again. The task’s own “done” field stays false; daily status is read from DailyTaskCompletion.
- **Regular (non-recurring) tasks** disappear from the Today view after the day they were completed. They remain in their Project’s task list in the Focus tab with a completed state.
- **Star priority** ranges from 0 (no stars, default) to 5. Higher-starred tasks sort to the top within their group.

### Daily Task Completion

Tracks whether a recurring task was completed on a specific day.

Fields: task ID, date (date-only), timestamp.

### Time Block

A scheduled block of time on a specific day.

Fields: unique ID, label (string), date (date-only), start hour (integer 0–23), end hour (integer 0–23), color (hex string), done (boolean).

### Weekly Snapshot

Aggregated stats for one week (Monday–Sunday), computed and stored at end of each day.

Fields: week ID (Monday’s date as key), total habit slots (habits × days active that week), habits completed, total tasks in scope, tasks completed, total blocks, blocks completed, total pomodoro sessions.

### App Settings

Lightweight key-value for app-level state.

Fields: last active date (for detecting day rollover), lifetime pomodoro count.

-----

## Build Order

Build in this exact order. Each section is one unit of work. Do not skip ahead — later views depend on earlier data layer work.

1. Data layer (SwiftData models, persistence manager)
1. Tab shell (TabView with four tabs, empty placeholder views)
1. Today view
1. Focus view
1. Blocks view
1. Log view

-----

## 0. App Shell

A TabView with four tabs at the bottom. Standard iOS tab bar, no custom styling needed — keep it native.

Tabs:

- **Today** (sun icon) — the daily feed
- **Focus** (target/circle icon) — pomodoro + project workspace
- **Blocks** (grid icon) — weekly time-block calendar
- **Log** (chart icon) — stats and export

The app should detect day rollover on launch and on returning from background. When a new day is detected: recurring task daily completions from previous days are left as-is (historical), and the current day starts fresh (no completions). The pomodoro session count resets daily but is also accumulated into the weekly snapshot before resetting.

-----

## 1. Today View

The daily command center. A single scrollable feed showing everything relevant to today: habits, tasks grouped by habit, and a quick-add input. The goal is to open the app, see exactly what needs doing, and start checking things off.

### Layout (top to bottom)

**Header area:**

- Current date displayed as a small label (e.g., “TUE, JUN 3”).
- Screen title “Today” in large bold text.
- A small “🔥” button in the top-right corner that toggles the Streaks panel open/closed.

**Streaks panel (collapsed by default):**
When opened via the 🔥 button, this panel slides in below the header. It contains:

- A 30-day heatmap grid. Each square represents one day. Color intensity maps to the percentage of habits completed that day (0% = empty/dark, 50% = medium, 100% = full accent color). Tapping a square does nothing — it’s read-only.
- Below the heatmap, a list of each habit with its current streak count (consecutive days completed up to and including today). Format: “[icon] [name] — [count]d”.
- Tapping the 🔥 button again closes the panel.

**Quick-add bar (sticky at top of scroll area):**

- A single text input field. Placeholder text: “+ Add task…”
- To the left of or below the input, two controls:
  - A **Draft toggle**. This is a small pill/button that says “Live” by default. Tapping it switches to “Draft” state (visually distinct — muted color, label changes to “📝 Draft”). When in Draft mode, any task added via the input is created with draft=true. The toggle is per-add, not global — it resets to “Live” after adding.
  - A **Project picker**. A compact dropdown or segmented selector showing the user’s project names. The user picks which project the new task goes into. Defaults to the first project if not selected.
- Pressing return/enter on the keyboard adds the task and clears the input. The input stays focused for rapid entry.

**Habits row:**

- A horizontally scrollable row of pill-shaped buttons, one per habit.
- Each pill shows the habit’s icon and name (e.g., “⌨️ Code 1hr”).
- Tapping a pill toggles that habit’s completion for today. Completed habits show a checkmark and change to a “completed” visual state (green tint or border).
- At the end of the row, a “+” button that reveals an inline text input to create a new habit. Type a name, press return, habit is created. No separate screen.

**Task feed (grouped by habit):**
This is the main content area. Tasks are grouped under their parent habit’s icon and name. The grouping works as follows:

- Each Project has an optional linked Habit. All tasks from projects linked to Habit A appear under Habit A’s group.
- Projects with no linked habit, or linked to a habit that doesn’t exist, have their tasks grouped under a “📌 General” section.
- Each group header shows: the habit icon, the habit name, and a completion fraction (e.g., “3/7”).

Within each group, tasks are sorted:

1. Live tasks before draft tasks.
1. Within live tasks, higher star count first (5 → 4 → 3 → 2 → 1 → 0).
1. Within same star count, creation order.
1. Draft tasks appear at the bottom of the group, visually muted.

**Individual task row (live):**

- Left: a checkbox (rounded square). Tap to toggle completion. For recurring tasks, this toggles today’s DailyTaskCompletion, not the task’s permanent “done” field.
- Center: the task text. Below the text in a smaller font: the project name and star indicators (filled stars for the task’s rating, empty for the remainder — or no stars shown if rating is 0).
- If the task is recurring, a small “↻” badge appears next to the text.
- Tapping the task text (not the checkbox) expands an inline action row below the task. This row contains:
  - Star selector: five tappable stars. Tap a star to set that rating. Tap the same star to clear back to 0.
  - Recurring toggle (↻ icon): tap to toggle the task between recurring and one-time.
  - Draft toggle (📝 icon): tap to move this task back to draft status.
  - Delete button (✕): tap to delete the task. No confirmation — it’s just a task, not a project.
- Tapping the task text again collapses the action row.

**Individual task row (draft):**

- Visually muted (lower opacity, dashed border on checkbox area, italic text).
- Checkbox is replaced with a 📝 icon.
- Tapping the text expands actions: “Publish” button (sets draft=false, making it live) and “Delete” button.
- Drafts do not count toward group completion fractions.

**What shows on Today vs. what doesn’t:**

- All tasks from all projects appear here, grouped by habit. This is the unified daily view.
- Completed non-recurring tasks from previous days do NOT appear. Only today’s tasks and incomplete tasks carry over.
- Recurring tasks always appear (they reset daily).
- Draft tasks always appear (in their muted state at the bottom of their group).

-----

## 2. Focus View

The workspace. Pomodoro timer for focus sessions, projects with task lists for doing actual work, and a random task selector for when you don’t know where to start.

### Layout (top to bottom)

**Header area:**

- Small label “FOCUS” and large title “Pomodoro.”

**Pomodoro timer card:**
A prominent card at the top of the view. This timer is purely a focus aid — it does not log individual sessions to a detailed focus log. It just counts pomodoro sessions (25-minute work blocks completed).

Timer states:

- **Idle:** Shows “READY” label, the time “25:00” in large monospace text, and a “Start” button. Below the timer, a session count: “[N] sessions today.”
- **Working:** Shows “WORKING” label (in accent color), countdown from 25:00 in large text, a thin progress bar at the bottom of the card filling left-to-right as time elapses. One button: “Stop” (cancels without counting). When the timer hits 0:00: increment the daily pomodoro count by 1, play a short audio chime (two-tone beep via AudioToolbox or AVFoundation), send a local push notification (“Work done! 5 min break.”), and auto-transition to Break state.
- **Break:** Shows “BREAK” label (in green), countdown from 5:00, progress bar. Two buttons: “Skip break” (immediately starts a new 25:00 work phase) and “Done” (returns to idle). When the break timer hits 0:00: play a chime, send a notification (“Break over! Let’s go.”), return to idle state.

The timer must continue running when the app is backgrounded. Use background task or local notification scheduling so the chime/notification fires even if the app isn’t foregrounded.

On first “Start” tap, request notification permission if not yet granted.

**Task completion flow:**
When a user marks any task as done (in the projects section below), a temporary “completion card” appears between the timer and the projects list. This card shows:

- “✓ COMPLETED” header in green.
- The task text that was just completed.
- A text input with placeholder “Follow-up task…” and a “Skip” button.
- If the user types a follow-up and submits, a new task is created in the same project with the same star rating as the completed task, recurring=false, draft=false. This is the “task extension” feature — it keeps momentum by letting you chain tasks.
- Tapping “Skip” dismisses the card.
- The card auto-dismisses after 10 seconds if no action is taken.

**Random task button:**
A dashed-border button labeled “🎲 Random task.” Tapping it picks one random task from all projects where done=false and draft=false. The selected task appears in a small card below the button showing:

- The task text and its parent project name and color indicator.
- A “Done” button (marks it complete, triggers the completion flow above).
- A “↻” button (picks a different random task).
  If there are no undone tasks, the button does nothing (or shows a brief “All clear!” message).

**Projects list:**
Below the random task area, a list of all Projects. Each project is a collapsible card.

Collapsed state shows: a color dot, the project name, a count of undone non-draft tasks, and a chevron (›).

Expanded state shows:

- All tasks in the project, sorted by stars descending. Each task row has:
  - Checkbox (tap to toggle done; if toggled to done, triggers the completion card flow).
  - Task text (strikethrough if done).
  - Recurring badge (↻) if applicable.
  - Star indicators (read-only in this view — edit stars on Today).
  - Delete button (✕, small, muted).
- An “+ Add task” button at the bottom of the task list. Tapping it reveals an inline text input. Type and press return to add. Press escape or tap away to cancel.
- A “Delete project” button at the very bottom, in muted red text. Tapping it shows a confirmation alert (this is destructive — confirm is warranted). Deleting a project deletes all its tasks.

**Add project:**
Above the project list, a small “+” button next to the “PROJECTS” section header. Tapping it reveals an inline form:

- Text input for the project name.
- A picker/dropdown to optionally link the project to a habit (“Link to habit” with a list of existing habits, or “None”).
- “Add” and “Cancel” buttons.
  The project is created with a color auto-assigned from a rotating palette.

-----

## 3. Blocks View

A visual daily schedule. The core interaction is a vertical hourly timeline where you tap empty time slots to add blocks.

### Layout (top to bottom)

**Header area:**

- Small label “SCHEDULE” and large title “Blocks.”
- Navigation arrows in the top-right: a left arrow (‹), a center dot (•), and a right arrow (›). Left/right shift the viewed week backward/forward by one week. The dot returns to the current week and selects today.

**Week strip:**
A horizontal row of 7 day cells (Sunday–Saturday or Monday–Sunday, follow the device’s locale). Each cell shows:

- The day’s two-letter abbreviation (e.g., “MO”, “TU”).
- The day’s date number (e.g., “3”).
- If that day has any blocks, a small dot indicator below the date.
- The currently selected day is highlighted (filled background). Today’s date is accented even if not selected.
- Tapping a day selects it and the timeline below updates.

The week strip supports swipe gestures: swiping left shows the next week, swiping right shows the previous week (equivalent to the arrow buttons).

**Selected day label:**
Below the week strip, a text label showing the full selected date (e.g., “Tue, Jun 3”). If the selected day is today, append “Today” in accent color.

**Hourly timeline:**
A vertical list of hours from 6:00 AM to 10:00 PM (17 slots). Each hour slot is a row.

Empty slot layout:

- Left column (fixed width): the hour label in small monospace text (e.g., “6a”, “7a”, “12p”, “1p”).
- Right column (fills remaining width): empty space with a subtle bottom border separating hours.
- Tapping an empty slot activates “add mode” for that hour.

When an empty slot is tapped (add mode):

- An inline input appears at that hour’s position. It contains:
  - A text field with placeholder “Block at [time]…” (e.g., “Block at 9a…”).
  - A compact end-time picker (dropdown or scroll selector showing hours after the start hour).
  - A row of small color circles (6 colors). Tap to select.
  - “Add” and “✕” (cancel) buttons.
- Only one slot can be in add mode at a time. Tapping a different slot moves add mode there.
- Pressing return or tapping “Add” creates the block and exits add mode.

Occupied slot layout (when a block exists at that hour):

- The block renders as a colored card spanning from its start hour to its end hour. The height is proportional to duration (a 2-hour block is twice the height of a 1-hour block).
- Inside the card: the block label in bold, and the time range in smaller text (e.g., “9a – 11a”).
- Tapping the block toggles its “done” state. Done blocks reduce opacity and show a checkmark.
- A small “✕” button in the corner deletes the block (no confirmation needed).
- If a block spans multiple hours, those intermediate hour rows are consumed by the block’s visual — they don’t render separately.

-----

## 4. Log View

Analytics and export. Shows aggregate stats and weekly breakdowns so you can spot patterns. This is the only view that looks backward — everything else is present or future.

### Layout (top to bottom)

**Header area:**

- Small label “ANALYTICS” and large title “Log.”

**Stat cards:**
A 2×2 grid of four cards, each showing:

- An icon, a large number, and a label.
- Card 1: “◎” icon, daily pomodoro count, label “POMODOROS”.
- Card 2: “🔥” icon, best current streak across all habits (in days), label “BEST STREAK”.
- Card 3: “◧” icon, total unique days where at least one habit was completed or one block was created, label “DAYS TRACKED”.
- Card 4: “▦” icon, number of projects, label “PROJECTS”.

**Weekly breakdown section:**
A section header “WEEKLY BREAKDOWN.”

Below, a vertical list of week summary cards, one per week, sorted most recent first. Only weeks with at least one day of tracked data appear.

Each week card shows:

- The week’s date range as a header (e.g., “Mon, Jun 2 – Sun, Jun 8”).
- A row of stats: “Habits [X]%” (percentage of total habit slots completed that week), “Blocks [done]/[total]”, “Tasks [done]/[total]” (if any tasks existed that week).
- A mini bar chart: 7 thin vertical bars, one per day of the week (Mon–Sun). Each bar’s fill height represents that day’s habit completion rate (0% = empty, 100% = full). The day’s single-letter label sits below each bar (M, T, W, T, F, S, S). This lets you visually see which days of the week you tend to be productive vs. slack.

**Export button:**
A full-width button labeled “↓ Download Full Log.” Tapping it generates a plain-text (.txt) file and presents the iOS share sheet.

The export file format:

- Header block with app name and generation timestamp.
- Weekly sections (most recent first). Each week shows:
  - Week date range.
  - Aggregate stats (habit %, blocks, tasks).
  - Per-day breakdown: each day lists habit completions (which ones done/not), blocks (done/not with labels and times), and recurring task completions.
- Projects section: each project with its tasks listed (done/not, star count, recurring flag).
- Streaks section: each habit with its current streak count.
- Summary: lifetime pomodoro count, total days tracked.

**Reset button:**
A small, muted-red button at the bottom labeled “Reset All Data.” Tapping shows a confirmation alert (“Reset everything? This cannot be undone.”). Confirming deletes all data and restores the default state.

-----

## Cross-Cutting Concerns

### Day Rollover

When the app detects a new day (on launch or on foregrounding), it must:

- Reset the daily pomodoro counter (but first accumulate the previous day’s count into the weekly snapshot).
- Ensure recurring tasks show as incomplete for the new day (they read from DailyTaskCompletion, which won’t have entries for the new day yet).
- Non-recurring completed tasks from previous days should no longer appear on the Today view.

### Notifications

The app uses local notifications only. No server. Two notification types:

- Pomodoro work phase complete: fires when the 25-minute timer ends.
- Pomodoro break phase complete: fires when the 5-minute timer ends.
  These should fire even if the app is backgrounded, using scheduled local notifications.

### Haptics

Use light haptic feedback (UIImpactFeedbackGenerator) on:

- Toggling a habit completion.
- Checking off a task.
- Completing a pomodoro session.
- Adding a new task or block.
  Keep it subtle — one light tap, not a buzz.

### Animations

Keep animations minimal and fast (0.15–0.2s). Use SwiftUI’s built-in transitions:

- Streaks panel: slide down / slide up.
- Task action row expand: height reveal.
- Completion card: fade in, auto-fade out.
- Block add mode: fade in at the tapped slot.
  No spring animations, no bounces, no elaborate transitions. Speed and responsiveness matter more than visual flair.

### Color Palette

Dark theme only (for now). Approximate values — adjust to taste but keep the vibe:

- Background: near-black (#09090B range).
- Surface cards: very dark gray (#111114 range).
- Borders: dark gray (#252535 range).
- Primary text: off-white (#E4E4EE range).
- Secondary text: muted gray (#7C7C96 range).
- Accent: indigo/violet (#635BFF range).
- Success/done: green (#10B981 range).
- Warning/streaks: amber (#F59E0B range).
- Danger/delete: red (#EF4444 range).
- Star color: amber (same as warning).
- Draft state: muted steel (#3A3A50 range).

### Typography

Use the system font (San Francisco) at various weights. This is an iOS app — SF is the right choice for readability and native feel. Use monospace variant (SF Mono or system monospace) for timer displays and numeric counters.

### Data Integrity

- All IDs should be UUIDs.
- Dates stored as date-only (no time component) for habit completions, daily task completions, block dates, and weekly snapshot keys.
- Timestamps (with time) for creation dates, completion timestamps.
- Star ratings clamped to 0–5 at the model level.
- Cascade delete: deleting a Project deletes all its Tasks. Deleting a Habit deletes its completions but does NOT delete linked projects (they become unlinked, falling into “General” group).

-----

## What This Spec Does NOT Cover (Future)

- AI integration (nudges, auto-planning, pattern analysis).
- Onboarding flow.
- iCloud sync or multi-device.
- Widget (lock screen or home screen).
- Apple Watch companion.
- Light theme / theme switching.
- Settings screen.
- Task reordering via drag-and-drop.
- Notification customization (sounds, timing).
- Data import/export in structured formats (JSON, CSV).

These are all valid future additions. This spec covers the complete v1.