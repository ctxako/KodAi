# Phase 5: Permissions + Onboarding

## Context

kodai-consumer is a private, offline iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. It runs on-device and accesses Calendar, Reminders, Contacts, Notifications, and Files via iOS frameworks. Phases 0-4 built the full tool system, data layer, and three-tab UI.

The current `OnboardingView.swift` (at `kodai-consumer/UI/OnboardingView.swift`) only requests Calendar and Reminders access. We now need to cover all domains and ensure the app works gracefully when any permission is denied.

## What to do

### 1. Update `OnboardingView.swift`

Rebuild the onboarding flow. It shows on first launch (gated by an `@AppStorage("hasCompletedOnboarding")` bool in `kodai_consumerApp.swift`).

**Layout:**

Page-style flow (use `TabView` with `.tabViewStyle(.page)` or a custom pager):

**Page 1 — Welcome**
- Wolf constellation icon (use existing `SplashView` aesthetic or a static wolf SF Symbol)
- "kodai" title
- "Your private AI agent. Everything runs on your phone. Nothing leaves."
- "Get Started" button → next page

**Page 2 — Permissions**
- Title: "Let kodai help you with..."
- Vertical list of permission cards, each with:
  - Domain icon (same colors as action cards)
  - Domain name
  - One-line explanation of what the agent can do with this access
  - Toggle or "Allow" button that triggers the system permission request
  - Status indicator: checkmark (granted), x (denied), or dash (not requested)

Permission cards:

| Domain | Icon | Explanation |
|---|---|---|
| Calendar | `calendar` / red | "Create events, check your schedule, manage appointments" |
| Reminders | `checklist` / blue | "Set reminders, manage to-do lists, mark tasks complete" |
| Contacts | `person.crop.circle` / green | "Search contacts, add new people" |
| Notifications | `bell.badge` / yellow | "Send you reminders and alerts at specific times" |

Files don't need upfront permission — access is per-use via the document picker. Clipboard doesn't need permission. Web fetch doesn't need permission.

- "Skip for now" link at the bottom — app works with zero permissions
- Each permission request uses the native iOS dialog (EventKit's `requestWriteOnlyAccessToEvents()`, `requestFullAccessToReminders()`, `CNContactStore().requestAccess(for:)`, `UNUserNotificationCenter.current().requestAuthorization(options:)`)

**Page 3 — Ready**
- "You're all set."
- "kodai works offline, on-device, with zero tracking."
- "Done" button → dismisses onboarding, sets `hasCompletedOnboarding = true`

### 2. Graceful degradation

Each tool router already returns structured errors when permissions are denied (e.g., `"calendar_access_denied"`). Verify this works for all domains:

- `EventKitToolRouter`: returns `"calendar_access_denied"` or `"reminders_access_denied"` — already implemented.
- `ContactsToolRouter`: should return `"contacts_access_denied"` when `CNContactStore` access is denied.
- `NotificationToolRouter`: should return `"notifications_access_denied"` when notification authorization is denied.
- `FileToolRouter`, `ClipboardToolRouter`, `SystemToolRouter`: no upfront permissions needed, but handle runtime errors gracefully.

The agent receives these errors as `ToolResult.failure(...)` and explains the issue to the user. The response should appear as an agent note card in the feed. Verify this flow works end-to-end: denied permission → tool error → agent note explaining how to fix it.

### 3. Settings sheet (optional, lightweight)

Add a settings/context sheet accessible from the Feed tab (gear icon in the nav bar or similar).

**Contents:**
- **Permissions section**: list each domain with current status (Granted / Denied / Not Requested). Each row links to iOS Settings for that domain (via `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`).
- **Agent context section**: shows what the agent knows:
  - Default calendar name (from `EKEventStore.defaultCalendarForNewEvents`)
  - Default reminder list name (from `EKEventStore.defaultCalendarForNewReminders()`)
  - Timezone (from `TimeZone.current`)
- **About section**: version, "All on-device, no tracking" tagline, link to privacy policy if any.

Present as a `.sheet` with `.presentationDetents([.large])`.

### 4. Permission re-request handling

If a user denies a permission during onboarding and later tries to use that tool:
1. The router returns the structured error
2. The agent explains: "I can't access your calendar — you can enable it in Settings > Privacy > Calendars"
3. The error card in the feed should be tappable to open iOS Settings (via the `openSettingsURLString`)

## Important

- Do NOT modify tool routers unless their error messages need updating. The routers should already handle denied permissions — just verify.
- Do NOT modify the data layer or agent loop.
- The onboarding flow should be skippable — every permission is optional.
- Dark mode only, same visual style as the rest of the app.
- Verify compile: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Do NOT boot or run simulators.
