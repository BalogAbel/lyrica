# Planning Mutation Gaps, PR 2 (Rows That Never Resolve, F1) Implementation Plan

> Status: Ready (2026-10-27). Covers PR 2 of
> `docs/specs/2026-10-21-planning-mutation-gaps.md` only: MG6–MG9, their MG13
> rows, and decision F1 (design gate approved 2026-10-27). PR 3
> (`fix/purge-and-pull-guards`, MG10–MG12) gets its own plan after this PR
> merges.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reconcile never writes an older accepted write over newer
projected content, no `cancelling` row survives the next run of its context
(planning and song), a Retry rebases only from a visible conflict, and
discarding a create takes its dependents with it.

**Architecture:** F1 moves the reconcile and rule 1a into one
`PlanningLocalStore.applyAcceptedWrite` transaction that first checks the
projection (content version and one versioned row) and skips both when the
projection already holds the write or a later state. MG6/MG7 add a run-start
conversion of stale tombstones in both sync controllers, with a
tombstone-origin marker (planning schema 9) that lets a `*_not_found` answer
close the converted planning delete. MG8 is a rule change in
`DriftPlanningMutationStore.retryMutation`; MG9 is a new store
`discardMutation` that applies the ADR-028 D10 collapse effects.

**Tech Stack:** Flutter/Dart, Riverpod, Drift 2.28 (schema 8 → 9, one
column; nested transactions are savepoints), the existing planning and song
sync stacks. No backend change.

