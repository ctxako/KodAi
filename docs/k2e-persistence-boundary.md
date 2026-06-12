# K2E — Workspace/chat persistence boundary

K2E splits SwiftData persistence into two independent schemas so each
container registers only the models it owns. Before this slice,
`KodaiProject.sessions` closed over the chat graph and forced
`KodaiChatSession`, `KodaiChatMessage`, `KodaiSummary`, and `KodaiStream`
into every schema that contained `KodaiProject` — including the iOS
workspace container, which never writes a chat row.

## The boundary

**Workspace models** (sync candidates for CloudKit later):

- `KodaiProject`
- `KodaiTask` (relationship `KodaiTask.project` ↔ `KodaiProject.tasks`,
  cascade delete — this is the only relationship in the workspace graph)

**Chat / local-only models** (never leave the device):

- `KodaiChatSession`, `KodaiChatMessage`, `KodaiSummary`, `KodaiStream`
- ledger models: `TurnRecord`, `ToolCall`, `ActivityEvent`,
  `ModelPerformanceMetric` (these already used a scalar `sessionID`)

No SwiftData relationship crosses the boundary in either direction.

## Scalar projectID instead of relationships

`KodaiChatSession.projectID: UUID?` and `KodaiSummary.projectID: UUID?`
replace the former `project` relationships. A SwiftData relationship requires
both entity types in the same schema, which is exactly the coupling the split
removes; a scalar UUID keeps the linkage while letting each store evolve (and
eventually sync) independently. Lookups go through fetches/filters on
`projectID` (see `ChatViewModel.currentProject(...)` and
`KodaiSidebar.sessions(in:)` on macOS). Cleanup that the old cascade did —
deleting a project's chats with it — is now explicit in
`ChatViewModel.deleteProject`.

## Containers

- **iOS `WorkspaceModelContainer`** registers only `KodaiProject` and
  `KodaiTask` (`cloudKitDatabase: .none`). Chats stay JSON-only in
  `ChatStore`. The pre-K2E workspace store (which carried the empty chat
  entities) reopens via automatic lightweight migration; covered by
  `StoreMigrationTests.testWorkspaceStoreReopensWithWorkspaceOnlySchema`.
- **macOS app container** still holds both sides in one store, built through
  `KodaiLocalStoreMigrationPlan`:
  - `KodaiLocalStoreSchemaV0` — original shape, `.unique` ids on
    project/task (pre-K2B stores on disk have this).
  - `KodaiLocalStoreSchemaV1` — post-K2B shape (unique constraints dropped),
    still relationship-coupled.
  - `KodaiLocalStoreSchemaV2` — current split shape.
  - V0→V1 is lightweight; V1→V2 is a custom stage that captures
    session→project and summary→project links in `willMigrate` and writes
    them to the scalar `projectID` fields in `didMigrate`, so no linkage is
    lost.

The V0/V1 classes are frozen copies and must not be edited; they exist only
so staged migration can identify and read old stores.

## Remaining before CloudKit (K2F+)

- Add a CloudKit-backed `ModelConfiguration` for the workspace container on
  iOS (entitlements, container id) — workspace models are now schema-clean
  for it (no unique constraints, no cross-boundary relationships; CloudKit
  also requires defaults/optionals, which `KodaiProject`/`KodaiTask` inits
  already satisfy, and inverse relationships, which `tasks ↔ project` has).
- Decide the macOS story: either point macOS workspace data at the same
  CloudKit-backed configuration (splitting its single store) or keep macOS
  local-only initially.
- Conflict/merge semantics for project/task edits across devices.
- Chats stay local-only by design.
