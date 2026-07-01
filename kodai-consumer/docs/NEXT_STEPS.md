# Next Steps: Current Standing → Publish-Ready

Open-ended roadmap for taking kodai-consumer from its current dev state to a published App Store product. Each section is a standalone workstream — no fixed order, pick what matters most and ship it. Written so any agent (or human) can read the current code, read this doc, and start executing.

The app is a **private, offline, on-device iPhone agent** that automates tasks via natural language → tool calls → structured action cards. Not a chatbot. Not a cloud product. Everything runs locally via LFM 2.5 on llama.cpp.

---

## Current Standing (what's already built)

- **20 tools** across 7 domains (calendar, reminders, contacts, files, clipboard, notifications, system) — all routers implemented
- **Agent loop** — multi-step infer → parse → validate → execute → feed result back (up to 6 steps), with retry on invalid calls
- **3-tab UI** — Feed (action card stream + input bar), Upcoming (grouped timeline from EventKit + agent cards), Archive (session-grouped history with filters)
- **SwiftData persistence** — ActionCard, SessionGroup, ActionStore with CRUD + pruning
- **Onboarding** — splash → permissions → ready, with per-domain permission cards
- **Settings** — permission status, agent context (default calendar/list/timezone), version
- **App Intents** — 10 Siri/Shortcuts/Spotlight shortcuts covering major tools
- **Widget** — input-only WidgetKit widget that deep-links into the app
- **Haptics** — domain-specific feedback at all interaction points
- **Confirm flow** — write actions show confirmation card, reads skip it
- **Test suite** — ~1600 lines: parser, validator, agent loop, dispatch, ActionStore tests
- **Branding** — wolf constellation splash, pawprint icon, "kodai" identity, dark-mode-only

---

## Workstream 1: Wire the Real Agent Loop

**Status**: `AgentLoop.swift` exists as a clean multi-step loop, but `AssistantController` runs its own single-turn flow (infer → parse → validate → execute → done). The controller doesn't chain tool calls in practice.

**Goal**: The model should be able to chain 2–6 tool calls in a single task ("check my calendar for tomorrow, then set a reminder for 8am, then schedule a notification 30 min before").

### Tasks

1. **Replace the inline loop in `AssistantController.run()`** with a call to `AgentLoop.run(task:)`. The controller currently duplicates parse/validate/execute logic — it should delegate to `AgentLoop` and only handle UI concerns (phase updates, card logging, confirmation).

2. **Bridge confirmation into `AgentLoop`**: The agent loop's `ToolRouter` protocol needs to support the async confirmation flow. The `ToolRouterDispatch` already takes a `confirm` closure — wire that through so `AgentLoop` can pause mid-chain for user confirmation on write actions.

3. **Progressive card logging**: Each step in the chain should log an `ActionCard` to the feed as it completes, not all at once at the end. The user should see cards appearing in real-time as the agent works through a multi-step task.

4. **Streaming thinking text**: While the model is generating, show the raw token stream in the feed (like the current `thinking` string), then replace it with the action card when the step completes.

5. **Cancel mid-chain**: If the user cancels while the agent is mid-chain (e.g., after step 2 of 4), the completed steps should remain in the feed. Only the in-progress and pending steps should be cancelled.

6. **Test**: Write an integration test that mocks the model to emit 3 chained tool calls and verify all 3 cards appear in the store.

### Files
- `kodai-consumer/UI/AssistantController.swift` — major refactor
- `kodai-consumer/Agent/AgentLoop.swift` — minor: add hooks for per-step card logging
- `kodai-consumerTests/AgentLoopTests.swift` — add chained-with-confirmation test

---

## Workstream 2: Model Distribution

**Status**: `ConsumerModelFileResolver` exists but the actual model download/bundling pipeline isn't implemented. The model is assumed to be available.

**Goal**: First launch downloads the GGUF model (~700MB Q4_K_M) with progress UI, or the model is bundled in the app binary for TestFlight/review.

### Tasks