**Spec:** `docs/specs/2026-10-21-planning-mutation-gaps.md` (MG6–MG9, F1,
MG13, MG14, "Await Points in `_run`"). Also ADR-019, ADR-028 (D3, D8–D10),
ADR-030 ("Stranded Tombstone Follow-Up"), ADR-038 (decision 4, 5, the
2026-10-13 and 2026-10-21 amendments), ADR-042, the plan-delete spec
`docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (I3, I7, D5, D7–D9),
`docs/deferred/2026-10-22-content-version-ahead-of-content.md`. Lessons from
PR 1: `docs/plans/2026-10-22-planning-run-boundaries.md` ("Execution Notes").

## Global Constraints

- Branch: `fix/planning-unresolved-rows` (exists; holds this plan). Never
  commit to `main`.
- No backend change, no Supabase migration, no hosted deploy. Planning Drift
  schema 8 → 9 adds exactly one column; nothing else in the schema changes.
- New and changed interfaces (exact names; every task uses these):
  - `planning_local_store.dart`:
    `enum PlanningProjectionRowKind { plan, session, sessionItem }`;
    `class PlanningVersionedRow { const PlanningVersionedRow({required this.kind, required this.id, required this.writtenVersion}); final PlanningProjectionRowKind kind; final String id; final int writtenVersion; }`;
    `class PlanningAcceptedWriteGate { const PlanningAcceptedWriteGate({this.planId, this.acceptedContentVersion, this.versionedRow}); final String? planId; final int? acceptedContentVersion; final PlanningVersionedRow? versionedRow; }`;
    `PlanningLocalStore.applyAcceptedWrite({required String userId, required String organizationId, required PlanningAcceptedWriteGate gate, required Future<void> Function() apply}) → Future<void>`.
  - Removed: `PlanningLocalStore.advanceSyncedPlanContentVersion`,
    `PlanningMutationStore.advanceAcceptedPlanContentVersion` (interface,
    Drift, budgeted, every test double).
  - `PlanningMutationRecord.resolvesCancelledCreate` (`final bool`, constructor
    default `false`; `copyWith({bool? resolvesCancelledCreate})`).
    `CachedPlanningMutations.resolvesCancelledCreate => boolean().withDefault(const Constant(false))()`.
  - `PlanningMutationStore.convertStaleCreateTombstones({required String userId, required String organizationId}) → Future<void>`.
  - `PlanningMutationStore.discardMutation({required String userId, required String organizationId, required String aggregateType, required String aggregateId}) → Future<bool>`.
  - `SongMutationStore.convertStaleSongCreateTombstones({required String userId, required String organizationId}) → Future<void>`.
  - `BudgetedPlanningMutationStore`: both new planning methods go through
    `_queuedWrite` (write queue, never budget-admitted, no recovery
    boundary), like `clearMutation`.
- `PlanningMutationReconciler.reconcile(context, record)` and the
  `PlanningAcceptedMutationReconciler` typedef keep their signatures.
- Existing tests must pass unmodified, except: (a) mechanical interface
  migrations of test doubles forced by the list above (add the new methods
  with the behavior this plan names, remove the removed overrides; change
  nothing else in such a file); (b) the tests this plan names as rewritten,
  with the named rewrite.
- After the table change: `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`;
  commit the regenerated `planning_local_database.g.dart`.
- Every task's verification: `cd apps/lyron_app && flutter analyze && flutter test`
  (the full suite, never a subdirectory). A focused run while iterating is
  fine; a task is done only on the full run.
- A STOP means: stop, report what you found, and wait. Never resolve a STOP
  yourself (no extra test, no workaround). Reviewers re-run every
  "prove the guard can fail" step themselves (scratch edit, run, restore) and
  quote the failure message.
- Code, comments, commits and docs in English. Subagent reports in caveman
  ultra (terse; identifiers, file:line and code exact).

## Model and effort per task

| Task | Implementer | Task reviewer |
|---|---|---|
| 1 F1 | Sonnet, high | Opus, high |
| 2 Schema 9 | Sonnet, medium | Sonnet, medium |
| 3 MG6 | Sonnet, high | Sonnet, high |
| 4 MG7 | Sonnet, medium | Sonnet, medium |
| 5 MG8 | Sonnet, medium | Sonnet, medium |
| 6 MG9 | Sonnet, medium | Sonnet, medium |
| 7 Docs, verification, PR | Sonnet, medium | final whole-diff review: Opus, xhigh |

Read-only lookups during execution: Haiku, low.

## Review Focus

Inputs a naive implementation gets wrong; each has a pinning test in the
named task.

1. A crash-resumed `accepted` marker (no returned content version) reconciled
   after a pull stored newer content: the reconcile must not write the old
   base over it (Task 1).
2. A `*_not_found` answer to a converted delete that arrives after the
   context moved: it is not this row's verdict, so the row is reset to
   `pending`, never closed (Task 3).
3. A delete the user records over a converted tombstone-origin row: the
   marker is gone, so a later `*_not_found` stays visible as
   `failedRemoteDelete` (Task 3).
4. Discarding a failed item create whose key edit is in flight (`sending`):
   the key edit stays (Task 6).
5. A song tombstone of another catalog context is untouched by this
   context's run (Task 4).

## STOP-and-report conditions

1. An existing test fails for a reason other than (a)/(b) of the Global
   Constraints, in particular one that observes projection contents after a
   refresh-failed batch end, a `cancelling` row across a run, a retry's base,
   or a discard's leftovers.
2. Nested transactions inside `applyAcceptedWrite` misbehave: a deadlock, a
   "transaction already active" or savepoint error, or a guarded inner write
   whose retry fails inside the outer transaction.
3. A "prove the guard can fail" step does not fail.
4. A step seems to need a backend, RPC or Supabase migration change, or a
   delete RPC's `*_not_found` maps to anything other than
   `PlanningMutationSyncErrorCode.remoteMissing` /
   `SongMutationSyncErrorCode.remoteDeleted`.
5. The regenerated Drift code changes anything beyond the new column.
6. A production caller of `advanceSyncedPlanContentVersion` or
   `advanceAcceptedPlanContentVersion` other than
   `DriftPlanningMutationStore.advanceAcceptedPlanContentVersion` and
   `PlanningMutationSyncController._advanceAcceptedContentVersion` appears.
7. The full suite fails in an area this plan does not touch, or
   `flutter analyze` reports a warning you cannot fix locally.

## File Structure

- `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`: the
  gate types, `applyAcceptedWrite`, `advanceSyncedPlanContentVersion` removed.
- `apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart`:
  validate first, one `applyAcceptedWrite` per kind.
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`:
  no separate advance (F1); run-start conversion and the tombstone-origin
  close (MG6); `discardMutation` through the store (MG9).
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart`:
  record field, interface methods.
- `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`:
  the new column in `_toRecord` / `_upsertRecord` / `_matchesPersistedRecord`,
  `convertStaleCreateTombstones`, `discardMutation`, the MG8 retry rule,
  `advanceAcceptedPlanContentVersion` removed.
- `apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart`:
  queued pass-throughs.
- `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart`,
  `planning_local_database.dart` (+ `.g.dart`): schema 9.
- `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_types.dart`,
  `drift_song_mutation_store.dart`, `song_mutation_sync_controller.dart`: MG7.
- Tests: `test/offline/planning/planning_local_store_test.dart`,
  `test/application/planning/planning_mutation_reconciler_test.dart`,
  `test/offline/adversarial/planning_content_version_ahead_test.dart`,
  `test/offline/planning/planning_mutation_store_test.dart`,
  `test/offline/adversarial/planning_migration_test.dart`,
  `test/application/planning/planning_mutation_sync_controller_test.dart`,
  `test/application/song_library/song_mutation_sync_controller_test.dart`;
  new `test/offline/adversarial/planning_stranded_tombstone_test.dart`,
  `test/offline/adversarial/song_stranded_tombstone_test.dart`,
  `test/offline/adversarial/planning_retry_rebase_test.dart`.

---

### Task 1: The reconcile and rule 1a are one projection transaction (F1)

**Files:**
- Modify: `planning_local_store.dart`, `planning_mutation_reconciler.dart`,
  `planning_mutation_sync_controller.dart` (refresh-failed branch;
  `_advanceAcceptedContentVersion` removed), `planning_mutation_sync_types.dart`,
  `drift_planning_mutation_store.dart`, `budgeted_planning_mutation_store.dart`
- Modify (mechanical, Global Constraints (a)): every `PlanningLocalStore` test
  double without `noSuchMethod` gets `applyAcceptedWrite` (`=> apply()`; the
  delegating double in `test/application/providers_test.dart` delegates);
  remove every `advanceSyncedPlanContentVersion` override (7 files:
  `test/app/lyron_app_test.dart`, `test/application/providers_test.dart`,
  `test/application/planning/planning_sync_controller_test.dart`,
  `test/application/planning/planning_local_read_repository_test.dart`,
  `test/application/storage/local_data_lifecycle_test.dart`,
  `test/presentation/song_library/song_list_screen_test.dart`,
  `test/offline/song_catalog/song_catalog_store_test.dart`) and every
  `advanceAcceptedPlanContentVersion` override (15 in 13 files; list with
  `grep -rln "advanceAcceptedPlanContentVersion" apps/lyron_app/test`),
  including the `'advance:'` log line of `_FakePlanningMutationStore` (no test
  asserts it)
- Test: `planning_local_store_test.dart`, `planning_mutation_reconciler_test.dart`,
  `planning_content_version_ahead_test.dart`, `planning_mutation_store_test.dart`

**Interfaces:**
- Produces: the gate types and `applyAcceptedWrite` (Global Constraints).
- `PlanningMutationReconciler.reconcile` contract: validates every required
  field before any store call; then exactly one `applyAcceptedWrite` whose
  `apply` runs today's switch-arm writes; rule 1a happens inside it. Per
  kind (decision F1 of the spec, verbatim):

  | Kind | `acceptedContentVersion` | `versionedRow` (kind, id, writtenVersion) |
  |---|---|---|
  | `planCreate`, `planEdit` | null | plan, `aggregateId`, `baseVersion ?? 1` |
  | `planDelete` | null | null |
  | `sessionCreate`, `sessionRename` | `acceptedPlanContentVersion` | session, `aggregateId`, `baseVersion ?? 1` |
  | `sessionDelete` | `acceptedPlanContentVersion` | null |
  | `sessionReorder` | `acceptedPlanContentVersion` | plan, `planId ?? aggregateId`, `baseVersion ?? 1` |
  | `sessionItemCreateSong`, `sessionItemDelete`, `sessionItemReorder` | `acceptedPlanContentVersion` | session, `sessionId` (required), `baseVersion ?? 1` |
  | `sessionItemKeyEdit` | `acceptedPlanContentVersion` | sessionItem, `aggregateId`, `baseVersion` (required) |

  `gate.planId` is the moved rule-1a block: `aggregateId` when
  `kind.aggregateType == 'plan'`, `planId` otherwise.

- [ ] **Step 1: Un-skip the F1 tests.** In
  `planning_content_version_ahead_test.dart` remove both `skip: skipReason`
  arguments and the `skipReason` constant; reword the header doc comment from
  "skipped until the fix" to "the acceptance tests of decision F1". Run the
  file. Expected: both FAIL on `expect(detail.sessions.single.name, 'Foreign')`
  (Actual: `'Renamed'`) or on version 4 (Actual: 3).
- [ ] **Step 2: Add the controller-level row-gate test** to the same file:
  `'a crash-resumed accepted rename does not overwrite a pull stored after the crash (F1)'`.
  Record the rename (base 2), write
  `saveSyncAttemptResult(syncStatus: accepted, expectedRevision: <its localRevision>)`
  (the crash left the marker), then `await planningSync.refreshPlanning()`
  with the `'Foreign'` payload (session v4, content version 5), then run a
  `PlanningMutationSyncController` with `refreshPlanning: (_) async => false`,
  `isRunContextActive: (_) => true`, the remote that would fail the test if
  called (`ScriptedPlanningRemote((_) => fail('resumed marker is not resent'))`)
  and `reconcileAcceptedMutation: reconciler.reconcile`. Expect
  `expectProjectionHoldsF()` and `readAllMutations` empty.
- [ ] **Step 3: Write the failing store tests** in
  `planning_local_store_test.dart`, new group `'applyAcceptedWrite (F1)'`
  next to the existing content-version tests (reuse its `seed()`: plan-1 at
  content version 4; `contentVersion(planId)` helper). `apply` is a closure
  counting its calls (`var applied = 0`):
  - `'skips the write and the advance when the projection is at or past R'`:
    `acceptedContentVersion: 4`, then `3`, `planId: 'plan-1'` → `applied == 0`,
    content version 4.
  - `'applies and advances exactly at R - 1, and is idempotent'`: R 5 →
    `applied == 1`, 5; R 5 again → `applied == 1`, 5.
  - `'applies without advancing below R - 1'`: R 6 → `applied == 1`, 4.
  - `'skips the write when the versioned row is newer than the written version'`:
    for each of plan `plan-1`, session `session-1` and session item `item-1`
    (all at version 1 in `seed()`): written 0 → skipped; written 1 →
    applied; written 2 → applied (no `acceptedContentVersion`).
  - `'an absent row, plan or projection never blocks the write'`: versioned
    row `session-x`; then a store with no owner at all → `applied == 1` each,
    nothing advanced.
  - `'a throwing apply rolls back its writes and the advance'`: R 5, `apply`
    calls `upsertSyncedSession(... name: 'Partial' ...)` then throws
    `StateError('boom')` → `throwsStateError`, session-1 name unchanged,
    content version 4.
  Rewrite (Global Constraints (b)) the two existing tests onto the new method:
  - `'advanceSyncedPlanContentVersion moves only a contiguous value'` →
    `'applyAcceptedWrite advances only a contiguous value'`: R 6 → 4
    (`reason: 'gap: foreign write'`), R 5 → 5, R 5 → 5 (`reason: 'idempotent'`),
    with a no-op `apply`.
  - `'advanceSyncedPlanContentVersion never fills a null value (I7)'` →
    `'applyAcceptedWrite never fills a null content version (I7)'`: same
    loop over R ∈ {0, 1, 2}, `apply` called every time, content version stays
    `null`.
- [ ] **Step 4: Write the failing reconciler tests** in
  `planning_mutation_reconciler_test.dart`, new group `'F1 gate'` (its own
  `setUp` seeding plan-1 v2 / content version 4, session-1 v2 `'S'`, item-1
  v1 through `replaceActiveProjection`):
  - `'a rename response at R - 1 reconciles and advances to R'`:
    `sessionRename` `baseVersion: 3`, `acceptedPlanContentVersion: 5`, name
    `'Mine'` → session `'Mine'` v3, content version 5.
  - `'a crash-resumed rename marker does not overwrite a newer projected session'`:
    re-seed session-1 v4 `'Foreign'`; `sessionRename` `baseVersion: 2`, no
    accepted content version → `'Foreign'` v4, content version 4.
  - `'a crash-resumed rename marker over its own base still reconciles'`:
    `baseVersion: 2`, name `'Mine'` → `'Mine'` v2, content version 4 (lag).
  - `'a planEdit older than the projected plan is skipped'`: plan-1 v2,
    `planEdit` `baseVersion: 1`, name `'Old'` → plan name unchanged.
  - `'a planEdit response never advances the content version'`: `planEdit`
    `baseVersion: 3`, `acceptedPlanContentVersion: 5` → plan v3, content
    version 4 (plan kinds carry no `acceptedContentVersion` in the gate).
  - `'a session created and since deleted by another member is not resurrected'`:
    re-seed content version 6 without the new session; `sessionCreate`
    `session-new`, `baseVersion: 1`, `acceptedPlanContentVersion: 5` → no
    `session-new` in the detail, content version 6. Then re-seed content
    version 4 and reconcile the same record → `session-new` present, content
    version 5.
  - `'a key edit without a returned content version is skipped when the item is newer'`:
    re-seed item-1 v3; key edit `baseVersion: 2`, no accepted content version
    → item-1 v3, key unchanged; with item-1 v1 → applied (v2, the key).
  - `'a corrupt record throws before any projection write, even when the projection is newer'`:
    re-seed content version 9; `sessionItemCreateSong` with `songId: null`,
    `acceptedPlanContentVersion: 5` → `throwsA(isA<ReconcileFieldError>())`.
- [ ] **Step 5: Run the new tests to verify they fail** (compile errors for
  the missing method count as failing). Expected also: the F1 tests from
  Step 1 and Step 2 fail.
- [ ] **Step 6: Implement `applyAcceptedWrite`** in `DriftPlanningLocalStore`
  (and the interface, with a doc comment citing spec F1). Algorithm (one
  `_database.transaction`; `apply` runs inside it, so its own
  `_database.transaction` calls nest as savepoints and its guarded writes keep
  their own `_guarded` wrapper; `applyAcceptedWrite` itself is not guarded):

```dart
var applied = false;
await _database.transaction(() async {
  final owner = await _readOwner(userId: userId, organizationId: organizationId);
  final planId = gate.planId;
  final plan = owner == null || planId == null
      ? null
      : await (_database.select(_database.cachedPlanningPlans)..where(
            (t) => t.userId.equals(userId) & t.organizationId.equals(organizationId) &
                t.snapshotVersion.equals(owner.snapshotVersion) & t.planId.equals(planId),
          )).getSingleOrNull();
  final current = plan?.contentVersion;
  final accepted = gate.acceptedContentVersion;
  if (accepted != null && current != null && current >= accepted) return;
  final row = gate.versionedRow;
  if (row != null && owner != null) {
    final projected = await _projectedVersion(owner.snapshotVersion, row, userId, organizationId);
    if (projected != null && projected > row.writtenVersion) return;
  }
  await apply();
  applied = true;
  if (accepted != null && current == accepted - 1) {
    // D7 rule 1a: the same contiguous UPDATE advanceSyncedPlanContentVersion ran.
  }
});
if (applied) _onStorageFootprintChanged?.call();
```

  `_projectedVersion` reads `version` of the plan / session / session-item
  row of that snapshot (null when absent). The rule-1a UPDATE is the body of
  today's `advanceSyncedPlanContentVersion` (`WHERE content_version = R - 1`).
  Remove `advanceSyncedPlanContentVersion` from the interface and the Drift
  store; update the `_upsertPlanRow` comment that names it.
- [ ] **Step 7: Restructure the reconciler.** `reconcile` builds
  `({PlanningAcceptedWriteGate gate, Future<void> Function() apply})` in a
  private `_acceptedWriteFor(...)` switch that runs every `_required(...)`
  eagerly and captures the validated values; each arm's `apply` is today's arm
  body. Then `await localStore.applyAcceptedWrite(...)`. Doc comment: `R`
  only exists on a record mapped from a backend response
  (`acceptedPlanContentVersion` is in memory only), and the PS15 gate nulls it
  for a key edit that is not provably the caller's own; such records are
  gated by their versioned row only and never advance.
- [ ] **Step 8: Remove the separate advance.** In `_run`'s refresh-failed
  branch keep `if (_isRunContextActive(context)) { await _reconcileAcceptedMutation(context, synced); }`
  inside the existing `try` / `on ReconcileFieldError`; delete the rule-1a
  block and `_advanceAcceptedContentVersion`; rewrite the MG4 comment there
  to cite F1 (the advance lives in the reconcile's transaction). Remove
  `advanceAcceptedPlanContentVersion` from `PlanningMutationStore`,
  `DriftPlanningMutationStore`, `BudgetedPlanningMutationStore`; update the
  `applyAcceptedWriteEffects` doc comment that points to it. Migrate the test
  doubles (Files).
- [ ] **Step 9: Rewrite the three store tests** (Global Constraints (b)) in
  `planning_mutation_store_test.dart`:
  - `'applyAcceptedWriteEffects no longer advances the projection content version (MG4)'`
    → `'applyAcceptedWriteEffects never moves the projection content version (MG4, F1)'`:
    delete the `advanceAcceptedPlanContentVersion` call and the final
    `expect(..., 4)`; keep everything else.
  - `'rule 1: a contiguous own child write rebases the pending plan delete and the projection'`
    → `'rule 1b: a contiguous own child write rebases the pending plan delete'`:
    delete the `advanceAcceptedPlanContentVersion` call and its `expect(..., 6)`.
  - `'rule 1 is idempotent and ignores planEdit/planCreate responses'`: delete
    the block from the comment "Rule 1a, now its own call" to the end of the
    test body (the advance cases now live in Step 3 / Step 4).
- [ ] **Step 10: Run the files, then the full suite.** Expected: green. In
  particular these pass unmodified: `planning_run_boundary_test.dart` ('a
  plan created and given a child in one batch still reaches content version
  2', 'a reconcile failure leaves the projection content version untouched'),
  `planning_session_item_key_sync_test.dart` (the C3 refresh-failed variant
  and 'a no-op success does not advance the projection content version (rule
  1a) when the post-sync refresh fails'), `planning_cascade_delete_test.dart`,
  `planning_reconcile_nullfield_test.dart`, `clock_skew_probe_test.dart`.
- [ ] **Step 11: Prove each guard can fail** (scratch edit, run, restore):
  (i) drop the content check → `'a session created and since deleted by
  another member is not resurrected'` fails (the F1 tests still pass through
  the row check); (ii) drop the versioned-row check → both crash-resumed
  tests (Step 2, Step 4) fail; (iii) relax both contiguity checks together:
  advance on `current < accepted` instead of `current == accepted - 1` and
  drop the rule-1a UPDATE's `content_version = R - 1` predicate →
  `'applies without advancing below R - 1'` and
  `'applyAcceptedWrite advances only a contiguous value'` fail (E5); (iv) run the `_required` checks inside `apply` → `'a corrupt record
  throws before any projection write…'` fails; (v) call `apply()` outside the
  transaction → `'a throwing apply rolls back its writes and the advance'`
  fails.
