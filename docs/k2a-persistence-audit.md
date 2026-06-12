# K2A — iOS Persistence Audit & CloudKit Migration Plan

Date: 2026-06-12. Status of codebase at audit time: K1H complete (iOS uses
KodaiKernel for inference protocol, context types, project/task values, slash
commands, proposals, and LocalContextPromptBuilder).

## 1. Why JSON existed, and what risk it creates now

The iOS app started as a standalone prototype (`kodAI_chatbot_dev`). JSON
files in Application Support were the cheapest durable store that:

- needed no schema or container setup while models churned weekly,
- kept Codable value types as the single source of truth,
- made debugging trivial (inspect/edit the files directly),
- avoided coupling the prototype to SwiftData before the kernel/persistence
  split existed.

That was the right call then. The risks now:

- **Whole-array rewrites.** `ChatStore.saveSessions` and
  `ProjectTaskStore.saveProjects` serialize the entire array on every change
  (ChatViewModel calls `saveSessions()` at ~40 sites). Cost grows linearly
  with history; a crash mid-write is mitigated by `.atomic`, but there is no
  partial update, no indexing, no lazy loading.
- **Silent data loss on decode failure.** All three `load*` methods catch
  decode errors and return `[]`. One bad migration of a Codable shape and the
  user's projects "disappear" while the next save overwrites the file.
- **No record-level identity for sync.** A JSON blob can't do per-record
  change tracking, conflict resolution, or tombstones — all required by
  CloudKit.
- **Divergence from macOS.** macOS already persists through SwiftData
  (`KodaiPersistence`); iOS JSON shapes (`KodaiProjectValue` with embedded
  `tasks`) and macOS models (`KodaiProject` ↔ `KodaiTask` relationship,
  `details: String` vs `details: String?`, `TaskPriority` low/medium/high vs
  `KodaiTaskPriority` low/normal/high) have already drifted.

## 2. Files that own persistence today

iOS app (`kodai_ios/kodAI_chatbot_dev/kodAI_chatbot_dev/`):

| File | Role |
|---|---|
| `ChatStore.swift` | JSON actor: `ChatSessions.json`, `Streams.json`, `PromptSettings.json` |
| `ProjectTaskStore.swift` | JSON actor: `Projects.json` (projects with embedded tasks) |
| `ChatSession.swift` | Codable `ChatSession` + `Stream` value types (iOS-only) |
| `ProjectTaskModels.swift` | typealiases onto kernel `KodaiProjectValue`/`KodaiTaskValue`/`DueTaskValue` |
| `ActivityLogModels.swift` | `ActivityEventLite` — **in-memory only**, not persisted |
| `ChatViewModel.swift` | The only caller of both stores; owns save timing |
| `AmbientContextProvider.swift`, `ChatView.swift` | `UserDefaults`/`@AppStorage` for preferences |
| `ConstraintSnapshot.swift`, `ContextVisibilityModels.swift` | runtime/UI snapshots, never persisted |

Shared package (`KodaiCore/Sources/`):

- `KodaiKernel/Models/WorkspaceValueModels.swift` — portable
  `KodaiProjectValue`/`KodaiTaskValue` (Foundation-only, the JSON shapes).
- `KodaiPersistence/Models/*.swift` — SwiftData `@Model` classes
  (`KodaiProject`, `KodaiTask`, `KodaiChatSession`, `KodaiChatMessage`,
  `KodaiStream`, `ActivityEvent`, `TurnRecord`, …) currently used by macOS
  only. **iOS links only the `KodaiKernel` product** (confirmed in
  project.pbxproj); it does not import KodaiPersistence anywhere.

SwiftData usage on iOS today: **none.**

## 3. Smallest safe migration sequence (JSON → SwiftData)

Each step is a separate commit; the app builds and runs after each.

1. **K2B — Reconcile the shared models.** Align `KodaiPersistence.KodaiTask`/
   `KodaiProject` with the kernel value types: same priority vocabulary
   (map `medium`↔`normal`), optionality, and add value↔model adapters
   (`init(value:)` / `var value`). Pure package change + tests; no app change.
2. **K2C — Link KodaiPersistence into the iOS target** and stand up a
   `ModelContainer` (local only, no CloudKit) behind the existing store API.
   No behavior change yet.