1. **Decide: bundle vs. download**. Bundling bloats the binary to ~800MB but guarantees offline-first from install. Downloading keeps the binary <50MB but requires a one-time network fetch. Recommendation: **bundle for TestFlight/review, download for production** — App Store reviewers need it to work immediately.

2. **If downloading**: Build a `ModelDownloadView` that shows progress (bytes/total, ETA, "downloading brain" messaging). Store the model in the app's `Application Support` directory. Use `URLSession` background download so it survives app backgrounding. Resume interrupted downloads. Verify SHA256 checksum on completion.

3. **If bundling**: Add the GGUF to the Xcode project as a resource. Update `ConsumerModelFileResolver` to find it in `Bundle.main`. Strip dSYMs to keep size manageable.

4. **Model version management**: Store a version identifier alongside the model file. When a new model version ships (via app update or download), migrate cleanly — don't lose the user's conversation context.

5. **Cold start optimization**: The README says 2–4s cold start on iPhone 14+. Profile on older supported devices (iPhone 12/13). If cold start exceeds 5s, add a model-loading interstitial with the wolf animation.

6. **Disk space guard**: Before downloading, check available disk space. If <2GB free, show a warning and don't proceed.

### Files
- `kodai-consumer/ConsumerModelFileResolver.swift` — implement resolution logic
- `kodai-consumer/UI/ModelDownloadView.swift` — new (if download path)
- `kodai-consumer/kodai_consumerApp.swift` — gate on model availability

---

## Workstream 3: Real-Device Performance

**Status**: No evidence of device profiling. The model runs via llama.cpp through KodaiRuntime.

**Goal**: The app runs smoothly on iPhone 12+ with no thermal throttling warnings, no OOM crashes, and <3s time-to-first-token.

### Tasks

1. **Memory budget**: Profile peak memory during inference on a real device. LFM 2.5 Q4_K_M at 1.2B params should sit around 800MB–1.2GB. iPhone 12 has 4GB RAM; iOS keeps ~1.5–2GB for apps. If inference + app exceed the budget, the system will kill the process. Measure and document the ceiling.

2. **Thermal throttling**: Run 10 consecutive tasks and monitor thermal state via `ProcessInfo.thermalState`. If the device hits `.serious` or `.critical`, pause inference and show "Your phone needs a moment to cool down." Don't let the app cause thermal warnings.

3. **Battery impact**: Profile energy usage during a typical 3-tool-call session. If the agent loop consumes >5% battery per session, consider reducing `n_threads` or adding a "low power mode" that uses fewer threads.

4. **Background behavior**: When the app is backgrounded mid-inference, the system may suspend the process. Handle this gracefully — either pause inference and resume on foreground, or let it complete in a `BGProcessingTask` if the user started a task via Siri/Shortcut.

5. **Watchdog tuning**: The current 45s timeout per turn may be too generous on slower devices. Make the timeout adaptive based on device model or observed inference speed.

6. **Instruments trace**: Run a full Instruments trace (Time Profiler + Allocations + Metal System Trace) during a representative task. Fix any main-thread blocking, unnecessary allocations, or GPU contention.

### Files
- `kodai-consumer/Agent/RuntimeAgentModel.swift` — threading knobs, thermal check
- `kodai-consumer/UI/AssistantController.swift` — background/foreground handling

---

## Workstream 4: App Store Submission Package

**Status**: No App Store metadata, screenshots, privacy policy, or review prep.

**Goal**: Complete submission package that passes Apple review on first attempt.

### Tasks

1. **App Store description**: Write the short description, promotional text, and keywords. Emphasize: private, offline, on-device AI, no account, no tracking, no cloud. Position as "what Siri should have been."

2. **Screenshots**: Generate 6.7" (iPhone 15 Pro Max) and 6.1" (iPhone 15 Pro) screenshot sets. Show:
   - Feed view with action cards (calendar event created, reminder set)
   - Upcoming view with grouped timeline
   - Confirm card for a write action
   - Onboarding privacy screen
   - Siri shortcut in action