- [ ] **Step 12: Commit.**
  `fix(planning): reconcile and rule 1a in one projection transaction (F1)`

### Task 2: Planning schema 9, the tombstone-origin marker (no behavior change)

**Files:**
- Modify: `planning_local_tables.dart`, `planning_local_database.dart`
  (`schemaVersion => 9`; `if (from < 9) await m.addColumn(cachedPlanningMutations, cachedPlanningMutations.resolvesCancelledCreate);`
  with a comment citing MG6), regenerated `planning_local_database.g.dart`
- Modify: `planning_mutation_sync_types.dart` (field, constructor default,
  `copyWith`), `drift_planning_mutation_store.dart` (`_toRecord`,
  `_upsertRecord` writes it, `_matchesPersistedRecord` compares it)
- Test: `test/offline/adversarial/planning_migration_test.dart`,
  `planning_mutation_store_test.dart`

- [ ] **Step 1: Write the failing migration test**
  `'schema 8 → 9 adds resolvesCancelledCreate as false and keeps every mutation'`,
  modeled on `'schema 7 → 8 keeps session items and mutations (C9)'`: the v7
  test's DDL plus exactly the columns `onUpgrade`'s `from < 8` block adds;
  insert a `cancelling` `session_create` row and a `pending` `plan_edit` row;
  `PRAGMA user_version = 8`; open through `PlanningLocalDatabase.connect`.
  Expect both rows readable with their kinds and statuses,
  `resolvesCancelledCreate == false` on both, and
  `PRAGMA user_version` reads 9.
