# Planning Mutation Gaps, PR 1 (Context and Run Boundaries) Implementation Plan

> Status: Implemented (2026-10-22, PR #97). Covers PR 1 of
> `docs/specs/2026-10-21-planning-mutation-gaps.md` only (MG1–MG5 and their
> MG13 rows). PR 2 (`fix/planning-unresolved-rows`, MG6–MG9) and PR 3
> (`fix/purge-and-pull-guards`, MG10–MG12) get their own plans after this PR
> merges.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Planning work survives an organization switch, a sync run never
sends or judges a row after its context moved, rule 1a can never leave a
projection at R without the write, and an after-write refresh only counts
when it stored a pull that started after the write.

**Architecture:** One synchronous same-context predicate replaces the async
reconcile guard and is checked at C1–C6 inside
`PlanningMutationSyncController._run` (and the same shape in
`SongMutationSyncController._runSync`). Rule 1a leaves
`applyAcceptedWriteEffects` and becomes its own store call made only after a
successful batch-end reconcile. `PlanningSyncController` numbers its pulls,
and a new `refreshPlanningAfterWrite(context)` reports whether a pull for
that context, started after the request, was stored. The organization
switch stops deleting, and `deletePlanningData` is removed.

**Tech Stack:** Flutter/Dart, Riverpod, Drift (no schema change), the
existing planning and song sync stacks. No backend change.

**Spec:** `docs/specs/2026-10-21-planning-mutation-gaps.md` (MG1–MG5, MG13,
MG14, "Await Points in `_run`"). Also ADR-019, ADR-030 (D2/D3, fourth review
round), ADR-035 (2026-10-21 amendment, item 1), ADR-038 (decision 4, D7 rules,
2026-10-21 amendment, item 1), the plan-delete spec
`docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (I3, I7, D7).

## Global Constraints

- Branch: `fix/planning-mutation-gaps` (exists; holds the S5b spec and this
  plan). Never commit to `main`.
- No backend change, no migration, no Drift schema change in this PR.
- Planning same-context predicate: the type
  `typedef PlanningRunContextGuard = bool Function(ActivePlanningReadContext context);`
  replaces `PlanningAcceptedMutationGuard` (async). The controller parameter is
  `required PlanningRunContextGuard isRunContextActive` (it replaces
  `shouldReconcileAcceptedMutation`). Production answers it synchronously from
  `ref.read(activePlanningContextProvider)` (userId and organizationId both
  equal).
- Planning refresh trigger: `typedef PlanningRefreshTrigger = Future<bool> Function(ActivePlanningReadContext context);`
  Production wires it to `PlanningSyncController.refreshPlanningAfterWrite`.
- Song predicate: `typedef SongRunContextGuard = bool Function(SongMutationContext context);`,
  `SongMutationSyncController` parameter `required SongRunContextGuard isContextActive`.
  Production answers it from `ref.read(activeCatalogContextProvider)`.
- The stop of a run reports, through `onMutationFailure`, a
  `PlanningMutationSyncException(PlanningMutationSyncErrorCode.connectivityFailure)`
  for every candidate it leaves unsent, the C2/C6 row included.
- A reset written by a stop is `saveSyncAttemptResult(syncStatus: pending,`
  `expectedRevision: <the sending revision>)` with no error code (planning) and
  `saveSyncAttemptResult(syncStatus: SongSyncStatus.pendingCreate,`
  `expectedRevision: <the sending revision>)` (song creates only).
- New store method: `Future<void> advanceAcceptedPlanContentVersion({required String userId, required String organizationId, required PlanningMutationRecord accepted});`
  on `PlanningMutationStore`. It never grows the store: queued in
  `BudgetedPlanningMutationStore` like `applyAcceptedWriteEffects`, no budget,
  no recovery boundary.
- New `PlanningSyncController` API: `Future<bool> refreshPlanningAfterWrite(ActivePlanningReadContext context)`.
  `refreshPlanning()` keeps its signature and behavior for every other caller.
- `PlanningLocalStore.deletePlanningData` is removed (interface, Drift
  implementation, every test double).
- Existing tests must pass unmodified, except: (a) constructor and fake
  signature migrations forced by the type changes above (change nothing
  else in such a test); (b) the tests this plan names as rewritten; (c) an
  exact `events` / call-order list in a refresh-failed-branch test that now
  also shows the separate advance call (add the entry, change nothing else).
- Every task's verification: `cd apps/lyron_app && flutter analyze && flutter test`
  (the full suite, never a subdirectory). A focused run while iterating is
  fine, but a task is done only on the full run.
- Code, comments, commits and docs in English. Subagent reports in caveman
  ultra (terse; identifiers, file:line and code exact).

## Review Focus

Inputs a naive implementation gets wrong; each has a pinning test in the
named task.

1. A context that moves and comes back before the next check (A → B → A):
   the run continues for A, with A's rows, and nothing is reset (Task 3).
2. A sign-out purge landing inside a run: no gated write, reconcile or
   advance writes the purged user's projection or rows back (Task 5).
3. A retry pressed in a context that has just moved: the retry throws a
   connectivity failure instead of returning as if it had worked (Task 3).
4. After a switch, the previous organization's rows still count for the
   sign-out warning (`countPlanningPendingWork` is user-wide) (Task 2).
5. After a switch whose first refresh failed, an offline cold start with the
   identity's new organization shows nothing of the previous organization
   (Task 2).

## STOP-and-report conditions

Stop, report what you found and wait, if:

1. An existing test fails for a reason other than (a)–(c) of the Global
   Constraints, in particular one that observes the projection's
   `contentVersion` between the RPC response and the batch end, or one that
   pins the boundary delete beyond the two tests Task 2 names.
2. Removing `deletePlanningData` reveals a production caller other than
   `PlanningSyncController.handleActiveContextChanged`.
3. A "prove the guard can fail" step does not fail.
4. C2 cannot be placed with no `await` between the check and the
   `syncMutation` / `syncSong` call.
5. Any step seems to need a backend, RPC or Drift schema change.
6. The full suite shows a failure in an area this plan does not touch.
7. `flutter analyze` reports a warning you cannot fix locally.

## File Structure

- Modify `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`:
  typedefs, constructor, C1–C6 in `_run`, the batch-end order (MG4), the
  observer on a stop.
- Modify `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart`:
  `PlanningMutationStore.advanceAcceptedPlanContentVersion`; the
  `applyAcceptedWriteEffects` doc no longer mentions the projection.
- Modify `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`:
  rule 1a moves out of `applyAcceptedWriteEffects` into
  `advanceAcceptedPlanContentVersion`.
- Modify `apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart`:
  the queued pass-through.
- Modify `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`:
  MG1 (no boundary delete), pull numbering, `refreshPlanningAfterWrite`.
- Modify `apps/lyron_app/lib/src/application/planning_providers.dart`:
  the two closures of `planningMutationSyncControllerProvider`.
- Modify `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`:
  `deletePlanningData` removed.
- Modify `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`
  and `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`:
  MG3.
- Create `apps/lyron_app/test/offline/adversarial/planning_run_boundary_test.dart`
  (real Drift stores, scripted remote) and
  `apps/lyron_app/test/offline/adversarial/song_run_boundary_test.dart`
  (modeled on `song_in_flight_create_cancellation_test.dart`'s `_TestEnv` and
  `_GatedSongRemote`).
- Create `apps/lyron_app/test/support/planning_run_fixtures.dart`: move
  `seedProjection` and `_ScriptedPlanningRemote` out of
  `test/offline/adversarial/planning_cascade_delete_test.dart` as public
  `seedPlanningProjection(DriftPlanningLocalStore, {required int contentVersion, String organizationId = 'org-1'})`
  and `ScriptedPlanningRemote`; that test imports them.
- Docs (Task 7): the spec status note, ADR-035/ADR-038 amendment status,
  `docs/architecture/architecture.md`, the roadmap S5b row, the deferred
  entries.

---

### Task 1: Synchronous context guard and context-taking refresh trigger (no behavior change)

**Files:**
- Modify: `planning_mutation_sync_controller.dart` (typedefs, constructor,
  the one reconcile-guard call site at batch end)
- Modify: `planning_providers.dart` (`planningMutationSyncControllerProvider`)
- Modify: `song_mutation_sync_controller.dart` (constructor only),
  `song_library_providers.dart`
- Modify (mechanical): every `PlanningMutationSyncController(` and
  `SongMutationSyncController(` constructor call under `apps/lyron_app/test`
  (16 planning files, 9 song files; list them with
  `grep -rl "PlanningMutationSyncController(\|SongMutationSyncController(" apps/lyron_app/test`)

**Interfaces:**
- Produces: `PlanningRunContextGuard`, `PlanningRefreshTrigger` (context
  parameter), `SongRunContextGuard`, constructor parameters
  `isRunContextActive` / `isContextActive` (see Global Constraints).

- [ ] **Step 1: Change the planning typedefs and constructor.** Replace
  `PlanningAcceptedMutationGuard` with `PlanningRunContextGuard` and the
  `_shouldReconcileAcceptedMutation` field with `_isRunContextActive`. The
  batch-end call becomes `if (_isRunContextActive(context))` (no await).
  `_refreshPlanning()` becomes `_refreshPlanning(context)`.
- [ ] **Step 2: Wire the provider.** `isRunContextActive: (context) { final active = ref.read(activePlanningContextProvider); return active != null && active.userId == context.userId && active.organizationId == context.organizationId; }`
  and, for this task only, `refreshPlanning: (_) => ref.read(planningSyncControllerProvider).refreshPlanning()`
  (Task 6 switches it).
- [ ] **Step 3: Add the song parameter.** `required SongRunContextGuard isContextActive`
  stored but not yet read. Provider: the same comparison against
  `ref.read(activeCatalogContextProvider)`, mirroring its `refreshCatalog`
  closure.
- [ ] **Step 4: Migrate the test call sites.** `shouldReconcileAcceptedMutation: (_) async => X`
  becomes `isRunContextActive: (_) => X`; a closure with a body keeps its
  logic without `async`/`await`; `refreshPlanning: () async => X` becomes
  `refreshPlanning: (_) async => X`; every `SongMutationSyncController(` gets
  `isContextActive: (_) => true`. Change nothing else.
- [ ] **Step 5: Verify.** `cd apps/lyron_app && flutter analyze && flutter test`.
  Expected: no analyzer issue, full suite green with the same test count as
  the baseline taken before Step 1.
- [ ] **Step 6: Commit.**
  `refactor(sync): synchronous run-context guard for mutation sync runs`

### Task 2: An organization switch keeps the previous organization's data (MG1)

**Files:**
- Modify: `planning_sync_controller.dart` (`handleActiveContextChanged`,
  the `!sameBoundary` block)
- Modify: `planning_local_store.dart` (remove `deletePlanningData` from
  `PlanningLocalStore` and `DriftPlanningLocalStore`)
- Modify: every test double that overrides `deletePlanningData` (list with
  `grep -rln "deletePlanningData(" apps/lyron_app/test`), and
  `test/offline/planning/planning_local_store_test.dart` ("does not report a
  projection throw or true no-op": call `deletePlanningDataForUser(userId: 'missing-user')`
  instead)
- Test: `test/application/planning/planning_sync_controller_test.dart`

- [ ] **Step 1: Write the failing tests** in the `PlanningSyncController`
  group (reuse the group's `store`, `mutationStore`, `remoteRepository`,
  `session`, `lifecycle`):

```dart
test('an organization switch keeps the previous organization pending '
    'mutations and projection (MG1)', () async {
  final controller = PlanningSyncController(
    localStore: () => store,
    localDataLifecycle: lifecycle,
    remoteRepository: () => remoteRepository,
    authSessionReader: () => session,
  );
  const orgB = ActivePlanningReadContext(userId: 'user-1', organizationId: 'org-b');
  const orgA = ActivePlanningReadContext(userId: 'user-1', organizationId: 'org-a');
  await controller.handleActiveContextChanged(orgB); // default payload for org-b
  await mutationStore.recordPlanEdit(
    context: const PlanningMutationContext(userId: 'user-1', organizationId: 'org-b'),
    draft: const PlanningPlanEditMutationDraft(planId: 'plan-1', name: 'Unsynced rename'),
  );
  remoteRepository.payloadsByOrganizationId['org-a'] =
      Future<PlanningSyncPayload>(() => throw Exception('offline'));

  await controller.handleActiveContextChanged(orgA);

  expect(controller.state.organizationId, 'org-a');
  expect(controller.state.hasLocalPlanningData, isFalse);
  expect(await mutationStore.readAllMutations(userId: 'user-1', organizationId: 'org-b'), hasLength(1));
  expect(await store.readPlanSummaries(userId: 'user-1', organizationId: 'org-b'), isNotEmpty);
  expect(await store.readPlanSummaries(userId: 'user-1', organizationId: 'org-a'), isEmpty);
});
```

  Plus two Review Focus tests in the same group:
  - `'previous organization rows still count for the sign-out warning after a switch'`:
    the same setup, then
    `DriftPendingLocalWorkReader(planningDatabase: database, songDatabase: SongCatalogDatabase.inMemory()).countPlanningPendingWork(userId: 'user-1')`
    returns `1` (close the song database in the test).
  - `'an offline cold start after a switch shows nothing of the previous organization'`:
    the same setup, then a new controller with `authSessionReader: () => null`
    and `lastKnownIdentityReader: () => (userId: 'user-1', organizationId: 'org-a')`;
    `await controller2.handleOfflineAuthenticated()`; expect
    `controller2.state.organizationId` is `null` (org-a has no projection) and
    never `'org-b'`.

- [ ] **Step 2: Rewrite the two tests that pin the delete.**
  - `'switching to a new active organization that fails to refresh does not expose the previous organization projection'`:
    keep every line except the last expectation, which becomes `isNotEmpty`
    for org-1's plan summaries (its `hasLocalPlanningData` `isFalse`
    expectation already pins "shows nothing"). Rename it to
    `'switching to a new active organization that fails to refresh shows nothing of the previous organization and keeps its data'`.
  - `'stale previous-boundary delete is aborted when ownership returns to that organization'`:
    delete it and its `_BlockingBoundaryDeletePlanningLocalStore` double; the
    behavior it guarded (an aborted delete) no longer exists.
- [ ] **Step 3: Run them to verify they fail.**
  `cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart`.
  Expected: the MG1 test fails on `hasLength(1)` (`Actual: []`), the count
  test fails with `0`, the rewritten switch test fails on `isNotEmpty`. The
  cold-start test may already pass (it pins existing behavior).
- [ ] **Step 4: Implement.** In the `!sameBoundary` branch keep only
  `_invalidateRefreshGeneration()`; delete the `deletePlanningData` call and
  its `PlanningProjectionAbortedException` catch. Remove
  `deletePlanningData` from `PlanningLocalStore`, `DriftPlanningLocalStore`
  and the test doubles. Update the comment above the branch to cite MG1.
- [ ] **Step 5: Run the file, then the full suite.** Expected: green.
- [ ] **Step 6: Prove the guard can fail.** Temporarily restore a call that
  deletes the previous organization's mutation rows in the `!sameBoundary`
  branch (e.g. through a raw delete on the store's database in a scratch
  edit); the MG1 test and the count test fail; revert.
- [ ] **Step 7: Commit.**
  `fix(planning): keep the previous organization's planning data on a switch (MG1)`

### Task 3: A planning sync run stops when its context moves (MG2)

**Files:**
- Modify: `planning_mutation_sync_controller.dart` (`_run`)
- Test: `test/application/planning/planning_mutation_sync_controller_test.dart`

**Interfaces:**
- Consumes: `isRunContextActive` (Task 1).
- Produces: C1, C2, C6 in `_run`; a private
  `void _reportUnsent(Iterable<PlanningMutationRecord> records, PlanningMutationFailureObserver? observer)`
  that calls the observer with the connectivity exception for each.

- [ ] **Step 1: Extend the test fakes.** In `_FakePlanningMutationStore` add
  `void Function(String event)? onEvent` (called right after every
  `events.add`) and `final List<String> resolvedCreates = []` filled by
  `resolveCancelledCreate` as `'$created:$aggregateId'` (keep returning
  `false`). Add a `bool active = true` local per test and pass
  `isRunContextActive: (_) => active`.
- [ ] **Step 2: Write the failing tests** (names and assertions):
  - `'C1: a context change between candidates stops the run'`: two pending
    `planEdit` rows (`plan-1` orderKey 1, `plan-2` orderKey 2); the remote's
    `slowCompleter` blocks the first call; set `active = false` while blocked;
    release. Expect `repository.calls == 1`,
    `store.events` contains no `'save:sending:plan-2'`, and the plan-2 record
    is still `pending`.
  - `'C1: a context that moves and comes back before the next check keeps the run going'`:
    same setup, set `active = false` then `active = true` while blocked;
    expect `repository.calls == 2`.
  - `'C2: a context change during the sending write sends nothing and resets the row to pending'`:
    one pending `planCreate` (`plan-1`); `store.onEvent = (e) { if (e == 'save:sending:plan-1') active = false; }`.
    Expect `repository.calls == 0`, `store.events` equals
    `['save:sending:plan-1', 'save:pending:plan-1']`,
    `store.resolvedCreates == ['false:plan-1']`, and the record's `errorCode`
    is `null`.
  - `'C6: a failure answered after a context change is not written as a verdict'`:
    two pending rows; the remote has `error: PlanningMutationSyncException(PlanningMutationSyncErrorCode.authorizationDenied)`
    and a `slowCompleter`; set `active = false` while blocked; release.
    Expect `store.events` contains `'save:pending:plan-1'` and no
    `'save:failedAuthorization:plan-1'`, and `repository.calls == 1`.
  - `'a retry in a context that just moved throws a connectivity failure'`:
    one `conflict` row in `all`; `active = false`; expect
    `controller.retryMutation(ctx, aggregateType: 'plan', aggregateId: 'plan-1')`
    to throw a `PlanningMutationSyncException` with code
    `connectivityFailure`, and `repository.calls == 0`.
- [ ] **Step 3: Run them to verify they fail.** Expected: C1 sends 2, C2
  sends 1, C6 writes `failedAuthorization`, the retry returns normally.
- [ ] **Step 4: Implement in `_run`** (see the spec's MG2 table):
  - C1: first statement of the non-`accepted` candidate path, before the
    `sending` write: `if (!_isRunContextActive(context)) { _reportUnsent(candidates.skip(index), onMutationFailure); break; }`.
  - C2: after `sendingRevision != null`, as the last statement before
    `_remoteRepository().syncMutation(...)` (no await in between): on moved,
    for a cancellable create await `resolveCancelledCreate(created: false)`;
    if that returned `false`, write the gated `pending` reset with
    `expectedRevision: sendingRevision`; `_reportUnsent(candidates.skip(index), ...)`; `break`.
  - C6: in the `on PlanningMutationSyncException` block, after
    `onMutationFailure?.call(...)` and after the existing tombstone
    resolution: when moved, replace the failure-status write with the gated
    `pending` reset (only when `!resolvedTombstone`),
    `_reportUnsent(candidates.skip(index), ...)` (the current row too: its
    verdict was discarded, so a retry waiting on it must hear a connectivity
    failure last, not the discarded verdict), `break`. Add to the C6 test:
    a `retryMutation` of plan-1 under the same setup throws with code
    `connectivityFailure`.
  - The `accepted` candidate path needs no check (it sends nothing).
- [ ] **Step 5: Run the file, then the full suite.** Expected: green.
- [ ] **Step 6: Prove each guard can fail.** Remove C1, C2 and C6 one at a
  time; each removal fails its test; revert.
- [ ] **Step 7: Commit.**
  `fix(planning): stop a mutation sync run when its context moves (O2, MG2)`

### Task 4: A song sync run stops when its catalog context moves (MG3)

**Files:**
- Modify: `song_mutation_sync_controller.dart` (`_runSync`)
- Create: `test/offline/adversarial/song_run_boundary_test.dart` (C1, C6)
- Test: `test/application/song_library/song_mutation_sync_controller_test.dart`
  (C2, through an `onMarkCreateSending` hook added to `_FakeSongMutationStore`)

**Interfaces:**
- Consumes: `isContextActive` (Task 1); existing store methods
  `markCreateSending`, `resolveCancelledSongCreate`, `saveSyncAttemptResult`.

- [ ] **Step 1: Write the failing tests** against the real song store, with a
  gated remote (copy the `_TestEnv` / `_GatedSongRemote` shape from
  `song_in_flight_create_cancellation_test.dart`) and `var active = true`:
  - `'a catalog context change between songs stops the run'`: two
    `pendingUpdate` songs; gate the first call; `active = false`; release.
    Expect one remote call and the second song still `pendingUpdate`.
  - In `song_mutation_sync_controller_test.dart`,
    `'a context change after the sending marker sends nothing and resets the create'`:
    one `pendingCreate` song in `_FakeSongMutationStore`; its new
    `void Function()? onMarkCreateSending` hook (called after the fake's
    marker write) sets `active = false`. Expect zero remote calls, a
    `resolveCancelledSongCreate(created: false)` call, and a
    `saveSyncAttemptResult` with `SongSyncStatus.pendingCreate` (not
    `sending`) as the last write.
  - `'a failure answered after a context change keeps the song pending'`:
    one `pendingUpdate` song; the remote throws
    `SongMutationSyncException(SongMutationSyncErrorCode.authorizationDenied)`
    after the gate; `active = false` while gated. Expect the row still
    `pendingUpdate`, not `conflict`.
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement in `_runSync`:** C1 at the top of each iteration
  (before `markCreateSending` for a create); C2 synchronously before
  `_remoteRepository.syncSong(...)`: for a create, `resolveCancelledSongCreate(created: false)`
  and, if not resolved, `saveSyncAttemptResult(syncStatus: SongSyncStatus.pendingCreate, expectedRevision: expectedRevision)`;
  `break`. C6 first in the `on SongMutationSyncException` block, before the
  `remoteDeleted`/`pendingDelete` branch: when moved, for a create resolve the
  tombstone as not created and otherwise write the `pendingCreate` reset; for
  a non-create write nothing; `break`.
- [ ] **Step 4: Run the file, then the full suite.** Expected: green.
- [ ] **Step 5: Prove each guard can fail** (remove each check once; its test
  fails; revert).
- [ ] **Step 6: Commit.**
  `fix(sync): stop a song mutation sync run when its context moves (O2, MG3)`

### Task 5: Rule 1a only after a successful reconcile (MG4)

**Files:**
- Modify: `planning_mutation_sync_types.dart`, `drift_planning_mutation_store.dart`,
  `budgeted_planning_mutation_store.dart`, every `PlanningMutationStore` test
  double (14 files; `grep -rln "implements PlanningMutationStore" apps/lyron_app/test`)
  gets a no-op `advanceAcceptedPlanContentVersion` (the
  `_FakePlanningMutationStore` one records `'advance:${accepted.aggregateId}'`)
- Modify: `planning_mutation_sync_controller.dart` (batch end)
- Create: `test/support/planning_run_fixtures.dart` (the moved helpers)
- Create: `test/offline/adversarial/planning_run_boundary_test.dart`
- Test: `test/offline/planning/planning_mutation_store_test.dart`

**Interfaces:**
- Produces: `PlanningMutationStore.advanceAcceptedPlanContentVersion` (Global
  Constraints). It calls `PlanningLocalStore.advanceSyncedPlanContentVersion`
  with `planId` = the record's `aggregateId` for a plan kind
  (`kind.aggregateType == 'plan'`) and `accepted.planId` otherwise (the moved
  rule-1a block, verbatim), and
  `acceptedContentVersion = accepted.acceptedPlanContentVersion`, and does
  nothing when `!accepted.kind.bumpsPlanContent`, the plan id is `null` or
  the value is `null` (the PS15 own-write gate already nulls it in the
  repository mapping).
- `applyAcceptedWriteEffects` keeps its signature; it no longer touches the
  projection.

- [ ] **Step 1: Write the failing store test** in
  `planning_mutation_store_test.dart`: `'applyAcceptedWriteEffects no longer advances the projection content version (MG4)'`:
  projection plan at content version 3; call `applyAcceptedWriteEffects` with
  an accepted `sessionRename` carrying `acceptedPlanContentVersion: 4` and
  `remoteResponse: true`; expect the projection plan still at 3. Then call
  `advanceAcceptedPlanContentVersion` with the same record; expect 4.
- [ ] **Step 2: Write the failing adversarial tests** in
  `planning_run_boundary_test.dart` (real `DriftPlanningLocalStore` and
  `DriftPlanningMutationStore`, `seedPlanningProjection(localStore, contentVersion: 3)`,
  `PlanningMutationReconciler` unless stated, `refreshPlanning: (_) async => false`,
  `var active = true`, `isRunContextActive: (_) => active`):
  - `'a context switch before the batch end leaves the old projection behind its content, never ahead'`:
    a pending `sessionRename` of `session-1` (base 2); the scripted remote sets
    `active = false` and returns `record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4)`.
    Expect plan-1's projection `contentVersion == 3`, session-1's projected
    name unchanged, and no mutation rows left.
  - `'a context switch before the batch end skips the refresh of the new context'`:
    the same rename and remote, with
    `refreshPlanning: (_) async { refreshCalls += 1; return true; }`. Expect
    `refreshCalls == 0` and plan-1's projection `contentVersion == 3`.
  - `'a reconcile failure leaves the projection content version untouched'`:
    the same rename, `active` stays true, `reconcileAcceptedMutation` throws
    `ReconcileFieldError('name', PlanningMutationKind.sessionRename)`. Expect
    `contentVersion == 3` and the row `failedDependency`.
  - `'a plan created and given a child in one batch still reaches content version 2'`:
    pending `planCreate` (`plan-new`) then `sessionCreate` under it; the
    remote answers the create with `acceptedPlanContentVersion: 1` and the
    session with `baseVersion: 1, acceptedPlanContentVersion: 2`. Expect
    plan-new's projection `contentVersion == 2`.
  - Review Focus 2, `'a sign-out purge inside a run writes nothing back'`:
    a pending `sessionRename`; the remote awaits
    `localStore.deletePlanningDataForUser(userId: 'user-1')` and sets
    `active = false` before returning the accepted record. Expect
    `readPlanDetail(planId: 'plan-1')` is `null` and `readAllMutations` is
    empty after the run.
- [ ] **Step 3: Run them to verify they fail.** Expected: the first and
  second tests see `contentVersion == 4`; the store test sees 4 after the
  effects call; the third and fourth may already pass (regression pins).
- [ ] **Step 4: Implement the store side.** Move the rule-1a block out of
  `DriftPlanningMutationStore.applyAcceptedWriteEffects` into
  `advanceAcceptedPlanContentVersion`; add the interface method and the
  queued pass-through; update the doc comments (rule 1a now lives only in the
  new method).
- [ ] **Step 5: Implement the controller side.** Before the batch-end
  refresh, C3: `final refreshed = _isRunContextActive(context) && await _refreshPlanning(context);`.
  In the refresh-failed branch, per record in `acceptedRecords` order: the
  effects call as today (unconditional); then
  `if (_isRunContextActive(context)) { await _reconcileAcceptedMutation(context, synced); if (remoteResponse && synced.kind.bumpsPlanContent && synced.acceptedPlanContentVersion != null) { await _advanceAcceptedContentVersion(context, synced); } }`
  inside the existing `try`/`on ReconcileFieldError`, so a throwing
  reconcile skips the advance. `_advanceAcceptedContentVersion` swallows an
  `Exception` like `_applyAcceptedEffects` (an `Error` propagates). The
  refreshed branch makes no advance call. Keep the D8 `effectsApplied` and the
  PS15 re-call logic exactly as they are.
- [ ] **Step 6: Move the helpers.** Create `test/support/planning_run_fixtures.dart`
  with `seedPlanningProjection` and `ScriptedPlanningRemote` (bodies moved
  verbatim from `planning_cascade_delete_test.dart`, `organizationId`
  parameterized) and make the cascade test import them.
- [ ] **Step 7: Run the files, then the full suite.** Expected: green. Any
  failing existing test whose only change is an extra `'advance:…'` entry is
  constraint (c); anything else is STOP condition 1. In particular
  `planning_session_item_key_sync_test.dart` ("… (rule 1a) when the
  post-sync refresh fails", the MG13 key-edit row) and
  `planning_cascade_delete_test.dart` (acceptance 4: a delete recorded
  mid-run is rebased by rule 1b) must pass unmodified.
- [ ] **Step 8: Prove the guards can fail.** (i) Call the advance before the
  reconcile: the reconcile-failure test fails. (ii) Call it outside the
  context check: the context-switch test fails. (iii) Put rule 1a back into
  `applyAcceptedWriteEffects`: the store test fails. Revert each.
- [ ] **Step 9: Commit.**
  `fix(planning): advance the plan content version only after a reconcile (MG4)`

### Task 6: An after-write refresh counts only a pull started after it (MG5)

**Files:**
- Modify: `planning_sync_controller.dart` (pull numbering,
  `refreshPlanningAfterWrite`)
- Modify: `planning_providers.dart` (the refresh closure)
- Test: `test/application/planning/planning_sync_controller_test.dart`,
  `test/offline/adversarial/planning_run_boundary_test.dart`

**Interfaces:**
- Produces: `refreshPlanningAfterWrite(ActivePlanningReadContext context) → Future<bool>`
  (Global Constraints). Private state: `int _pullSequence = 0;` and
  `({int sequence, String userId, String organizationId})? _lastStoredPull;`.

- [ ] **Step 1: Write the failing controller tests** (group setup; the
  controller established with `handleActiveContextChanged(ctx1, refresh: false)`
  where `ctx1 = (user-1, org-1)`):
  - `'an after-write refresh never coalesces onto a pull that started before it'`:
    `remoteRepository.nextPayload = blocked.future`; `final first = controller.refreshPlanning();`
    `final afterWrite = controller.refreshPlanningAfterWrite(ctx1);`
    `blocked.complete(_payloadFor('org-1', planId: 'plan-1'));`
    expect `await afterWrite` is `true`, `remoteRepository.fetchCallCount == 2`.
  - `'an after-write refresh whose queued pull never ran is not reported as refreshed'`:
    the same start, then `controller.handleCurrentUser('user-2')` before
    `blocked.complete(...)`; expect `await afterWrite` is `false`.
  - `'a pull stored for another context does not count for the requester'`:
    the same start, then
    `await controller.handleActiveContextChanged(const ActivePlanningReadContext(userId: 'user-1', organizationId: 'org-2'), refresh: false)`
    before releasing; expect `await afterWrite` is `false`.
  - `'an after-write refresh with no refresh in flight runs one pull and reports it'`:
    expect `true` and `fetchCallCount == 1`.
- [ ] **Step 2: Write the failing R3 adversarial test** in
  `planning_run_boundary_test.dart`:
  `'a key edit accepted while an older refresh is in flight ends with the returned item version in the projection'`:
  use a real `PlanningSyncController` over the same `DriftPlanningLocalStore`
  with a remote refresh double whose first payload is blocked and stale (item
  `version: 1`) and whose second payload carries the returned item
  `version: 2`; start `planningSync.refreshPlanning()` (blocked), then run the
  mutation sync of a pending `sessionItemKeyEdit` with
  `refreshPlanning: planningSync.refreshPlanningAfterWrite`; release the first
  payload. Expect the projected item `version == 2` and no mutation rows left.
- [ ] **Step 3: Run them to verify they fail** (the method does not exist
  yet; after a stub returning `refreshPlanning()`'s bool, the first, second,
  third and R3 tests fail).
- [ ] **Step 4: Implement.** In `_refreshPlanning`, right before
  `fetchPlanningSyncPayload`: `final pullNumber = ++_pullSequence;`; after a
  successful, non-stale `_replaceProjection`:
  `_lastStoredPull = (sequence: pullNumber, userId: userId, organizationId: organizationId);`.
  `refreshPlanningAfterWrite`: capture `startSequence = _pullSequence`; if
  `_refreshFuture != null` set `_refreshQueued = true`; `await refreshPlanning();`;
  return `_lastStoredPull` is not null, its sequence `> startSequence`, and it
  equals `context`. Provider: `refreshPlanning: (context) => ref.read(planningSyncControllerProvider).refreshPlanningAfterWrite(context)`.
- [ ] **Step 5: Run the files, then the full suite.** Expected: green.
- [ ] **Step 6: Prove the guards can fail.** (i) Drop the
  `_refreshQueued = true`: the never-coalesce and R3 tests fail. (ii) Return
  `_state.refreshStatus == PlanningRefreshStatus.idle` instead of the
  sequence check: the queued-never-ran and other-context tests fail. Revert.
- [ ] **Step 7: Commit.**
  `fix(planning): count an after-write refresh only for a pull started after it (R3, MG5)`

### Task 7: Documentation, final verification, review, PR

**Files:**
- Modify: `docs/specs/2026-10-21-planning-mutation-gaps.md` (status note:
  PR 1 implemented on `fix/planning-mutation-gaps`, PR number)
- Modify: `docs/architecture/decisions/ADR-035-local-data-purge-contract.md`
  and `ADR-038-plan-content-version.md` (amendment status: item implemented
  by PR 1)
- Modify: `docs/architecture/architecture.md`: the planning sentence that
  says it "purges the previous active organization data when the active
  organization changes" now says the previous organization's projection and
  pending mutations stay until a purge reason (MG1); check the reader-cache
  sentence above it against the code ("does not retain ... parallel retained
  organization catalogs") and correct it only if the catalog really keeps
  other organizations' snapshots; the `PlanningMutationSyncController._run`
  paragraph gains one sentence on the C1–C6 stop and on rule 1a after the
  reconcile
- Modify: `docs/plans/2026-10-01-delivery-roadmap.md` (S5b row: PR 1 state)
- Delete: `docs/deferred/2026-10-01-org-switch-drops-pending-planning-mutations.md`,
  `docs/deferred/2026-09-30-content-version-advance-on-context-switch.md`
- Modify: `docs/deferred/2026-10-05-gate-cross-user-leaks.md` (O2 narrowed to
  the token-binding residual of MG2, with `auth_http_client.dart:24`; header
  and "Trigger" lines updated), `docs/deferred/2026-10-14-key-edit-residuals.md`
  (R3 section removed, triage line updated)
- Create: `docs/deferred/2026-10-22-other-organization-pending-work.md`: while
  another organization is active, the previous organization's pending
  planning work is not shown in the header or the sync popup, only counted
  by the sign-out warning; trigger: an organization switcher, or a field
  report; options: a read-only "unsynced changes in another organization"
  line in the popup, or syncing a kept outbox in the background.
- Modify, where they repeat the old behavior: any other doc that `grep -rn "purges the previous\|deletePlanningData\b" docs`
  finds (historical specs and plans keep their text; only living docs change)

- [ ] **Step 1: Write the doc changes above.**
- [ ] **Step 2: Final verification.** `./scripts/verify.sh --skip-migrations --skip-backend-write-contracts`
  (no backend change in this PR) and `cd apps/lyron_app && flutter analyze && flutter test`.
  Expected: all green.
- [ ] **Step 3: Whole-diff adversarial review** (one fresh reviewer on the
  strongest model, caveman ultra) of `git diff main...HEAD`, asked to
  disprove: "After this diff, no interleaving of context changes, folds,
  deletes, refresh outcomes and reconcile failures during a planning or song
  sync run can (1) send a row after C2 failed, (2) write a terminal status
  for an answer received after the context moved, (3) leave a projection's
  `contentVersion` ahead of the content it holds, (4) report `refreshed` for a
  pull that started before the write or belongs to another context, or
  (5) delete or bury a pending row of an organization that is no longer
  active." Spot-check the reviewer's file:line citations against the live
  files before acting. Fix substantive findings with a red test first;
  re-run the full suite.
- [ ] **Step 4: Commit the docs.**
  `docs(s5b): record PR 1 (context and run boundaries) in the spec, ADRs and deferred entries`
- [ ] **Step 5: Push and open the PR** to `main` titled
  `fix(planning): context and run boundaries (S5b PR 1)`, the body listing
  MG1–MG5, the residuals (MG1 gap, MG2 token binding, MG4 invisible own
  write), and "no backend change"; end it with the attribution line. Bind it
  with the PR tools, wait for green CI, and leave the merge to the user.

## Execution Notes

Deviations from the plan above that were ruled during execution; the code and
the spec are authoritative where they differ from the plan text.

- **Task 3.** Two existing tests modelled "the context moved" with a guard
  that is false for the whole run. From MG2 on such a run sends nothing, so
  they flip the guard after the send instead:
  `planning_mutation_sync_controller_test.dart` 'accepted-write fallback is
  skipped when the active boundary changed' uses
  `isRunContextActive: (_) => repository.calls == 0`, and the C10 test in
  `planning_session_item_key_sync_test.dart` sets `reconcileAllowed = false`
  inside its refresh closure.
- **Task 4.** On the song side C1 and C2 coincide for an update and a delete
  (no `sending` marker, so no await between the two checks). An extra test,
  'a context that has already moved writes no sending marker for a create',
  pins C1 for creates (spec MG3).
- **Task 5.** Two store tests were rewritten because rule 1a left
  `applyAcceptedWriteEffects`: 'rule 1: a contiguous own child write
  rebases the pending plan delete…' and 'rule 1 is idempotent and ignores
  planEdit/planCreate responses'. The projection stays at the old content
  version after `applyAcceptedWriteEffects` and reaches the new one only after
  an explicit `advanceAcceptedPlanContentVersion`. The plan id is the moved
  block verbatim (plan kind: `aggregateId`; otherwise `accepted.planId`;
  skipped on `null`), not `accepted.planId ?? accepted.aggregateId`.
- **Task 6.** The test 'a pull stored for another context does not count for
  the requester' needs one `Duration.zero` delay, so that the first pull is
  blocked inside the fetch when the context switch lands. Without it, a single
  pull started after the switch's synchronous generation invalidation is
  stored for the original context, and `true` is the correct answer there.