3. **Privacy policy**: Write and host a privacy policy page. Contents: no data collected, no data shared, no analytics, no tracking, no network calls except user-initiated `web_fetch`. All processing on-device. Host on the CTXA site or a simple static page.

4. **App Review notes**: Write the review notes explaining:
   - The app uses an on-device ML model (LFM 2.5) for natural language understanding
   - No server-side AI — everything runs locally via llama.cpp
   - The model is [bundled/downloaded] — explain which
   - Tool calls require explicit user permissions (calendar, contacts, etc.)
   - Write actions require user confirmation before execution

5. **Age rating**: Likely 4+ (no objectionable content, no user-generated content shared, no purchases).

6. **App category**: Productivity.

7. **App icon**: The wolf constellation / pawprint identity needs to be rendered as a proper App Store icon (1024x1024 + all required sizes). Decide between the pawprint and the wolf constellation.

8. **Entitlements audit**: Verify all entitlements in `kodai_consumer.entitlements` are justified. Remove anything unused. Apple rejects apps with unnecessary entitlement requests.

### Files
- `kodai-consumer/Resources/` — icon assets
- `kodai-consumer/Info.plist` — usage descriptions for all frameworks
- New: privacy policy page (external)

---

## Workstream 5: Multi-Step Intelligence

**Status**: The model can chain tool calls, but there's no planning layer — it emits one tool call at a time and sees the result before deciding the next step. The system prompt says "state your plan first in one sentence, then execute" but there's no enforcement.

**Goal**: The agent handles compound requests reliably ("set up my morning routine: alarm at 6, gym reminder at 7, meeting prep at 8:30").

### Tasks

1. **Plan-then-execute**: When the model detects a multi-step task, it should emit a brief plan (logged as an `AgentNoteView` in the feed) before executing. This gives the user visibility into what's about to happen and a chance to course-correct.

2. **State anchor improvements**: `StateAnchor` currently tracks `stepsCompleted` as strings. Enhance it to carry:
   - The original plan (if emitted)
   - Success/failure status of each prior step
   - IDs of created resources (event IDs, reminder IDs) so later steps can reference them

3. **Cross-tool references**: The model should be able to reference results from prior steps. Example: "list my events for tomorrow" → result includes event ID → "delete the 3pm meeting" → uses the event ID from step 1. The current `ToolResult.asContextJSON()` already includes fields — verify the model actually uses them.

4. **Prompt engineering for chaining**: Test and tune the system prompt for multi-step reliability. The 1.2B model may struggle with 4+ step chains. Establish the practical chain-length ceiling and document it. If the model degrades past 3 steps, consider summarizing intermediate context.

5. **Parallel tool calls**: Some steps are independent (e.g., create 3 reminders). The model currently emits them sequentially. For v1, sequential is fine. Note for future: a planning layer could detect independent steps and execute in parallel.

6. **Eval harness**: Use the existing Bench Lab infrastructure to run a suite of multi-step scenarios and measure success rate. Target: >90% accuracy on 2-step tasks, >80% on 3-step.

### Files
- `kodai-consumer/Agent/StateAnchor.swift` — richer state
- `kodai-consumer/Assistant/SystemPromptBuilder.swift` — prompt tuning
- `docs/AGENT_PROMPT.md` — updated prompt

---

## Workstream 6: Accessibility & Inclusive Design

**Status**: Some VoiceOver labels exist (onboarding cards), but no systematic audit.

**Goal**: Full VoiceOver support, Dynamic Type, and reduced-motion compliance.

### Tasks

1. **VoiceOver audit**: Every interactive element needs an `accessibilityLabel` and `accessibilityHint`. Priority:
   - Input bar (text field, send button, stop button)
   - Action cards (summary, status chip, expand/collapse)
   - Confirm card (tool details, confirm/cancel buttons)
   - Tab bar items
   - Settings rows

2. **Dynamic Type**: Test all views at the largest accessibility text sizes (AX1–AX5). The action card layout may need to stack vertically at large sizes. The input bar should grow to accommodate larger text.