- [ ] **Step 2: Write the failing store test**
  `'resolvesCancelledCreate round-trips and survives a retry'`:
  `recordSessionCreate`, then `readMutation` → `false`; set the column
  directly
  (`database.update(database.cachedPlanningMutations)..where(...)).write(const CachedPlanningMutationsCompanion(resolvesCancelledCreate: Value(true)))`),
  `readMutation` → `true`; `saveSyncAttemptResult(conflict)` then
  `retryMutation` → still `true`, `localRevision` bumped (the retry's
  `_upsertRecord` writes the column, and `_matchesPersistedRecord` compares
  it).
- [ ] **Step 3: Run to verify they fail.**
- [ ] **Step 4: Implement** the column, migration, field and the three
  store mappings; run `build_runner`.
- [ ] **Step 5: Run the files, then the full suite.** Expected: green.
- [ ] **Step 6: Prove the guard can fail:** remove the `from < 9` step → the
  migration test fails with a missing-column error.
- [ ] **Step 7: Commit.**
  `feat(planning): schema 9 tombstone-origin marker on planning mutations (MG6)`

### Task 3: A stale planning tombstone becomes a pending delete at run start (MG6)

**Files:**
- Modify: `planning_mutation_sync_types.dart` (`convertStaleCreateTombstones`),
  `drift_planning_mutation_store.dart`, `budgeted_planning_mutation_store.dart`,
  `planning_mutation_sync_controller.dart` (`_run` start; the failure
  branch)
