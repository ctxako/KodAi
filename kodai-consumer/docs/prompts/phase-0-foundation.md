# Phase 0: Foundation — Expand Tool Surface to 20 Tools

## Context

kodai-consumer is a private, offline, on-device iOS action agent at `/Users/ctxa/kodai/kodai-consumer`. It runs a 1.2B LFM2.5 model via llama.cpp (through KodaiCore at `../KodaiCore`) and executes tool calls against iOS frameworks. No cloud, no network.

The current v1 has 7 tools: `create_calendar_event`, `create_reminder`, `add_to_list`, `query_calendar`, `query_reminders`, `save_file`, `read_file`. We're expanding to 20 tools across 7 domains.

## What to do

Expand the tool type system to support all 20 tools. This is types, validation, and prompt generation only — no router implementations, no UI changes.

### The 20 tools

**Calendar** (EventKit):
- `calendar_create_event` — title (required), start_date ISO8601 (required), end_date ISO8601, location, notes, calendar_name, all_day bool
- `calendar_list_events` — start_date ISO8601 (required), end_date ISO8601 (required), calendar_name
- `calendar_delete_event` — event_id string (required)

**Reminders** (EventKit):
- `reminders_create` — title (required), due_date ISO8601, notes, list_name, priority ("none"|"low"|"medium"|"high")
- `reminders_list` — list_name, completed bool (default false)
- `reminders_complete` — reminder_id string (required)

**Contacts** (Contacts.framework):
- `contacts_search` — query string (required, searches name/phone/email)
- `contacts_create` — first_name (required), last_name, phone, email, company, notes

**Files** (FileManager + UIDocumentPicker):
- `files_list` — path string (required, "icloud/" prefix for iCloud Drive, "local/" for app sandbox)
- `files_read` — path string (required)
- `files_create` — path (required), content string (required)
- `files_delete` — path string (required)

**Clipboard** (UIPasteboard):
- `clipboard_read` — no parameters
- `clipboard_write` — content string (required)

**Notifications** (UserNotifications):
- `notification_schedule` — title (required), body (required), trigger_date ISO8601 (required), identifier string
- `notification_cancel` — identifier string (required)

**System** (URLSession + UIApplication):
- `web_fetch` — url string (required)
- `open_url` — url string (required)

### Files to modify

1. **`../KodaiCore/Sources/KodaiKernel/Assistant/ConsumerToolCall.swift`** (or wherever `AssistantToolName` and `AssistantToolCall` are defined — grep for `enum AssistantToolName` and `enum AssistantToolCall` in KodaiKernel):
   - Replace the existing tool name enum with all 20 names.
   - Replace the existing `AssistantToolCall` enum with cases for all 20 tools, each carrying typed parameters. Use the parameter types listed above (strings, optional strings, Date, optional Date, Bool).
   - Keep the `respond` tool (it's used for non-action responses).

2. **`kodai-consumer/Assistant/ToolCallValidator.swift`** — update validation to handle all 20 tool names and their required/optional parameters. Each tool's required parameters must be present; optional ones default to nil. Date parameters are parsed from ISO 8601 strings.

3. **`kodai-consumer/Assistant/SystemPromptBuilder.swift`** — update the `build()` method to inject the new agent system prompt. The full prompt is in `docs/AGENT_PROMPT.md`. It must include:
   - The agent behavior preamble (prefer action, chain tools, hard limits)
   - All 20 tool schemas with parameter descriptions
   - Current datetime context (already exists)
   - The tool calling format: `{"tool": "<name>", "parameters": {...}}`

4. **`kodai-consumer/Assistant/AssistantTool.swift`** — update the re-exports and `AssistantToolCatalog` to expose the new tool definitions JSON.

5. **Tests** — update existing tests in `kodai-consumerTests/` and add new ones:
   - `ToolCallParserTests.swift` — parse tests for representative new tools (contacts_search, clipboard_write, notification_schedule, web_fetch)
   - `ToolCallValidatorTests.swift` — validation tests for all 20 tools (required params present, missing required param fails, optional params work)
   - `SystemPromptBuilderTests.swift` — verify all 20 tool names appear in the built prompt

### Important

- Do NOT create router implementations or UI changes. This phase is types + validation + prompt only.
- Do NOT remove the `respond` tool — it's used when the model wants to reply with text instead of calling an action tool.
- The parser (`ToolCallParser.swift`) probably doesn't need changes — it parses generic JSON tool calls. But verify it handles the new tool names.
- Keep the `ParseConfidence` system (.native, .json, .pythonic).
- The `RawToolCall` type (name string + arguments dictionary) should remain generic — validation turns it into the typed `AssistantToolCall`.
- Verify everything compiles: `xcodebuild -project kodai-consumer.xcodeproj -scheme kodai-consumer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build test`
- Do NOT boot or run simulators. Use compile-only builds.