3. **Reduced motion**: Respect `UIAccessibility.isReduceMotionEnabled`. Disable the thinking dots animation, card appear animation, and wolf constellation animation. Replace with static equivalents.

4. **VoiceOver rotor actions**: Add custom rotor actions on action cards: "View details", "Ask agent to modify" (for upcoming items).

5. **Haptics**: Already present — these are a plus for VoiceOver users. Ensure they're semantically correct (success for completion, error for failure).

### Files
- All UI files in `kodai-consumer/UI/`

---

## Workstream 7: Error Handling & Edge Cases

**Status**: Basic error handling exists (timeout, validation failure, permission denied), but no comprehensive edge-case coverage.

**Goal**: The app never crashes, never shows a blank screen, and always communicates what went wrong.

### Tasks

1. **Model load failure**: If the model file is corrupted, missing, or incompatible, show a recovery screen ("Something went wrong with the AI model. Tap to re-download."). Don't crash.

2. **Inference OOM**: If llama.cpp runs out of memory mid-inference, catch the signal (if possible) or detect the crash on next launch and offer a lower-quality model option.

3. **SwiftData migration**: When the schema changes between versions, write a proper migration plan. Don't rely on lightweight migration for anything beyond adding optional fields. Test upgrade from v1 → v2 schema.

4. **Network failures** (for `web_fetch`): Timeout after 10s. Show the URL that failed and suggest the user check their connection. Don't retry automatically — the user might be intentionally offline.

5. **Permission revocation**: If a user grants calendar access during onboarding but later revokes it in Settings, the tool router returns a structured error. Verify the agent explains this clearly and suggests how to re-enable.

6. **Empty states**: All three tabs have empty states, but verify they look correct and offer useful guidance:
   - Feed: "What would you like to do?" (current — good)
   - Upcoming: "Nothing coming up." (current — could add "Try: 'remind me to call Mom tomorrow'")
   - Archive: "No history yet." (current — fine)

7. **Keyboard avoidance**: Verify the input bar moves up when the keyboard appears and the feed scrolls to keep the latest card visible. Test with hardware keyboards (bluetooth) and software keyboard.

8. **Orientation lock**: The app should be portrait-only on iPhone. Verify the `Info.plist` restricts orientations.

### Files
- `kodai-consumer/UI/AssistantController.swift` — error recovery
- `kodai-consumer/kodai_consumerApp.swift` — launch-time health checks
- `kodai-consumer/Info.plist` — orientation lock

---

## Workstream 8: TestFlight & Beta

**Status**: No TestFlight distribution yet.

**Goal**: Get the app into real users' hands for feedback before App Store submission.

### Tasks

1. **TestFlight build**: Create a distribution provisioning profile, archive the app, and upload to App Store Connect. Include the bundled model so testers don't need to download anything.

2. **Beta test group**: Start with 5–10 testers. Include a mix of:
   - Power users (will stress-test multi-step chains)
   - Non-technical users (will find UX friction)
   - Accessibility users (VoiceOver testers)

3. **Feedback mechanism**: Add a simple "Send Feedback" button in Settings that opens a pre-filled email compose sheet (to a feedback address). Include device model, iOS version, and app version in the email body.

4. **Crash reporting**: Since the app is fully offline, use Apple's built-in crash reporting (available via App Store Connect / Xcode Organizer). No third-party crash reporting needed (would violate the no-tracking promise).

5. **Analytics**: None. Zero. The app's identity is "no tracking." Don't add any analytics, even privacy-preserving ones. User feedback and crash reports are sufficient.

6. **Known issues doc**: Before each TestFlight build, write a brief "known issues" note so testers don't report things you already know about.

### Files
- `kodai-consumer/UI/SettingsView.swift` — add feedback button
- Xcode project settings — signing, provisioning

---

## Workstream 9: UI Polish & Delight