- Modify (mechanical): every `PlanningMutationStore` test double gets a
  no-op `convertStaleCreateTombstones`; the one in
  `planning_mutation_sync_controller_test.dart` counts calls in
  `int convertCalls` and logs no event (its exact `events` lists stay
  unchanged), and gains `bool throwOnEffects = false` (makes
  `applyAcceptedWriteEffects` throw `Exception('effects')`)
- Create: `test/offline/adversarial/planning_stranded_tombstone_test.dart`
  (real `DriftPlanningLocalStore` / `DriftPlanningMutationStore`,
  `seedPlanningProjection(localStore, contentVersion: 3)`,
  `ScriptedPlanningRemote`, real `PlanningMutationReconciler`,
  `refreshPlanning: (_) async => false`, `isRunContextActive: (_) => true`)
- Test: `planning_mutation_store_test.dart`, `planning_mutation_sync_controller_test.dart`

**Interfaces:**
- Consumes: `resolvesCancelledCreate` (Task 2).
- Produces: `convertStaleCreateTombstones` (Global Constraints).
  Conversion, per `cancelling` row of the context in `orderKey` order, each in
  its own transaction that re-reads the row and converts it only if it is
  still `cancelling`:

  | Tombstone kind | Becomes | Bases |
  |---|---|---|
  | `planCreate` | `planDelete` | `baseVersion: 1`, `baseContentVersion: 1` |
  | `sessionCreate` | `sessionDelete` | `baseVersion: 1` |
  | `sessionItemCreateSong` | `sessionItemDelete` | `baseVersion: b + 1` (b = the row's `baseVersion`; `null` stays `null`, which the RPC rejects as a conflict) |

  Built as `existing.copyWith(kind: …, syncStatus: pending, orderKey: await _nextOrderKey(...), updatedAt: now, baseVersion: …, baseContentVersion: … (plan only), clearSlug: true, clearName: true, clearErrorCode: true, clearErrorMessage: true, resolvesCancelledCreate: true, originSnapshot: …)`
  (`planId`, `sessionId`, `songId`, `songTitle`, `position` are kept). The
  origin snapshot is the create's, or, for a plan or session create that has
  none, `{'name': existing.name}` (the label `recordPlanDelete`'s
  stranded-tombstone branch already keeps, since the name column is
  dropped); an item keeps `existing.originSnapshot`. Fires the footprint
  callback when it converted anything.

- [ ] **Step 1: Write the failing store tests** in
  `planning_mutation_store_test.dart`, group `'convertStaleCreateTombstones (MG6)'`.
  Strand a tombstone with a helper: `record*Create`, then
  `saveSyncAttemptResult(syncStatus: sending, expectedRevision: <localRevision>)`,
  then the matching `record*Delete` (row becomes `cancelling`).
  - `'a plan create tombstone becomes a pending plan delete based on (1, 1)'`:
    kind `planDelete`, `pending`, `baseVersion 1`, `baseContentVersion 1`,
    `resolvesCancelledCreate` true, `slug` and `name` null,
    `originSnapshot == {'name': <the create's name>}`, `orderKey` greater than
    every other row's.
  - `'a session create tombstone becomes a pending session delete based on 1'`:
    `sessionDelete`, `baseVersion 1`, `planId` kept.
  - `'an item create tombstone becomes a pending item delete based on b + 1'`:
    create `baseVersion: 2` → `sessionItemDelete`, `baseVersion 3`,
    `sessionId` / `planId` kept.
  - `'only cancelling rows of the given context are converted'`: a `pending`
    create of the same context and a `cancelling` row of `org-2` stay as
    they are.
  - `'a user-recorded delete over a converted row clears the marker'`:
    convert a session tombstone, then `recordSessionDelete` for the same
    session → `resolvesCancelledCreate` false (Review Focus 3, store half).
  - `'retry keeps the marker'`: converted row → `saveSyncAttemptResult(conflict)`
    → `retryMutation` → still `true`.
- [ ] **Step 2: Write the failing run tests** in
  `planning_stranded_tombstone_test.dart` (strand with the same helper; the
  scripted remote records every call):
  - `'a stranded plan create tombstone whose create committed is deleted by the next run'`:
    remote accepts the delete (returns the record) → `calls.single.kind == planDelete`,
    `baseVersion 1`, `baseContentVersion 1`; no mutation rows left.
  - `'a stranded plan create tombstone whose create never committed closes on plan_not_found and purges its child rows'`:
    after stranding, `recordSessionCreate` under the same plan (a child row);
    the remote throws `remoteMissing` for every call → two calls (the child,
    then the delete), no mutation rows left.
  - `'a stranded session create tombstone: committed is deleted, never committed closes on session_not_found'`
    (two sub-cases, the second with `remoteMissing`): `sessionDelete`
    `baseVersion 1` sent; no rows left either way.
  - `'a stranded item create tombstone sends its delete based on b + 1'`:
    item create `baseVersion: 2` under `session-1` → `calls.single.kind == sessionItemDelete`,
    `baseVersion 3`; remote accepts → no rows left.
  - `'an uncommitted item create in a quiet session conflicts once, then Keep mine closes it'`:
    call 1 throws `conflict` → row `conflict`, marker true; then
    `controller.retryMutation(ctx, aggregateType: 'session_item', aggregateId: <id>)`
    → call 2 has `baseVersion 2` (the projected session version) and the
    remote throws `remoteMissing` → no rows left.
  - `'a connectivity failure keeps the converted delete pending and marked'`.
  - `'a user-recorded delete answered not_found stays visible (D9)'`:
    `recordPlanDelete` for the projected `plan-1` (bases 2, 3), remote throws
    `remoteMissing` → row `failedRemoteDelete`.
  - Review Focus 3: `'a delete recorded over a converted row is no longer closed by not_found'`:
    convert a session tombstone, `recordSessionDelete` again, remote throws
    `remoteMissing` → row `failedRemoteDelete`.
- [ ] **Step 3: Write the failing controller tests** in
  `planning_mutation_sync_controller_test.dart` (fake store):
  - `'a run converts stale tombstones before it reads its candidates'`: the
    fake appends `'convert'` / `'readAll'` to a new `List<String> runCalls`
    (separate from `events`) in `convertStaleCreateTombstones` /
    `readAllMutations`; expect `runCalls.take(2)` equals
    `['convert', 'readAll']` and `convertCalls == 1`.
  - Review Focus 2: `'a not_found answered after a context change resets the converted delete instead of closing it'`:
    one pending `sessionDelete` with `resolvesCancelledCreate: true`; the
    remote throws `remoteMissing` after `active = false` → events contain
    `'save:pending:<id>'`, `clearedAggregateIds` is empty.
  - `'a not_found close whose purge fails resets the row to pending'`:
    `throwOnEffects = true`, converted `planDelete`, remote `remoteMissing`
    → `clearedAggregateIds` empty, events contain `'save:pending:plan-1'`.
- [ ] **Step 4: Run them to verify they fail.**
- [ ] **Step 5: Implement the store method** (Interfaces) and the queued
  pass-through.
- [ ] **Step 6: Implement the controller.** First statement of `_run`:
  `await _mutationStore().convertStaleCreateTombstones(userId: context.userId, organizationId: context.organizationId);`
  with a comment: under the per-context single-flight no remote call of this
  context is in flight here, so every `cancelling` row is stale (MG6; await
  point A0). In the `on PlanningMutationSyncException` block, after the C6
  evaluation and only when the context did not move: if
  `error.code == remoteMissing && mutation.resolvesCancelledCreate`, then
  `final purged = await _applyAcceptedEffects(context, mutation, remoteResponse: false);`
  (the D8 child purge; no rebases without a response) and, if `purged`,
  `clearMutation(..., expectedRevision: sendingRevision)`, otherwise
  `_resetToPending(context, mutation, sendingRevision)`; skip the
  failure-status write in both cases. Every other answer keeps today's path.
  The observer still hears the `remoteMissing` first (N3).
- [ ] **Step 7: Run the files, then the full suite.** Expected: green,
  including `planning_in_flight_create_cancellation_test.dart` and
  `planning_run_boundary_test.dart` unmodified.
- [ ] **Step 8: Prove the guards can fail:** (i) remove the run-start call →
  the stranded run tests fail; (ii) base `b` instead of `b + 1` → the item
  base tests fail; (iii) close every `remoteMissing` regardless of the marker
  → `'a user-recorded delete answered not_found stays visible (D9)'` fails;
  (iv) evaluate the close before C6 → the context-change test fails;
  (v) clear even when the purge failed → the purge-failure test fails.
- [ ] **Step 9: Commit.**
  `fix(planning): resolve stranded create tombstones at run start (MG6)`

### Task 4: A stale song tombstone becomes a pending delete at run start (MG7)

**Files:**
- Modify: `song_mutation_sync_types.dart` (interface method with a doc
  comment), `drift_song_mutation_store.dart`,
  `song_mutation_sync_controller.dart` (`_runSync` start)
- Modify (mechanical): every `SongMutationStore` test double (9 files; list
  with `grep -rln "implements SongMutationStore\|, SongMutationStore" apps/lyron_app/test`)
  gets a no-op; the one in `song_mutation_sync_controller_test.dart` also
  records `runCalls` (Step 1)
- Create: `test/offline/adversarial/song_stranded_tombstone_test.dart`
  (copy the `_TestEnv` shape of `song_in_flight_create_cancellation_test.dart`;
  a scripted `SongMutationRemoteRepository` recording every `syncSong`
  record and answering from a callback)

**Interfaces:**
- Produces: `DriftSongMutationStore.convertStaleSongCreateTombstones` reads the
  context's `cancelling` rows through
  `_songCatalogStore.readSongMutations(userId:, organizationId:, syncStatuses: const [SongSyncStatus.cancelling])`
  and resolves each with
  `_songCatalogStore.resolveCancelledSongCreate(created: true, acceptedVersion: 1)`
  (`create_song` inserts version 1; the store's existing D3 branch writes
  `pendingDelete` with that base, through its own recovery boundary).

- [ ] **Step 1: Write the failing tests** (strand a song: `service.createSong`,
  `mutationStore.markCreateSending(expectedRevision: <localRevision>)`,
  `service.deleteSong` → `cancelling`):
  - `'a stranded song tombstone whose create committed is deleted by the next run'`:
    the remote returns success for the delete → the sent record has
    `syncStatus == pendingDelete` and `baseVersion == 1`; `readById` is null
    afterwards.
  - `'a stranded song tombstone whose create never committed is removed on remoteDeleted'`:
    remote throws `SongMutationSyncException(remoteDeleted)` → `readById` null.
  - `'a connectivity failure keeps the converted pendingDelete'`.
  - `'a conflict ends conflict'`: remote throws `conflict` → row `conflict`.
  - Review Focus 5: `'a song tombstone of another context is untouched'`:
    strand in `org-2`, run `org-1` → the `org-2` row is still `cancelling`,
    zero remote calls.
  - In `song_mutation_sync_controller_test.dart`:
    `'a sync run converts stale song tombstones first'`: the fake appends
    `'convert'` / `'readPending'` to a new `List<String> runCalls`; expect
    `runCalls.take(2)` equals `['convert', 'readPending']`.
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement** the store method and, as the first statement of
  `_runSync`, `await _store.convertStaleSongCreateTombstones(userId: context.userId, organizationId: context.organizationId);`
  with the MG7 comment (single-flight, so every `cancelling` row is stale; no
  marker needed because a `remoteDeleted` answer to a `pendingDelete`
  already deletes the local row).
- [ ] **Step 4: Run the files, then the full suite.** Expected: green,
  including `song_in_flight_create_cancellation_test.dart` and
  `song_tombstone_resolution_atomicity_test.dart` unmodified.
- [ ] **Step 5: Prove the guard can fail:** remove the run-start call → the
  stranded tests fail; pass `acceptedVersion: 2` → the base assertion fails.
- [ ] **Step 6: Commit.**
  `fix(sync): resolve stranded song create tombstones at run start (MG7)`

### Task 5: Retry rebases only from a visible conflict (MG8)

**Files:**
- Modify: `drift_planning_mutation_store.dart` (`retryMutation`,
  `_currentBaseVersionFor`)
- Test: `planning_mutation_store_test.dart`; create
  `test/offline/adversarial/planning_retry_rebase_test.dart` (real stores,
  `seedPlanningProjection`, `ScriptedPlanningRemote`)

- [ ] **Step 1: Write the failing store tests**, group `'retry rebase (MG8)'`
  (projection re-seeded with plan-1 v5, session-1 v5 through
  `replaceActiveProjection`):
  - `'a conflicted session rename is rebased onto the projected session version'`:
    `recordSessionRename` base 2 → `saveSyncAttemptResult(conflict)` →
    `retryMutation` → `baseVersion 5`, `pending`.
  - `'a non-conflict retry of a value-overwriting kind keeps its base'`: for
    `planEdit` (base 3), `sessionRename` (base 2), `sessionReorder` (base 3),
    `sessionItemReorder` (base 2), each from `failedDependency` and from
    `pending` with `errorCode: connectivityFailure` → base unchanged,
    `pending`.
  - `'a key edit retried from a non-conflict status keeps its base (PS16, MG13)'`.
  - `'creates and sessionItemDelete still rebase from any status'`:
    `sessionItemDelete` base 2 from `failedDependency` → 5;
    `sessionCreate` from `failedDependency` → the projected plan version.
- [ ] **Step 2: Write the failing run test** in `planning_retry_rebase_test.dart`:
  `'a rename that failed on connectivity is resent with its original base and surfaces a foreign rename as a conflict'`:
  call 1 throws `connectivityFailure`; re-seed session-1 v5; the remote
  answers `conflict` when `record.baseVersion != 5`; `retryMutation` → call 2
  `baseVersion 2`, row `conflict`; `retryMutation` again (Keep mine) → call 3
  `baseVersion 5`, accepted, no rows left.
- [ ] **Step 3: Run to verify they fail** (the rename conflict test: base
  stays 2; the non-conflict tests: bases move to 5).
- [ ] **Step 4: Implement.** In `retryMutation` replace the
  `isCascadeDelete || isKeyEdit` predicate with an exhaustive switch:
  `planDelete`, `sessionDelete`, `sessionItemKeyEdit`, `planEdit`,
  `sessionRename`, `sessionReorder`, `sessionItemReorder` → conflict-only;
  `planCreate`, `sessionCreate`, `sessionItemCreateSong`,
  `sessionItemDelete` → any status. Comment: ADR-038 decision 5 applied to
  every overwrite (MG8). In `_currentBaseVersionFor` resolve the session of a
  `sessionRename` by `aggregateId` like `sessionDelete`; update the PS16
  comment that calls this "the S5b session-rename defect".
- [ ] **Step 5: Run the files, then the full suite.** Expected: green,
  including `'retrying a conflicted plan edit refreshes the base version'`
  unmodified.
- [ ] **Step 6: Prove the guards can fail:** revert the rename lookup → the
  conflicted-rename tests fail; let `planEdit` rebase in any status → the
  non-conflict test fails.
- [ ] **Step 7: Commit.**
  `fix(planning): rebase a retry only from a visible conflict (MG8)`

### Task 6: Discarding a create discards what depends on it (MG9)

**Files:**
- Modify: `planning_mutation_sync_types.dart` (`discardMutation`, doc
  comment), `drift_planning_mutation_store.dart`,
  `budgeted_planning_mutation_store.dart`,
  `planning_mutation_sync_controller.dart` (`discardMutation`)
- Modify (mechanical): every `PlanningMutationStore` test double gets
  `discardMutation` that behaves like its `clearMutation` (the controller
  test fake adds the id to `clearedAggregateIds` and to a new
  `discardedAggregateIds`, so the existing discard tests stay unchanged)
- Test: `planning_mutation_store_test.dart`, `planning_mutation_sync_controller_test.dart`

**Interfaces:**
- Produces: `discardMutation` — one transaction: read the row (absent →
  `false`); delete it; when it is a create and its status is not `sending`,
  `accepted` or `cancelling`, apply exactly the D10 collapse effects the
  `record*Delete` collapse branches apply today:
  - `sessionItemCreateSong`: `_removeSessionItemFromPendingReorder` (when
    `sessionId` is set) and `_deleteKeyEditUnlessInFlight`;
  - `sessionCreate`: `_deletePendingMutationsForSession` and
    `_removeSessionFromPendingReorder` (when `planId` is set);
  - `planCreate`: `_deleteChildMutationsOfPlan(keepInFlight: false)`.
  Returns `true`; footprint callback after the transaction.
  `clearMutation` stays for the sync's revision-gated clears.

- [ ] **Step 1: Write the failing store tests**, group `'discardMutation (MG9)'`:
  - `'discarding a failed item create removes its key edit and its entry in the pending item reorder'`
    (create `failedDependency`; a pending key edit; a pending item reorder
    listing it and another item → the reorder keeps the other item only).
  - `'discarding a failed session create removes its item, key-edit and item-order rows and its entry in the pending session reorder'`.
  - `'discarding a failed plan create removes every child row of the plan'`.
  - `'discarding an in-flight create keeps its dependents'` (`sending` and
    `accepted`, each with a pending key edit / child row).
  - Review Focus 4: `'discarding a failed item create keeps a key edit that is in flight'`
    (key edit `sending`).
  - `'discarding a non-create row removes only that row'` (`planEdit`).
- [ ] **Step 2: Write the failing controller test**
  `'discardMutation goes through the store discard, then syncs'`:
  `store.discardedAggregateIds == ['plan-1']`, followed by the usual sync.
- [ ] **Step 3: Run to verify they fail.**
- [ ] **Step 4: Implement** the store method, the queued pass-through, and
  `PlanningMutationSyncController.discardMutation` calling
  `_mutationStore().discardMutation(...)` instead of `clearMutation`.
- [ ] **Step 5: Run the files, then the full suite.** Expected: green,
  including the existing controller discard tests unmodified.
- [ ] **Step 6: Prove the guards can fail:** discard through `clearMutation`
  → the dependents tests fail; drop the in-flight check → the in-flight test
  fails.
- [ ] **Step 7: Commit.**
  `fix(planning): discarding a create discards its dependents (MG9, R1)`

### Task 7: Documentation, final verification, review, PR

**Files:**
- Modify: `docs/specs/2026-10-21-planning-mutation-gaps.md`: status note (PR 2
  implemented, PR number); I7 and Acceptance no longer except F1; MG4's
  "A failed advance … swallowed" and "does not cover the F1 race" bullets
  point to decision F1; the "Await Points" row A9 reads "reconcile and 1a in
  one transaction (F1)", row A0 is now implemented.
- Modify: `docs/architecture/decisions/ADR-038-plan-content-version.md`:
  2026-10-21 amendment status (item 2 implemented by PR 2); item 1's "One race
  stays … scheduled for PR 2" sentence replaced by a new item 3 (F1: the gate
  tables of the spec, the two user decisions, the planCreate/planEdit
  residual); the historical "Deferred" list entries for the stranded
  tombstones and the session rename get "(resolved by S5b PR 2)".