3. **K2D — Migrate Projects.json.** On first launch, if `Projects.json`
   exists and the SwiftData store has no projects, decode it, insert
   `KodaiProject`/`KodaiTask` models, then rename the file to
   `Projects.json.migrated` (keep as backup; never delete). Replace
   `ProjectTaskStore` reads/writes in `ChatViewModel` with the SwiftData
   path, still surfacing kernel value types to the UI so views don't change.
4. **K2E — Persist activity events** (optional, lightweight): give
   `ActivityEventLite` a SwiftData counterpart with a retention cap, or keep
   in-memory if not worth it.
5. **K2F — Leave chats on JSON.** `ChatSessions.json`/`Streams.json`/
   `PromptSettings.json` stay as-is. They are local-only by product decision,
   the JSON store works, and migrating them buys nothing for sync. Revisit
   only if chat storage itself becomes a problem.

Hard rules during migration: never delete the JSON source until the SwiftData
copy is verified; decode failures must surface (log + keep file), not return
`[]` and overwrite.

## 4. Sync boundary

**Sync (shared workspace, CloudKit-eligible):**
- Projects (title, details, deadline, status, timestamps)
- Tasks (title, details, priority, due date, completion, timestamps)
- Project deadlines / task due dates (already fields on the above)
- Plans and Challenges — *do not exist as types yet*; when added, model them
  in KodaiKernel as value types + KodaiPersistence models from day one
- Saved decisions/outcomes — none exist today (`docs/decisions.md` is
  repo-level, not app data); same rule as Plans when introduced
- Activity events: only if trimmed to metadata (kind, title, ids, timestamp)
  with a retention cap; defer until needed

**Local-only (durable but never leaves device):**
- Chat sessions, messages, streams, chat summaries (`ChatSessions.json`,
  `Streams.json`)
- Prompt settings (`PromptSettings.json`)
- UI preferences (UserDefaults/@AppStorage)
- TurnRecord/ledger, ModelPerformanceMetric, diagnostics

**Never sync:**
- Raw chat/conversation content of any kind (product decision)
- Context snapshots, assembled prompts, Glass Box context blocks
- ConstraintSnapshot / ambient context (device state)
- Model files, model runtime state, logs

## 5. Model changes needed before CloudKit

CloudKit-backed SwiftData has hard requirements the current
`KodaiPersistence` models violate:

- **No `@Attribute(.unique)`** — CloudKit forbids unique constraints.
  `KodaiProject.id`/`KodaiTask.id` use it; replace with app-level dedupe
  (UUIDs already give stable identity, which is the part sync actually needs).
- **All properties need defaults or be optional** — current non-optional
  `title`, `priority` etc. need default values in the `@Model`.
- **Relationships must be optional** — `KodaiProject.sessions`/`tasks` are
  non-optional arrays; make them `[KodaiTask]?` (or keep arrays with defaults
  per current SwiftData allowances — verify against the deployed OS).
- **Schema split.** Because chats must never sync, chat models
  (`KodaiChatSession`, `KodaiChatMessage`, `TurnRecord`, …) must live in a
  separate ModelConfiguration (local store file) from the workspace models
  (`KodaiProject`, `KodaiTask`, future Plan/Challenge/Decision), so only the
  workspace configuration is ever given `cloudKitDatabase:`. This also means
  **removing the `KodaiProject.sessions` relationship** (replace with a
  `projectID: UUID?` on the chat session) — a cross-configuration
  relationship can't exist, and we don't want chat linkage in the synced
  record anyway.
- Tombstones/soft-delete and `lastModifiedAt` discipline: `updatedAt` exists
  everywhere already; keep updating it on every mutation.

Verdict: the architecture is **not** CloudKit-ready yet — do not enable
CloudKit in this pass.

## 6. Recommended next slice

**K2B: reconcile KodaiPersistence models with kernel value types and add
value↔model adapters** (step 1 above). It is package-only, fully testable,
unblocks both the iOS SwiftData adoption and the future CloudKit schema, and
fixes the macOS/iOS vocabulary drift (priority `medium` vs `normal`) before
any data is written to a synced store. The `sessions` relationship removal
and `.unique` removal can ride along or be K2C's prep commit.