**Status**: Functional UI, dark-mode-only, basic card layout. No animation polish, no micro-interactions beyond haptics.

**Goal**: The app feels premium, fast, and intentional. Every interaction has weight.

### Tasks

1. **Card appear animation**: Action cards should slide up from the bottom with a spring animation when they appear in the feed. Not a fade — a physical entrance.

2. **Confirm card transition**: The confirmation sheet should feel like a card rising from the feed, not a generic sheet. Consider a custom transition that scales the card up from its position in the feed.

3. **Thinking state**: Replace `ThinkingDotsView` with something more expressive — a subtle pulsing glow around the input bar, or a minimal progress indicator that shows the model is generating tokens.

4. **Success celebration**: When a multi-step task completes successfully, play a subtle completion animation (quick checkmark, brief particle burst, or just a satisfying haptic pattern).

5. **Empty state illustrations**: Replace the SF Symbol + text empty states with custom illustrations that match the wolf/constellation brand. Keep them minimal and monochromatic.

6. **Tab bar**: The current tab bar is stock. Consider a custom tab bar that's more integrated with the dark theme — maybe a floating pill-style bar with the wolf pawprint as the center action button.

7. **Scroll behavior**: When the user scrolls up in the feed, the input bar should slide down (out of view) to give more reading space. Scrolling down or tapping the input area brings it back.

8. **Card expansion**: Expanded cards should animate smoothly. Consider a matched geometry effect between the compact and expanded states.

9. **Color system**: Define a formal color palette beyond the domain icon colors. The app should have a consistent accent color, surface colors, and text hierarchy that works across all views.

10. **Typography**: Define a type scale. Currently using system fonts — that's fine, but be intentional about which weights and sizes are used where.

### Files
- All UI files in `kodai-consumer/UI/`
- New: `kodai-consumer/UI/ConsumerPalette.swift` (if not already exists — formalize colors)

---

## Workstream 10: Expanded Tool Surface (Post-Launch)

**Status**: 20 tools across 7 domains. This is a solid v1 surface.

**Goal**: Expand the agent's capabilities based on what users actually try to do.

### Candidate tools (prioritized by iOS sandbox feasibility + user value)

1. **Photos** (`PhotoKit`):
   - `photos_search` — search by date, location, or album name
   - `photos_save` — save an image to a specific album
   - Read + add only, no delete (PhotoKit limitation for third-party apps)
   - High user value: "save this screenshot to my Work album"

2. **Health** (`HealthKit`):
   - `health_read` — read steps, heart rate, sleep data for a date range
   - `health_log` — log water intake, weight, mood
   - Requires separate entitlement and careful privacy handling
   - Medium user value, high trust requirement

3. **Maps / Location**:
   - `maps_search` — search for places nearby
   - `maps_directions` — get directions (opens Maps app)
   - Uses `MapKit` for search, `open_url` with `maps://` for navigation
   - Already partially possible via `open_url`

4. **Music** (`MusicKit`):
   - `music_play` — play a song, album, or playlist
   - `music_search` — search Apple Music catalog
   - Requires Apple Music subscription for full functionality

5. **Shortcuts integration**:
   - `run_shortcut` — trigger an existing Shortcut by name
   - Massively expands capability by piggybacking on the user's existing automations
   - Uses `ShortcutsLink` or URL scheme

6. **Share sheet**:
   - `share` — present the iOS share sheet with content (text, URL, image)
   - Enables iMessage pre-fill, email pre-fill, AirDrop, etc.
   - Workaround for the "can't send messages silently" limitation

7. **Alarms / Timers**:
   - Cannot be set programmatically on iOS (no API)
   - Can open Clock app via `clock-alarm://` deep link
   - Document as a hard limit

### Process
- Add tools one domain at a time
- Each new domain gets: router, validator cases, system prompt update, App Intent, tests
- Don't expand the surface faster than you can test it — a broken tool is worse than no tool

---

## Workstream 11: Agent Context & User Memory

**Status**: The agent has no memory between sessions. Each task starts from scratch. The system prompt includes datetime context but no user preferences.