- Modify: `ADR-030-sync-snapshot-identity.md` ("Stranded Tombstone
  Follow-Up": implemented by PR 2; the not_found close purges first, then
  clears gated on the `sending` revision, and resets to `pending` when the
  purge failed).
- Modify: `ADR-028-local-storage-budget-and-eviction-policy.md` (D3 table:
  rows for `convertStaleCreateTombstones` and `discardMutation`, both never
  budget-admitted, write queue, no recovery; the sentence "Once the mutation
  budget is exhausted, `clearMutation` is the only way out" names
  `discardMutation`, the discard path since MG9).
- Modify: `docs/architecture/architecture.md`: the
  `PlanningMutationSyncController._run` paragraph (run-start conversion, the
  reconcile transaction, the not_found close, discard dependents) and the
  song sync paragraph (run-start conversion).
- Modify: `docs/plans/2026-10-01-delivery-roadmap.md` (status note and S5b
  row: PR 2 state).
- Delete: `docs/deferred/2026-09-30-stranded-create-tombstones.md`,
  `docs/deferred/2026-09-30-session-rename-retry-never-rebases.md`,
  `docs/deferred/2026-10-22-content-version-ahead-of-content.md`.
- Modify: `docs/deferred/2026-10-14-key-edit-residuals.md` (R1 section
  removed, triage line updated); any living doc that
  `grep -rn "stranded-create-tombstones\|session-rename-retry-never-rebases\|content-version-ahead-of-content\|advanceSyncedPlanContentVersion\|advanceAcceptedPlanContentVersion" docs apps/lyron_app/lib`
  still points at (historical specs and plans keep their text).

