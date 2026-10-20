# Song Key Layers, PR 2 (Planning Client) Implementation Plan

> Status: Ready for execution (2026-10-14). Covers PR 2 of
> `docs/specs/2026-10-13-personal-song-settings.md` only (PS14–PS21, tests
> C1–C11). PR 1 merged as #94 (`603d69b`) and its migration is deployed.
> PR 3 (reader) gets its own plan after this PR merges.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** The planning client stores, overlays, syncs and reconciles a song
item's shared plan key (`transpose`, `capo`) through one new planning
mutation kind, with no self-conflict and a working Keep mine.

**Architecture:** The pull reads the item's `version`, `transpose` and `capo`
into the planning projection (schema 8). A key edit is a
`sessionItemKeyEdit` row (aggregate type `session_item_key`) in the existing
outbox, folded per item, sent to `set_session_item_key`, reconciled like
every other kind. The hard part is PS15: a row folded while its previous
content was in flight or accepted-uncleared is rebased only when the server
state is provably the client's own write.

**Tech Stack:** Flutter/Dart, Drift (schema migration + codegen), Riverpod,
the existing planning sync stack; Supabase RPC `set_session_item_key`.

**Spec:** `docs/specs/2026-10-13-personal-song-settings.md` (PS14–PS21,
C1–C11). Also ADR-042, ADR-038 (D4/D7 contiguity, I3, I7), ADR-028 (D3, D8,
D9), ADR-030 (snapshot identity), ADR-041.

## Global Constraints

- Branch: `feat/song-key-planning-client` (exists, from `main` `603d69b`).
  Never commit to `main`.
- No backend change. RPC `set_session_item_key` with parameter names
  `p_organization_id`, `p_session_id`, `p_session_item_id`, `p_base_version`,
  `p_transpose_mode`, `p_transpose`, `p_capo_mode`, `p_capo`. Response
  columns `id`, `plan_id`, `session_id`, `organization_id`, `version`,
  `transpose`, `capo`, `plan_content_version`.
- Modes, stored and sent verbatim: `keep`, `set`, `clear`.
- Bounds: transpose −11..+11, capo 0..11. The store refuses anything else with
  `ArgumentError` (never sent).
- Kind: `PlanningMutationKind.sessionItemKeyEdit`, stored value
  `session_item_key_edit`, aggregate type `session_item_key`, aggregate id =
  session item id, `planId` and `sessionId` always set, `bumpsPlanContent`
  true.
- Planning Drift schema: 7 → 8, one `onUpgrade` step (`from < 8`).
- Sync popup nested detail text: `song key changed`.
- Do not change the behavior of any existing kind. Existing tests must pass
  unmodified, except where a new required interface method forces a fake to
  implement it (add the method, change nothing else).
- Every task's verification: `cd apps/lyron_app && flutter analyze && flutter
  test` (the full suite, never a subdirectory). Codegen after table changes:
  `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`.
- Code, comments, commits and docs in English. Subagent reports in caveman
  ultra (terse; identifiers, file:line and code exact).

## Review Focus

Inputs a naive implementation gets wrong; each has a pinning test below.

1. A no-op success that returns `R == b + 1` after a foreign write: the folded
   row must NOT be rebased (C11, Task 4).
2. A second Save while the first is in flight or accepted-uncleared must not
   self-conflict (C4, Task 4), and the rebase must never touch a row that is
   still `sending` (its accept write would then be lost).
3. Keep mine must look up the session ITEM's version, not the session's (the
   S5b rename defect) (C5, Task 4).
4. A key-edit row whose item is deleted locally, collapsed, or whose create is
   cancelled must not survive to be sent; an in-flight one must (C7, Task 2).
5. A projection upgraded from schema 7 reads item version 1 and null keys,
   never crashes on a missing column (C9, Task 1).

## STOP-and-report conditions

- Any existing test fails and the fix would change an existing kind's
  behavior.
- Making a test pass seems to need a backend or RPC change.
- The PS15 rebase cannot be placed in `applyAcceptedWriteEffects` without
  changing when that method runs for other kinds.
- `flutter analyze` reports a new warning you cannot fix locally.
- The pull fails against local Supabase with the new columns (would mean PR 1
  is not what this plan assumes).

## File Structure

- Create `apps/lyron_app/lib/src/application/planning/session_item_key_edit.dart`:
  the value object (modes, fold, apply, bounds). Pure, unit-tested.
- Modify `planning_mutation_sync_types.dart`: kind, record fields, draft,
  store interface method.
- Modify `drift_planning_mutation_store.dart`: record/fold, persistence,
  interactions, PS15 rebase, retry gate, `_currentBaseVersionFor`.
- Modify `budgeted_planning_mutation_store.dart`: the tenth admitted method.
- Modify `planning_mutation_reconciler.dart`: the reconcile case.
- Modify `supabase_planning_mutation_repository.dart`: RPC name, params,
  `_mapRow` for the kind.
- Modify `offline/planning/planning_local_tables.dart`,
  `planning_local_database.dart` (+ regenerated `.g.dart`),
  `planning_local_store.dart`: projection columns, mutation columns,
  `applySyncedSessionItemKey`.
- Modify `infrastructure/planning/supabase_planning_repository.dart`,
  `application/planning/planning_sync_payload.dart`,
  `planning_sync_controller.dart`: pull columns and mapping.
- Modify `domain/planning/session_item_summary.dart`: `version`,
  `planTranspose`, `planCapo`.
- Modify `planning_local_read_repository.dart`: the merged overlay.
- Modify `planning_write_service.dart`: `setSessionItemKey`.
- Modify `application/sync/unified_sync_overview.dart`: the detail text.
- Docs: ADR-028 D3 table, `docs/architecture/architecture.md`,
  `docs/product/sync-ux-contract.md`, `docs/domain/domain-model.md`, the spec
  status note.

---

### Task 1: Projection, pull and schema 8

**Files:**
- Modify: `apps/lyron_app/lib/src/domain/planning/session_item_summary.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_database.dart`
  (+ `planning_local_database.g.dart` by codegen)
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_payload.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`
  (the `PlanningSyncSessionItem` → `CachedSessionItemRecord` mapping before
  `replaceActiveProjection`, ~line 577)