**Goal**: The agent learns the user's patterns and preferences over time, entirely on-device.

### Tasks

1. **User context store**: A lightweight key-value store (UserDefaults or a SwiftData model) that persists:
   - Preferred calendar name (if not the default)
   - Preferred reminder list
   - Timezone (already confirmed on first use — persist it)
   - Common contacts (names the user references often)
   - Frequently used file paths
   - Any explicit preferences the user states ("I work 9-5", "my gym is Planet Fitness")

2. **Context injection**: `SystemPromptBuilder` should append the user context to the system prompt. Keep it concise — the 1.2B model has a limited context window. Format as a `[USER CONTEXT]` block with key-value pairs.

3. **Implicit learning**: After each successful task, extract and store relevant preferences. Example: if the user creates events on "Work" calendar 90% of the time, set that as the default. Do this with simple heuristics, not ML — the 1.2B model can't do reliable preference extraction.

4. **Explicit preferences**: If the user says "always use my Work calendar" or "my morning starts at 6am", store that directly. The agent should acknowledge: "Got it — I'll use your Work calendar by default."

5. **Privacy**: All context stays on-device. Show the full context store in Settings so the user can see and edit what the agent knows. Add a "Reset all context" button.

6. **Context size budget**: The model's context window is limited. Cap the user context block at 200 tokens. Prioritize recent and frequent preferences.

### Files
- New: `kodai-consumer/Agent/UserContextStore.swift`
- `kodai-consumer/Assistant/SystemPromptBuilder.swift` — inject context
- `kodai-consumer/UI/SettingsView.swift` — show/edit context

---

## Workstream 12: Widget Expansion

**Status**: Input-only widget that deep-links into the app.

**Goal**: Widgets that show upcoming items and let users take quick actions without opening the app.

### Tasks

1. **Upcoming widget**: A medium-sized widget showing the next 3 upcoming events/reminders. Tapping an item opens the app to the Upcoming tab. Uses `WidgetKit` timeline provider to refresh every 15 minutes.

2. **Quick action widget**: A small widget with 3–4 quick action buttons (e.g., "Add reminder", "Check calendar", "New note"). Each button deep-links into the app with a pre-filled query.

3. **Last action widget**: A small widget showing the most recent action card (what the agent last did). Tap to open the feed.

4. **Lock Screen widgets**: iOS 16+ lock screen widgets. Show the next upcoming event or a quick-action button.

5. **Live Activity** (stretch): When the agent is executing a multi-step task, show a Live Activity on the lock screen with progress ("Step 2 of 4: Setting reminder…"). This is high-impact but requires careful implementation.

### Files
- `kodai-consumer-widget/` — expand existing widget target
- New timeline providers and widget views

---

## Workstream 13: Test Coverage Hardening

**Status**: ~1600 lines of tests covering parser, validator, agent loop, dispatch, and ActionStore.

**Goal**: >90% coverage on core logic (agent loop, routers, store). UI tests for the critical path.

### Tasks

1. **Router unit tests**: Each of the 7 routers needs tests with mock framework objects. Currently only dispatch tests exist — add per-router tests that verify correct framework API calls.

2. **Agent loop edge cases**:
   - Model emits no tool call and no text (empty response)
   - Model emits a tool call for a tool that doesn't exist
   - Model emits valid JSON that's not a tool call
   - Step budget exceeded on step 6 — verify graceful degradation
   - Cancellation mid-inference

3. **ActionStore stress test**: Create 1000 sessions with 5 cards each, verify pruning works correctly. Test concurrent access from main thread + background task.

4. **UI tests**: Write 3 critical-path Xcode UI tests:
   - Type a request → see action card appear → verify feed state
   - Navigate to Upcoming → verify items present
   - Navigate to Archive → verify session grouping

5. **Snapshot tests**: Consider adding snapshot tests for key views (ActionCardView, ConfirmCardView, OnboardingView) to catch visual regressions. Use a lightweight snapshot testing library or roll your own with `ImageRenderer`.