- [ ] **Step 1: Write the doc changes above.**
- [ ] **Step 2: Final verification.**
  `./scripts/verify.sh --skip-migrations --skip-backend-write-contracts` and
  `cd apps/lyron_app && flutter analyze && flutter test`. Expected: all green.
- [ ] **Step 3: Whole-diff adversarial review** (one fresh reviewer, Opus,
  effort xhigh, caveman ultra) of `git diff main...HEAD`, asked to disprove:
  "After this diff, no interleaving of pulls, folds, user deletes, context
  changes, crashes (a run ending at any await) and backend answers (accepted,
  no-op, conflict, `*_not_found`, connectivity) can (1) leave a projection
  whose `contentVersion` claims content it does not hold, or advance it from
  a value the client's own write did not return; (2) leave a `cancelling` row
  that the next run of its context does not convert, in either domain;
  (3) clear a delete without a visible state unless it is tombstone-origin,
  answered `*_not_found`, in the run's unmoved context, after its child purge
  succeeded; (4) rebase on Retry any row other than a create or a
  `sessionItemDelete` whose status is not `conflict`; (5) after discarding a
  create that was not in flight, leave a dependent row that can only fail, or
  remove a dependent of an in-flight create." The reviewer re-runs every
  "prove the guard can fail" step of Tasks 1–6 and quotes the failures.
  Spot-check the reviewer's file:line citations against the live files
  before acting. Fix substantive findings with a red test first; re-run the
  full suite.