- Modify: `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart`
- Test: `test/offline/adversarial/planning_migration_test.dart`,
  `test/offline/planning/planning_local_store_test.dart`,
  `test/infrastructure/planning/supabase_planning_repository_test.dart`

**Interfaces:**
- Produces: `SessionItemSummary.version` (`int`, default 1),
  `.planTranspose` (`int?`), `.planCapo` (`int?`);
  `CachedSessionItemRecord.version/transpose/capo` (same defaults);
  `PlanningSyncSessionItem.version/transpose/capo` (same defaults);
  `PlanningLocalStore.applySyncedSessionItemKey({required String userId,
  required String organizationId, required String sessionItemId, required int
  version, required int? transpose, required int? capo, required DateTime
  refreshedAt})`.
- Mutation-table columns added here too (one schema bump), used from Task 2:
  `keyTransposeMode` (text), `keyTranspose` (int), `keyCapoMode` (text),
  `keyCapo` (int), `keyBaseTranspose` (int), `keyBaseCapo` (int), all
  nullable.

- [ ] **Step 1: Red tests**
  - `planning_migration_test.dart`, new test "schema 7 → 8 keeps session items
    and mutations (C9)": create a v7 database the way the file's existing
    v6 → v7 test does, insert one `cached_planning_session_items` row and one
    `cached_planning_mutations` row, open with the current code, and assert:
    the item reads `version == 1`, `transpose == null`, `capo == null`; the
    mutation row survives with all six new columns null.
  - `planning_local_store_test.dart`: `replaceActiveProjection` with an item
    `CachedSessionItemRecord(version: 3, transpose: 2, capo: 1, ...)` then
    `readPlanDetail` returns a `SessionItemSummary` with `version 3`,
    `planTranspose 2`, `planCapo 1`; `applySyncedSessionItemKey(version: 4,
    transpose: null, capo: 5)` updates exactly those three fields; on an
    unknown item id it is a no-op (no throw, no row created).
  - `supabase_planning_repository_test.dart`: the `session_items` page fetcher
    receives columns containing `version, transpose, capo`, and a fetched row
    `{version: 2, transpose: -3, capo: null}` maps to
    `PlanningSyncSessionItem(version: 2, transpose: -3, capo: null)`; a row
    without the keys (older fixture) maps to `version 1`, nulls.
  - Run `flutter test` on these three files: fails to compile (missing
    fields) — that is the red.

- [ ] **Step 2: Implement**
  - `SessionItemSummary`: add `this.version = 1, this.planTranspose,
    this.planCapo`; include them in `==` and `hashCode`.
  - `CachedPlanningSessionItems`: `IntColumn get version =>
    integer().withDefault(const Constant(1))();` `IntColumn get transpose =>
    integer().nullable()();` `IntColumn get capo => integer().nullable()();`
  - `CachedPlanningMutations`: the six nullable columns named above.
  - `PlanningLocalDatabase`: `schemaVersion => 8`; in `onUpgrade` add:

```dart
      if (from < 8) {
        // S3 PR 2 (docs/specs/2026-10-13-personal-song-settings.md, PS17):
        // a pre-8 projection row reads item version 1 (no RPC bumped it
        // before the key edit existed) and no key until the next refresh.
        await m.addColumn(
          cachedPlanningSessionItems,
          cachedPlanningSessionItems.version,
        );
        await m.addColumn(
          cachedPlanningSessionItems,
          cachedPlanningSessionItems.transpose,
        );
        await m.addColumn(
          cachedPlanningSessionItems,
          cachedPlanningSessionItems.capo,
        );
        for (final column in [
          cachedPlanningMutations.keyTransposeMode,
          cachedPlanningMutations.keyTranspose,
          cachedPlanningMutations.keyCapoMode,
          cachedPlanningMutations.keyCapo,
          cachedPlanningMutations.keyBaseTranspose,
          cachedPlanningMutations.keyBaseCapo,
        ]) {
          await m.addColumn(cachedPlanningMutations, column);
        }
      }
```

  - Run codegen.
  - `CachedSessionItemRecord` and `PlanningSyncSessionItem`: add the three
    fields with defaults (`version = 1`); every construction site keeps
    compiling.
  - `DriftPlanningLocalStore`: write the three fields in the
    `replaceActiveProjection` and `upsertSyncedSessionItem` companions; map
    them in `readPlanDetail` / `readPlanDetailBySlug` into
    `SessionItemSummary`; add `applySyncedSessionItemKey` as an `update ...
    where userId, organizationId, sessionItemId` that changes only `version`,
    `transpose`, `capo` (not guarded by `LocalStorageWriteRecovery`: an
    in-place update of an existing row, ADR-028 D8's rule), firing the
    footprint callback only when a row changed.
  - Pull: add `version, transpose, capo` to the `session_items` columns
    string; `_mapItem` reads `(row['version'] as num?)?.toInt() ?? 1`,
    `(row['transpose'] as num?)?.toInt()`, `(row['capo'] as num?)?.toInt()`.
  - `planning_sync_controller.dart`: pass the three fields into
    `CachedSessionItemRecord`.

- [ ] **Step 3: Green** — full `flutter analyze && flutter test`.

- [ ] **Step 4: Commit**
  `feat(planning): project session item version and plan key (S3 PR 2)`

---

### Task 2: The `sessionItemKeyEdit` kind, recording and folding

**Files:**
- Create: `apps/lyron_app/lib/src/application/planning/session_item_key_edit.dart`
- Modify: `planning_mutation_sync_types.dart`, `drift_planning_mutation_store.dart`,
  `budgeted_planning_mutation_store.dart`, every test fake implementing
  `PlanningMutationStore` (add the method only)
- Test: create `test/application/planning/session_item_key_edit_test.dart`;
  extend `test/offline/planning/planning_mutation_store_test.dart`,
  `test/application/planning/budgeted_planning_mutation_store_test.dart`

**Interfaces:**
- Consumes: Task 1's mutation columns.
- Produces: `SessionItemKeyFieldMode`, `SessionItemKeyEdit`,
  `PlanningSessionItemKeyEditMutationDraft`,
  `PlanningMutationStore.recordSessionItemKeyEdit`, the record fields below.

- [ ] **Step 1: The value object, test first**

Create `session_item_key_edit.dart`:

```dart
/// One field of a key edit (PS11, PS14).
enum SessionItemKeyFieldMode { keep, set, clear }

extension SessionItemKeyFieldModeX on SessionItemKeyFieldMode {
  String get value => switch (this) {
    SessionItemKeyFieldMode.keep => 'keep',
    SessionItemKeyFieldMode.set => 'set',
    SessionItemKeyFieldMode.clear => 'clear',
  };
}

SessionItemKeyFieldMode sessionItemKeyFieldModeFromValue(String value) =>
    switch (value) {
      'keep' => SessionItemKeyFieldMode.keep,
      'set' => SessionItemKeyFieldMode.set,
      'clear' => SessionItemKeyFieldMode.clear,
      _ => throw ArgumentError.value(value, 'value', 'Unknown key mode'),
    };

/// A plan-key edit of one session item: per field keep, set (with a value)
/// or clear (docs/specs/2026-10-13-personal-song-settings.md, PS11, PS14).
class SessionItemKeyEdit {
  SessionItemKeyEdit({
    required this.transposeMode,
    this.transpose,
    required this.capoMode,
    this.capo,
  }) {
    _checkField('transpose', transposeMode, transpose, minTranspose, maxTranspose);
    _checkField('capo', capoMode, capo, minCapo, maxCapo);
  }

  static const minTranspose = -11;
  static const maxTranspose = 11;
  static const minCapo = 0;
  static const maxCapo = 11;

  final SessionItemKeyFieldMode transposeMode;
  final int? transpose;
  final SessionItemKeyFieldMode capoMode;
  final int? capo;

  static void _checkField(
    String name,
    SessionItemKeyFieldMode mode,
    int? value,
    int min,
    int max,
  ) {
    final valid = mode == SessionItemKeyFieldMode.set
        ? value != null && value >= min && value <= max
        : value == null;
    if (!valid) {
      throw ArgumentError.value(value, name, 'invalid for mode ${mode.value}');
    }
  }

  /// PS14 fold: this (later) edit over [earlier]. A later set or clear
  /// replaces that field's intent; a later keep leaves the earlier one.
  SessionItemKeyEdit foldOnto(SessionItemKeyEdit earlier) => SessionItemKeyEdit(
    transposeMode: transposeMode == SessionItemKeyFieldMode.keep
        ? earlier.transposeMode
        : transposeMode,
    transpose: transposeMode == SessionItemKeyFieldMode.keep
        ? earlier.transpose
        : transpose,
    capoMode: capoMode == SessionItemKeyFieldMode.keep
        ? earlier.capoMode
        : capoMode,
    capo: capoMode == SessionItemKeyFieldMode.keep ? earlier.capo : capo,
  );

  /// The key this edit produces from [transpose]/[capo] (PS12 step 8, PS15).
  ({int? transpose, int? capo}) applyTo({int? transpose, int? capo}) => (
    transpose: switch (transposeMode) {
      SessionItemKeyFieldMode.keep => transpose,
      SessionItemKeyFieldMode.set => this.transpose,
      SessionItemKeyFieldMode.clear => null,
    },
    capo: switch (capoMode) {
      SessionItemKeyFieldMode.keep => capo,
      SessionItemKeyFieldMode.set => this.capo,
      SessionItemKeyFieldMode.clear => null,
    },
  );

  @override
  bool operator ==(Object other) =>
      other is SessionItemKeyEdit &&
      other.transposeMode == transposeMode &&
      other.transpose == transpose &&
      other.capoMode == capoMode &&
      other.capo == capo;

  @override
  int get hashCode => Object.hash(transposeMode, transpose, capoMode, capo);
}
```

Tests in `session_item_key_edit_test.dart`: the mode round trip; each
invalid combination throws (`set` with null, `keep`/`clear` with a value,
transpose ±12, capo −1 and 12); `foldOnto` for (set over set, keep over set,
clear over set, set over clear); `applyTo` for every mode on both fields.

- [ ] **Step 2: Kind, record, draft, interface**
  - `PlanningMutationKind.sessionItemKeyEdit`; `value`
    `'session_item_key_edit'`; `aggregateType` `'session_item_key'`;
    `bumpsPlanContent` true; `planningMutationKindFromValue` maps it. Let the
    compiler list every exhaustive switch; each new arm follows this plan
    (Tasks 3–5) and nothing else changes.
  - `PlanningMutationRecord` gains persisted `keyEdit`
    (`SessionItemKeyEdit?`), `keyBaseTranspose` (`int?`), `keyBaseCapo`
    (`int?`) and in-memory-only `acceptedOwnKeyVersion` (`int?`, documented
    like `acceptedPlanContentVersion`), each with a `copyWith` parameter and
    a `clear…` flag.
  - Draft:

```dart
class PlanningSessionItemKeyEditMutationDraft {
  const PlanningSessionItemKeyEditMutationDraft({
    required this.sessionItemId,
    required this.sessionId,
    required this.planId,
    required this.edit,
    required this.baseVersion,
    required this.baseTranspose,
    required this.baseCapo,
    this.originSnapshot,
  });

  final String sessionItemId;
  final String sessionId;
  final String planId;
  final SessionItemKeyEdit edit;

  /// The item's `version` in the merged read (1 for an item whose create is
  /// still pending: the version `create_song_session_item` writes).
  final int baseVersion;

  /// The item's key at [baseVersion] (PS14 base values, used by PS15).
  final int? baseTranspose;
  final int? baseCapo;
  final Map<String, Object?>? originSnapshot;
}
```

  - `PlanningMutationStore.recordSessionItemKeyEdit({required
    PlanningMutationContext context, required
    PlanningSessionItemKeyEditMutationDraft draft})`.

- [ ] **Step 3: Red store tests** (`planning_mutation_store_test.dart`, real
  in-memory Drift, the file's existing setUp):
  - insert: one row, kind `sessionItemKeyEdit`, aggregate
    `('session_item_key', itemId)`, `planId`/`sessionId` set, status
    pending, base/base values from the draft, the edit round-trips through
    `readMutation` (all six columns).
  - **C2** fold: two records for the same item, the second with
    `(keep, set capo 2)` over `(set 3, keep)` → one row, edit
    `(set 3, set 2)`, the FIRST base version and base values, the first
    `orderKey`.
  - fold resets a `sending`, `accepted`, `conflict` and
    `failedRemoteDelete` row to pending, keeps its base, clears its error.
  - **C7**:
    - `recordSessionItemDelete` of the item drops a pending key row, keeps
      a `sending` or `accepted` one;
    - collapsing a still-pending `sessionItemCreateSong` drops the key row;
    - `resolveCancelledCreate(created: false)` of the item's create drops it
      unless it is in flight;
    - an accepted `sessionDelete` and an accepted `planDelete`
      (`applyAcceptedWriteEffects`) remove it;
    - a collapsed pending `sessionCreate` removes it.
  - **C8**: `DriftPendingLocalWorkReader.countPlanningPendingWork` counts the
    key row; `deletePlanningDataForUser` deletes it.

- [ ] **Step 4: Implement in `DriftPlanningMutationStore`**
  - Map the record fields to and from the six columns (mode `value`
    strings).
  - `recordSessionItemKeyEdit`, in one transaction, mirroring
    `recordSessionRename`'s fold:

```dart
final existing = await _readMutationByKey(
  userId: context.userId,
  organizationId: context.organizationId,
  aggregateType: 'session_item_key',
  aggregateId: draft.sessionItemId,
);
final record = existing == null
    ? PlanningMutationRecord(
        aggregateId: draft.sessionItemId,
        organizationId: context.organizationId,
        planId: draft.planId,
        sessionId: draft.sessionId,
        kind: PlanningMutationKind.sessionItemKeyEdit,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: await _nextOrderKey(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        updatedAt: DateTime.now().toUtc(),
        baseVersion: draft.baseVersion,
        keyEdit: draft.edit,
        keyBaseTranspose: draft.baseTranspose,
        keyBaseCapo: draft.baseCapo,
        originSnapshot: draft.originSnapshot,
      )
    // PS14: fold. First base and base values kept (ADR-028 squash rule);
    // any status returns to pending, which also makes an in-flight send's
    // accept write miss its revision (ADR-030 D3) and leaves the row for
    // the PS15 rebase.
    : existing.copyWith(
        keyEdit: draft.edit.foldOnto(existing.keyEdit!),
        syncStatus: PlanningMutationSyncStatus.pending,
        updatedAt: DateTime.now().toUtc(),
        clearErrorCode: true,
        clearErrorMessage: true,
      );
await _upsertRecord(
  context: context,
  aggregateType: 'session_item_key',
  record: record,
);
```

  - A private `_deleteKeyEditUnlessInFlight({context, sessionItemId})`
    (delete where aggregate `session_item_key`, id, status not in
    `_inFlightSyncStatuses`), called from both branches of
    `recordSessionItemDelete` and from `resolveCancelledCreate` when
    `created` is false for `session_item`.
  - `_deleteChildMutationsOfSession` and `_deletePendingMutationsForSession`:
    also match `aggregateType == 'session_item_key' & sessionId ==
    sessionId`. `_deleteChildMutationsOfPlan` already matches by `planId`;
    the C7 test proves it.
  - `BudgetedPlanningMutationStore.recordSessionItemKeyEdit`: the same
    `_guardedWrite` path as `recordSessionRename` (budget admission, the D9
    queue, the D8 recovery boundary); no collapse admission.

- [ ] **Step 5: Budget test** — at an exhausted budget a key edit is refused
  with `PlanningMutationBudgetExceededException`; below it, it is admitted.

- [ ] **Step 6: Green** — full `flutter analyze && flutter test`.

- [ ] **Step 7: Commit**
  `feat(planning): record and fold session item key edits (S3 PR 2)`

---

### Task 3: Remote mapping

**Files:**
- Modify: `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_mutation_repository.dart`
- Test: `test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`

**Interfaces:**
- Consumes: Task 2's record fields.
- Produces: a synced record for the kind whose `baseVersion` is the returned
  item version, whose `keyEdit` is the server state (`set` for a non-null
  field, `clear` for null), whose `acceptedPlanContentVersion` is set, and
  whose `acceptedOwnKeyVersion` is the returned version only when PS15's
  state check holds.

- [ ] **Step 1: Red tests** (the file's `.testing(rpc:)` fake):
  - the RPC name is `set_session_item_key` and the params are exactly the
    eight named ones, modes as strings, null for keep/clear values;
  - response `{version: 2, transpose: 3, capo: null, plan_content_version: 9,
    ...}` for a sent record `(base 1, edit (set 3, keep), base values
    (null, null))` maps to `baseVersion 2`, `keyEdit (set 3, clear)`,
    `acceptedPlanContentVersion 9`, `acceptedOwnKeyVersion 2`;
  - **C11 mapping**: same sent record, response `{version: 2, transpose: 3,
    capo: 5}` (a foreign write set capo) → `acceptedOwnKeyVersion null`;
  - a no-op at the current base (`version: 1` for a sent base 1) →
    `acceptedOwnKeyVersion null`;
  - errors (PS20): `P0001 session_item_version_conflict` → `conflict`;
    `P0002 session_item_not_found` and `session_not_found` → `remoteMissing`;
    `22023 invalid_session_item_key` → `unknown`. No mapper change is
    expected; the tests pin it.

- [ ] **Step 2: Implement** — rpc name and `_paramsFor` arm:

```dart
PlanningMutationKind.sessionItemKeyEdit => {
  ...organization,
  'p_session_id': record.sessionId,
  'p_session_item_id': record.aggregateId,
  'p_base_version': record.baseVersion,
  'p_transpose_mode': record.keyEdit!.transposeMode.value,
  'p_transpose': record.keyEdit!.transpose,
  'p_capo_mode': record.keyEdit!.capoMode.value,
  'p_capo': record.keyEdit!.capo,
},
```

  and, in `_mapRow`, after the generic mapping, for this kind only:

```dart
if (original.kind == PlanningMutationKind.sessionItemKeyEdit) {
  final returnedVersion = (row['version'] as num).toInt();
  final serverTranspose = (row['transpose'] as num?)?.toInt();
  final serverCapo = (row['capo'] as num?)?.toInt();
  // PS15: the server state is provably this client's own write only when
  // the version moved by exactly one from the sent base AND the state is
  // what the sent edit produces from the sent base values. A no-op success
  // can return base + 1 after a foreign write; the state check catches it.
  final expected = original.keyEdit!.applyTo(
    transpose: original.keyBaseTranspose,
    capo: original.keyBaseCapo,
  );
  final ownWrite =
      original.baseVersion != null &&
      returnedVersion == original.baseVersion! + 1 &&
      expected.transpose == serverTranspose &&
      expected.capo == serverCapo;
  return mapped.copyWith(
    keyEdit: SessionItemKeyEdit(
      transposeMode: serverTranspose == null
          ? SessionItemKeyFieldMode.clear
          : SessionItemKeyFieldMode.set,
      transpose: serverTranspose,
      capoMode: serverCapo == null
          ? SessionItemKeyFieldMode.clear
          : SessionItemKeyFieldMode.set,
      capo: serverCapo,
    ),
    acceptedOwnKeyVersion: ownWrite ? returnedVersion : null,
    clearAcceptedOwnKeyVersion: !ownWrite,
  );
}
```

  (`mapped` is the existing `original.copyWith(...)` result, bound to a local
  first.)

- [ ] **Step 3: Green** — full suite. **Step 4: Commit**
  `feat(planning): send session item key edits to set_session_item_key (S3 PR 2)`

---

### Task 4: Accept, rebase, reconcile, Keep mine

**Files:**
- Modify: `drift_planning_mutation_store.dart` (`applyAcceptedWriteEffects`,
  `retryMutation`, `_currentBaseVersionFor`)
- Modify: `planning_mutation_sync_controller.dart` (two guarded extra
  rebase calls in `_run`)
- Modify: `planning_mutation_reconciler.dart`
- Test: create `test/offline/adversarial/planning_session_item_key_sync_test.dart`
  (real in-memory Drift stores, the real `PlanningMutationSyncController`, a
  scripted fake remote; copy the harness shape of
  `planning_sync_snapshot_identity_test.dart` /
  `planning_in_flight_create_cancellation_test.dart`); extend
  `test/application/planning/planning_mutation_reconciler_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: the PS15 rebase and the PS16 retry behavior.

- [ ] **Step 1: Red tests** (each one names its spec ID):
  - **C1** accepted edit, then a second edit: first edit (base 1) accepted
    with `version 2`; the post-sync refresh returns the item at version 2;
    a second `recordSessionItemKeyEdit` built from the merged read carries
    base 2 and is accepted (the fake asserts the base it receives).
  - **C3** resend after a lost response: the fake commits but throws a
    connectivity error; the next run resends; the fake answers the no-op
    shape (current version, matching values); the row clears and the
    projection holds the returned version and values.
  - **C4a** fold while in flight: the fake's first call blocks on a
    `Completer`; meanwhile record a second edit of the same item; complete
    with `version 2` and the state the first edit produces; the row is now
    pending with base 2 and base values = the returned key; the next run
    sends base 2 and is accepted.
  - **C4b** fold onto accepted-uncleared: make `_refreshPlanning` block, so
    the row sits `accepted`; record a second edit; release the refresh; the
    batch-end `applyAcceptedWriteEffects` rebases the row to the returned
    version; the clear is skipped (revision moved); the next run sends the
    new base.
  - **C4c / C4d** the two narrow windows: wrap the real store (as
    `planning_sync_snapshot_identity_test.dart` wraps it) so a second edit is
    recorded INSIDE the `accepted` `saveSyncAttemptResult` call (C4c) and
    INSIDE the batch-end `clearMutation` call (C4d); in both, the row ends
    pending with the returned base, and the next send is accepted.
  - **C11** a no-op over a foreign write: the first send returns `version 2`
    with a kept field differing from the sent base values; the folded row
    keeps base 1; the next send gets `session_item_version_conflict` and the
    row is `conflict`.
  - **Not while sending**: `applyAcceptedWriteEffects` with an own-write
    response while the row is still `sending` leaves it untouched (no
    `localRevision` change), so the accept write applies.
  - **C5** Keep mine: a key edit ends `conflict`; a refresh puts the item at
    version 4 with key `(5, null)`; `retryMutation` sets base 4 and base
    values `(5, null)`; the next send carries base 4 and is accepted.
  - **C6** a retry from `pending` with an error (connectivity) or from
    `failedRemoteDelete` resends the ORIGINAL base.
  - **C10** the inherited gap: an accepted key edit whose context switches
    before the reconcile (use the same switch the existing
    content-version-advance tests use) leaves the projection at the old item
    version; the next edit's send is a `conflict`. The test name and a
    comment reference
    `docs/deferred/2026-09-30-content-version-advance-on-context-switch.md`.
  - Reconciler: for the kind, with a failed post-sync refresh, the projection
    item takes `baseVersion` as `version` and the server key from `keyEdit`.

- [ ] **Step 2: Implement**
  - `applyAcceptedWriteEffects`, inside its existing transaction, when
    `remoteResponse` and `accepted.kind == sessionItemKeyEdit`:

```dart
changed =
    await _rebaseFoldedKeyEdit(context: context, accepted: accepted) ||
    changed;
```

```dart
  /// PS15: a key edit folded into a row whose earlier content was in flight
  /// or accepted-uncleared moves to the version the client's OWN write
  /// produced -- [PlanningMutationRecord.acceptedOwnKeyVersion], set only
  /// when the server state is exactly what that write produces. A row still
  /// `sending` or `accepted` (no fold happened) is never touched: its own
  /// accept write or clear must still apply.
  Future<bool> _rebaseFoldedKeyEdit({
    required PlanningMutationContext context,
    required PlanningMutationRecord accepted,
  }) async {
    final ownVersion = accepted.acceptedOwnKeyVersion;
    if (ownVersion == null) {
      return false;
    }
    final row = await _readMutationByKey(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: 'session_item_key',
      aggregateId: accepted.aggregateId,
    );
    if (row == null ||
        row.kind != PlanningMutationKind.sessionItemKeyEdit ||
        row.syncStatus != PlanningMutationSyncStatus.pending ||
        row.baseVersion != ownVersion - 1) {
      return false;
    }
    final serverKey = accepted.keyEdit!.applyTo();
    return _upsertRecord(
      context: context,
      aggregateType: 'session_item_key',
      record: row.copyWith(
        baseVersion: ownVersion,
        keyBaseTranspose: serverKey.transpose,
        clearKeyBaseTranspose: serverKey.transpose == null,
        keyBaseCapo: serverKey.capo,
        clearKeyBaseCapo: serverKey.capo == null,
      ),
    );
  }
```

    (`applyTo()` with no arguments yields the server key, because the synced
    `keyEdit` is all `set`/`clear`. `_upsertRecord` returns whether the row
    changed.)
  - `PlanningMutationSyncController._run`: a fold can land between any two
    awaits, so the (idempotent) rebase also runs after every gated write
    that missed for this kind:
    1. right after the response (the existing `_applyAcceptedEffects`
       call; no change);
    2. in the `newRevision == null` branch, before `continue`, when
       `mutation.kind == PlanningMutationKind.sessionItemKeyEdit`:
       `await _applyAcceptedEffects(context, syncedMutation, remoteResponse: true);`
    3. in both batch-end branches, when `clearMutation` returns `false` and
       `synced.kind == PlanningMutationKind.sessionItemKeyEdit`:
       `await _applyAcceptedEffects(context, synced, remoteResponse: remoteResponse);`

    No other kind's path changes; points 2 and 3 are guarded by the kind.
  - `retryMutation`: the rebase gate becomes
    `!(isCascadeDelete || existing.kind == PlanningMutationKind.sessionItemKeyEdit) || existing.syncStatus == PlanningMutationSyncStatus.conflict`;
    when it rebases a key edit, also set `keyBaseTranspose`/`keyBaseCapo` from
    the projection item.
  - `_currentBaseVersionFor`: an arm for the kind returning the projection
    item's `version` (found by `record.sessionId` and `record.aggregateId` in
    `_localStore.readPlanDetail`), falling back to `record.baseVersion`.
  - Reconciler: a `case PlanningMutationKind.sessionItemKeyEdit:` calling
    `localStore.applySyncedSessionItemKey(... version: _required(record.baseVersion,
    'baseVersion', record.kind), transpose: key.transpose, capo: key.capo,
    refreshedAt: reconciledAt)` with `key = record.keyEdit!.applyTo()`.

- [ ] **Step 3: Prove the guards can fail** — temporarily drop the state check
  from Task 3's `ownWrite` (keep only the version check): C11 must fail.
  Temporarily drop `row.syncStatus != pending`: the "not while sending" test
  must fail. Temporarily remove call point 2, then call point 3: C4c, then
  C4d, must fail. Temporarily make `_currentBaseVersionFor` return the session's
  version for the kind: C5 must fail. Restore each.

- [ ] **Step 4: Green** — full suite. **Step 5: Commit**
  `feat(planning): rebase folded key edits and retry them by item version (S3 PR 2)`

---

### Task 5: Merged read, write service, sync popup, docs

**Files:**
- Modify: `planning_local_read_repository.dart`, `planning_write_service.dart`,
  `application/sync/unified_sync_overview.dart`
- Modify docs: `docs/architecture/decisions/ADR-028-local-storage-budget-and-eviction-policy.md`
  (D3 table and list: the tenth `record*` method),
  `docs/architecture/architecture.md` (planning mutation kinds / offline
  strategy: the key edit and its own OCC), `docs/product/sync-ux-contract.md`
  (the plan row detail list gains `song key changed`),
  `docs/domain/domain-model.md` (`session_items` read-model note: the client
  reads and writes the key from S3 PR 2), the spec's status note
- Test: `test/application/planning/planning_local_read_repository_test.dart`,
  `test/application/planning/planning_write_service_test.dart`,
  `test/application/sync/unified_sync_overview_test.dart`

**Interfaces:**
- Produces for PR 3:

```dart
class SessionItemKeyDraft {
  const SessionItemKeyDraft({
    required this.planId,
    required this.sessionId,
    required this.sessionItemId,
    required this.edit,
  });

  final String planId;
  final String sessionId;
  final String sessionItemId;
  final SessionItemKeyEdit edit;
}

// PlanningWriteService
Future<void> setSessionItemKey({
  required PlanningWriteContext context,
  required SessionItemKeyDraft draft,
});
```

- [ ] **Step 1: Red tests**
  - Read overlay: projection item `(version 2, key (1, null))` plus a pending
    key edit `(keep, set 3)` → merged `SessionItemSummary` has
    `planTranspose 1`, `planCapo 3`, `version 2`; a `conflict` key edit still
    overlays; a `cancelling` row never exists for this kind (no assertion).
  - Write service: `setSessionItemKey` records a draft whose base is the
    merged item's `version`, `planTranspose`, `planCapo`, with the
    `_sessionItemSnapshot` origin snapshot, then schedules a sync (same
    assertions style as the file's `deleteSessionItem` test).
  - Popup: a key-edit row under its plan reads `song key changed`.

- [ ] **Step 2: Implement**
  - Overlay: add the kind to the plan-level no-op arm list; in the item-level
    switch, replace the matching item (by `sessionId`, `aggregateId`) with a
    copy whose `planTranspose`/`planCapo` are
    `keyEdit.applyTo(transpose: item.planTranspose, capo: item.planCapo)`;
    `version` unchanged.
  - Write service: `setSessionItemKey` mirrors `deleteSessionItem`
    (`_requireMatchingContext`, merged `getPlanDetail`, find session and
    item, `recordSessionItemKeyEdit`, `_scheduleSync`).
  - Popup: `PlanningMutationKind.sessionItemKeyEdit => 'song key changed'`.
  - Docs as listed. In the spec status note: "PR 2 implemented on
    `feat/song-key-planning-client`".

- [ ] **Step 3: Green** — full suite. **Step 4: Commit**
  `feat(planning): overlay and write the plan key, popup detail (S3 PR 2)`

---

### Task 6: Full verification, review, PR

- [ ] **Step 1:** `./scripts/verify.sh` from the repository root: PASS
  (Flutter suite, analyzer, backend contracts unchanged). Also
  `cd apps/lyron_app && flutter build web --release` (the web compile gate).

- [ ] **Step 2: One adversarial whole-diff review** (most capable model,
  caveman ultra report), over `git diff main...HEAD -- apps/lyron_app/lib`,
  with this claim to disprove: "There is a sequence of local edits, sync
  runs, refreshes, retries, deletes and context switches in which a
  `sessionItemKeyEdit` either overwrites a foreign key change without a
  visible conflict, self-conflicts after its own accepted write was
  reconciled, is sent after its item was deleted locally, or blocks or
  loses another kind's accept, clear or rebase." Fix confirmed findings with
  a red test first.

- [ ] **Step 3:** push, open the PR (body: what PS14–PS21 implement, C1–C11,
  no backend change, the schema bump, and that PR 3 follows). End with the
  repository's `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
  line. Report link and CI, then STOP. Do not start PR 3.