6. **CI pipeline**: Set up a basic CI that runs `xcodebuild build test` on every push. Use GitHub Actions with a macOS runner. Tests should pass before any merge.

### Files
- `kodai-consumerTests/` — all test files
- New: `.github/workflows/ci.yml` (if using GitHub Actions)

---

## Workstream 14: Prompt & Model Quality

**Status**: System prompt is well-structured. Using LFM 2.5 1.2B Q4_K_M. No eval suite for the specific tool-calling domain.

**Goal**: The model reliably produces correct tool calls for the 20-tool surface, with <5% error rate on common requests.

### Tasks

1. **Eval dataset**: Create a dataset of 100+ (input, expected_tool_call) pairs covering:
   - All 20 tools (at least 5 examples each)
   - Ambiguous requests that should clarify
   - Requests outside the tool surface (should respond with capabilities message)
   - Multi-step requests (2–3 steps)
   - Edge cases: no date specified, relative dates ("tomorrow"), partial info

2. **Run evals**: Use the Bench Lab infrastructure to run the eval dataset against the model. Measure:
   - Tool name accuracy (did it pick the right tool?)
   - Parameter accuracy (did it fill parameters correctly?)
   - Date parsing accuracy (ISO 8601 compliance)
   - Chain completion rate (for multi-step)

3. **Prompt iteration**: Based on eval results, iterate on the system prompt. Common fixes:
   - Add more examples of correct tool calls
   - Clarify parameter formats (especially dates)
   - Add negative examples ("do NOT use calendar_create_event for reminders")
   - Tune the "prefer action over clarification" instruction

4. **Model alternatives**: If LFM 2.5 1.2B doesn't meet the accuracy bar, evaluate:
   - LFM 2.5 at a higher quantization (Q5_K_M, Q6_K — larger but more accurate)
   - Phi-3.5 Mini (3.8B) at Q4_K_M — significantly larger but dramatically better at tool calling
   - Qwen 2.5 1.5B — similar size to LFM, potentially better at structured output
   - Trade-off: accuracy vs. memory vs. cold start time

5. **Fallback behavior**: When the model produces garbage (happens with 1.2B models), the app should never show raw model output to the user. The current `ToolCallParser` falls back through native → JSON → Pythonic formats. Add a final fallback: if nothing parses, show "I didn't understand that — try rephrasing."

### Files
- `docs/prompts/` — eval datasets
- `kodai-consumer/Assistant/SystemPromptBuilder.swift` — prompt updates
- `docs/AGENT_PROMPT.md` — canonical prompt

---

## Priority Order (suggested, not prescribed)

For shipping v1.0 to the App Store:

1. **Model distribution** (Workstream 2) — can't ship without it
2. **Real-device performance** (Workstream 3) — can't ship if it crashes
3. **Error handling** (Workstream 7) — can't pass review if it crashes
4. **App Store package** (Workstream 4) — required for submission
5. **TestFlight** (Workstream 8) — get real feedback before review
6. **Accessibility** (Workstream 6) — Apple reviews for this
7. **UI polish** (Workstream 9) — makes the difference between 3-star and 5-star

For post-launch iteration:

8. **Wire real agent loop** (Workstream 1) — multi-step is the killer feature
9. **Prompt & model quality** (Workstream 14) — ongoing improvement
10. **Agent context & memory** (Workstream 11) — makes the agent feel personal
11. **Multi-step intelligence** (Workstream 5) — compound tasks
12. **Expanded tools** (Workstream 10) — user-requested capabilities
13. **Widget expansion** (Workstream 12) — surface area
14. **Test hardening** (Workstream 13) — ongoing

---

## Non-Goals

- Cloud sync, accounts, or any server-side component
- In-app purchases or subscriptions (v1 is free)
- iPad or Mac support (iPhone-only for v1)
- Custom model training or fine-tuning on-device
- Chat history export
- Third-party integrations (Slack, Notion, etc.) — the app is local-only