- [ ] **Step 4: Commit the docs.**
  `docs(s5b): record PR 2 (rows that never resolve, F1) in the spec, ADRs and deferred entries`
- [ ] **Step 5: Push and open the PR** to `main` titled
  `fix(planning): rows that never resolve and the F1 reconcile race (S5b PR 2)`,
  the body listing MG6–MG9 and F1, the schema 9 migration, the residual
  (decision F1's planCreate/planEdit re-insert), the two user decisions of
  the F1 gate, and "no backend change"; end it with the attribution line.
  Bind it with the PR tools, wait for green CI, and leave the merge to the
  user.

## Execution Notes

Deviations ruled during execution go here; the code and the spec are
authoritative where they differ from the plan text.

### Pre-execution rulings (2026-10-27, user)

- **E1 (Tasks 3, 4, 7). A failed run-start conversion never stops the run.**
  In `PlanningMutationSyncController._run` and
  `SongMutationSyncController._runSync` the conversion call is wrapped in
  `try { … } on Exception { }` (an `Error` still propagates); the rows stay
  `cancelling` and the next run retries the conversion. Why: the conversion
  has no recovery boundary, and an exception escaping `_run` reaches
  `PlanningWriteService` through `syncScheduler` (try/finally, no catch), so
  an unrelated new write would report failure; on the song side the outbox
  would stop. Tests: the planning controller test's fake store gets
  `bool throwOnConvert = false` (throws `Exception('convert')`), pinned by
  `'a failed tombstone conversion does not stop the run'` (pending
  candidates are still sent); the same test in
  `song_mutation_sync_controller_test.dart`. Guard proof: remove the catch →
  each fails. Task 7: spec MG6/MG7 and the "Await Points" row A0 say the
  conversion is best-effort.
- **E2 (Task 7). Two more living docs.**
  `docs/architecture/state-machines.md`: the conflict-only retry rebase now
  covers `planEdit`, `sessionRename`, `sessionReorder`, `sessionItemReorder`
  and the key edit besides the cascade deletes; discarding a create removes
  its dependents unless the create is in flight; a stale `cancelling` row is
  converted at the next run start, planning and song.
  `docs/testing/testing-strategy.md`: one entry for
  `planning_stranded_tombstone_test`, `song_stranded_tombstone_test` and
  `planning_retry_rebase_test`.
- **E3 (Tasks 3, 5). Red at a "verify they fail" step.** A test that fails
  only because it does not compile yet counts as red.
  `'a user-recorded delete answered not_found stays visible (D9)'` and
  `'a not_found answered after a context change resets the converted delete
  instead of closing it'` pin behavior the current code already has; their
  red is guard proofs (iii) and (iv) of Task 3. In Task 5,
  `'creates and sessionItemDelete still rebase from any status'` and the
  PS16 key-edit test also pass on the current code. None of these is a STOP.
- **E4 (Task 1, STOP 2, Task 7). No test for STOP 2's last clause.** A
  guarded inner write retried inside the outer transaction has no planned
  trigger; no test is added for it. Task 7 records in ADR-028 D8: guarded
  writes inside `applyAcceptedWrite` run in savepoints, a recovery retry runs
  in a fresh savepoint, and if SQLite aborts the outer transaction the
  exception propagates and the rows stay `accepted` (fail-safe, resumed by
  the next run).
- **E5 (Task 1, STOP 3). Guard proof (iii) relaxes both contiguity checks.**
  The rule-1a UPDATE keeps its `WHERE content_version = R - 1` predicate, so
  relaxing only the outer `current == accepted - 1` to `current < accepted`
  changes no behavior (the UPDATE matches no row) and no test can catch it.
  Proof (iii) instead relaxes the outer condition and the `WHERE` predicate
  together; `'applies without advancing below R - 1'` and
  `'applyAcceptedWrite advances only a contiguous value'` then fail
  (`Expected: <4> Actual: <6>`). The code stays as planned: the outer check
  keeps the decision on the gate read C (the approved design), guards
  `owner!`, and is equivalent to the predicate today because no
  `bumpsPlanContent` arm writes the plan's `contentVersion`. Reviewers re-run
  (iii) in this form.
