# Planning Mutation Sync Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the planning mutation sync loop exactly-once-safe, single-flight, batch-refreshed, and offline-honest, with failed edits kept visible — landing each fix on a testable extracted reconciler.

**Architecture:** First extract the inline reconcile closure (`providers.dart:387-504`) into a `PlanningMutationReconciler` class (behavior-preserving, characterization-locked). Then, on that clean surface: hoist refresh out of the per-mutation loop, add a durable `accepted` marker (no schema migration — free-text status column), add a controller-owned single-flight guard (controller becomes stateful), drop the connectivity gate from discard/retry, and surface non-`pending` actionable mutations in the read merge.

**Tech Stack:** Dart, Flutter, Riverpod, Drift. Spec: `docs/specs/2026-06-28-planning-mutation-sync-correctness.md`. Tests via `flutter test` from `apps/lyron_app`.

**Conventions:** All `flutter test` commands run from `apps/lyron_app`. Commit after each task. Findings referenced: `ARCH-1`, `LF-1/2/3/4/5/7`.

---

## File Structure

- `apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart` — **new**: extracted reconciler class (one method, injected deps, no `ref`).
- `apps/lyron_app/lib/src/application/providers.dart` — wire the class instead of the inline closure (currently `:387-504`).
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart` — batch refresh (LF-2), accepted marker (LF-1), single-flight (LF-3, const→stateful), offline discard/retry (LF-7).
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart` — add `PlanningMutationSyncStatus.accepted` + string mapping.
- `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart` — merge non-`pending` actionable mutations (LF-4); LF-5 blanking guard on visible `planEdit`.
- Tests under `apps/lyron_app/test/application/planning/`.

---

## Task 1: Extract `PlanningMutationReconciler` (ARCH-1, behavior-preserving)

**Files:**
- Read: `apps/lyron_app/lib/src/application/providers.dart:387-504` (current inline reconcile closure)
- Create: `apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart` (wire the class)
- Test: `apps/lyron_app/test/application/planning/planning_mutation_reconciler_test.dart`

- [ ] **Step 1: Characterization test BEFORE moving code.** Read the current closure body at `providers.dart:387-504`. Write a test that drives the *current* reconcile behavior for every `PlanningMutationKind` (`planCreate, planEdit, sessionCreate, sessionRename, sessionDelete, sessionReorder, sessionItemCreateSong, sessionItemDelete, sessionItemReorder`) through the existing provider wiring with an in-memory store, asserting the resulting projection rows. Name: `planning_mutation_reconciler_test.dart`, group `reconcile (characterization)`.

```dart
// One case per kind; assert projection equals expected after reconcile.
test('planEdit reconcile writes name/description/scheduledFor into projection', () async {
  // arrange: in-memory PlanningLocalStore + a planEdit PlanningMutationRecord
  // act: run reconcile (via current provider wiring, then via the new class in Step 4)
  // assert: store.readPlanDetail returns the edited fields
});
```

- [ ] **Step 2: Run characterization tests against current code.** Run: `flutter test test/application/planning/planning_mutation_reconciler_test.dart`. Expected: PASS (locks current behavior).

- [ ] **Step 3: Create the class.** Move the closure body verbatim into a class. It must take its dependencies as constructor parameters / method arguments — **not** capture the provider `ref` (the current closure at `providers.dart:387` captures `ref`). Signature mirrors the existing `PlanningAcceptedMutationReconciler` typedef (`planning_mutation_sync_controller.dart:8-12`): `Future<void> reconcile(ActivePlanningReadContext context, PlanningMutationRecord record)`.

```dart
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

class PlanningMutationReconciler {
  const PlanningMutationReconciler({required PlanningLocalStore Function() localStore})
      : _localStore = localStore;

  final PlanningLocalStore Function() _localStore;

  Future<void> reconcile(
    ActivePlanningReadContext context,
    PlanningMutationRecord record,
  ) async {
    // EXACT body moved from providers.dart:387-504, with `ref.read(planningLocalStoreProvider)`
    // replaced by `_localStore()`. Do not alter the switch logic in this task.
  }
}
```

- [ ] **Step 4: Wire the class in providers.dart.** Replace the inline `reconcileAcceptedMutation:` closure passed to `PlanningMutationSyncController` with `PlanningMutationReconciler(localStore: () => ref.read(planningLocalStoreProvider)).reconcile`. Delete the old inline closure body.

- [ ] **Step 5: Re-run characterization tests against extracted class.** Run: `flutter test test/application/planning/planning_mutation_reconciler_test.dart`. Expected: PASS (identical behavior).

- [ ] **Step 6: Verify no import cycle / no analyzer regressions.** Run: `flutter analyze lib/src/application/planning/planning_mutation_reconciler.dart lib/src/application/providers.dart`. Expected: no errors. (Graphify confirmed the reconciler is a leaf unit; depends only on store + types.)

- [ ] **Step 7: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart \
        apps/lyron_app/lib/src/application/providers.dart \
        apps/lyron_app/test/application/planning/planning_mutation_reconciler_test.dart
git commit -m "refactor(planning): extract PlanningMutationReconciler from providers closure (ARCH-1)"
```

---

## Task 2: LF-2 — hoist refresh out of the per-mutation loop

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart:35-85`
- Test: `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`

Current loop (`:41-56`) calls `await _refreshPlanning()` once **per mutation**.

- [ ] **Step 1: Write failing test — N mutations cause exactly one refresh.**

```dart
test('syncPendingMutations refreshes once for N accepted mutations', () async {
  // arrange: stub store with 3 pending mutations, remote.syncMutation returns accepted,
  //          a refresh counter
  // act: await controller.syncPendingMutations(context)
  // assert: refreshCount == 1 (was 3 before)
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart -p "refreshes once"`. Expected: FAIL (refreshCount == 3).

- [ ] **Step 3: Implement batch-then-refresh.** Restructure `syncPendingMutations`: iterate pending, `syncMutation` each, record per-mutation failures exactly as today (auth/dependency/conflict via `saveSyncAttemptResult`; connectivity failure still `break`s the loop), and accumulate the accepted records. After the loop, call `_refreshPlanning()` **once**. On refresh success, `clearMutation` each accepted record. On refresh failure, for each accepted record call `_reconcileAcceptedMutation(context, record)` (guarded by `_shouldReconcileAcceptedMutation`) then `clearMutation`.

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart`. Expected: PASS (including existing reconcile-fallback tests).

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart \
        apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart
git commit -m "perf(planning): collapse per-mutation refresh to one batch refresh (LF-2)"
```

---

## Task 3: LF-1 — durable `accepted` marker (exactly-once)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart:15-21,57-65,86-99`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
- Test: `apps/lyron_app/test/application/planning/planning_mutation_sync_types_test.dart`, `..._sync_controller_test.dart`

No migration needed — `syncStatus` is a free-text column (`drift_planning_mutation_store.dart:423`).

- [ ] **Step 1: Failing test — `accepted` round-trips through string mapping.**

```dart
test('accepted status maps to and from "accepted"', () {
  expect(PlanningMutationSyncStatus.accepted.value, 'accepted');
  expect(planningMutationSyncStatusFromValue('accepted'),
      PlanningMutationSyncStatus.accepted);
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/planning/planning_mutation_sync_types_test.dart`. Expected: FAIL (no enum value).

- [ ] **Step 3: Add the enum value + mapping.** In `planning_mutation_sync_types.dart`: add `accepted` to the enum (`:15-21`); add `PlanningMutationSyncStatus.accepted => 'accepted'` to `PlanningMutationSyncStatusX.value` (`:57-65`); add `'accepted' => PlanningMutationSyncStatus.accepted` to `planningMutationSyncStatusFromValue` (`:86-99`).

- [ ] **Step 4: Failing test — crash between accept and clear does not re-send.**

```dart
test('a mutation already marked accepted is reconciled/cleared, not re-sent', () async {
  // arrange: store has one mutation pre-marked syncStatus=accepted; remote.syncMutation throws if called
  // act: await controller.syncPendingMutations(context)
  // assert: remote.syncMutation NOT called; reconcile+clear happened; no conflict status set
});
```

- [ ] **Step 5: Run to verify it fails.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart -p "already marked accepted"`. Expected: FAIL (re-sends).

- [ ] **Step 6: Implement the marker.** In `syncPendingMutations`: read mutations needing send (status `pending`) AND mutations already `accepted` (use `readAllMutations` filtered, or a new `readActionableMutations`). For a `pending` mutation, immediately after `syncMutation` returns accepted call `saveSyncAttemptResult(syncStatus: PlanningMutationSyncStatus.accepted)` **before** the batch refresh/clear. For an already-`accepted` mutation, skip `syncMutation` and include it directly in the accepted set for reconcile/clear.

- [ ] **Step 7: Run to verify it passes.** Run: `flutter test test/application/planning/`. Expected: PASS.

- [ ] **Step 8: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart \
        apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart \
        apps/lyron_app/test/application/planning/
git commit -m "fix(planning): add accepted marker for exactly-once sync (LF-1)"
```

---

## Task 4: LF-3 — single-flight guard (controller becomes stateful)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart:16-33` (drop `const`)
- Modify: `apps/lyron_app/lib/src/application/providers.dart` (instantiation site, if `const`)
- Test: `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`

The class is `const` (`:17`), so it cannot hold a guard field — convert to a normal class.

- [ ] **Step 1: Failing test — concurrent calls coalesce into one run.**

```dart
test('concurrent syncPendingMutations calls do not double-send', () async {
  // arrange: remote.syncMutation counts calls, slow (Completer) so two calls overlap
  // act: final a = controller.syncPendingMutations(context);
  //      final b = controller.syncPendingMutations(context);
  //      await Future.wait([a, b]);
  // assert: each pending mutation sent exactly once (no duplicate syncMutation/clearMutation)
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart -p "do not double-send"`. Expected: FAIL (sends twice).

- [ ] **Step 3: Implement the guard.** Remove `const` from the constructor (`:17`). Add a field `Future<void>? _inFlight;`. Wrap the body: if `_inFlight != null` return it; else assign `_inFlight = _run(context)` and clear it in a `whenComplete`. Move the current body into a private `_run`.

```dart
Future<void> syncPendingMutations(ActivePlanningReadContext context) {
  final inFlight = _inFlight;
  if (inFlight != null) return inFlight;
  final run = _run(context).whenComplete(() => _inFlight = null);
  _inFlight = run;
  return run;
}
```

- [ ] **Step 4: Fix instantiation if needed.** In `providers.dart`, if the controller was built with `const`, drop it. Run: `flutter analyze`. Expected: no errors.

- [ ] **Step 5: Run to verify it passes.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart`. Expected: PASS.

- [ ] **Step 6: Regression — the four concurrent triggers.** Graphify identified the real concurrent callers: `UnifiedManualSyncController`, `UnifiedDiscardController`, `ForegroundSyncListener`, `OnlineTransitionDetector`. Add a test that fires two of these paths overlapping and asserts a single run. Run: `flutter test test/application/`. Expected: PASS.

- [ ] **Step 7: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart \
        apps/lyron_app/lib/src/application/providers.dart \
        apps/lyron_app/test/application/planning/
git commit -m "fix(planning): single-flight guard on syncPendingMutations (LF-3)"
```

---

## Task 5: LF-7 — offline discard/retry

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart:87-119`
- Test: `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`

Current `discardMutation`/`retryMutation` start with `if (!await _refreshPlanning()) return;` (`:92,109`) → no-op offline.

- [ ] **Step 1: Failing test — discard works offline.**

```dart
test('discardMutation clears local intent when refresh is unavailable', () async {
  // arrange: _refreshPlanning returns false (offline)
  // act: await controller.discardMutation(context, aggregateType: 'plan', aggregateId: id)
  // assert: store.clearMutation called for that aggregate
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart -p "clears local intent when refresh is unavailable"`. Expected: FAIL (returns early, no clear).

- [ ] **Step 3: Implement.** In `discardMutation`: remove the leading refresh gate; call `clearMutation` unconditionally; make the post-clear `syncPendingMutations` best-effort (do not depend on refresh). In `retryMutation`: remove the leading gate; `retryMutation` on the store, then best-effort `syncPendingMutations` (stays pending if offline).

- [ ] **Step 4: Run to verify it passes.** Run: `flutter test test/application/planning/planning_mutation_sync_controller_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart \
        apps/lyron_app/test/application/planning/
git commit -m "fix(planning): allow offline discard/retry of stuck mutations (LF-7)"
```

---

## Task 6: LF-4 — keep failed/conflict/accepted edits visible (+ LF-5 guard)

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart:103-115,135-148`
- Modify (maybe): `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart` (add `readActionableMutations` to `PlanningMutationStore`) + its Drift impl
- Test: `apps/lyron_app/test/application/planning/planning_local_read_repository_test.dart`

Today `_readPendingMutations` (`:103-115`) calls `readPendingMutations` (status `pending` only, `drift_planning_mutation_store.dart:423`), so `failed`/`conflict` edits vanish from the merge.

- [ ] **Step 1: Failing test — a failed planEdit stays in the merged plan.**

```dart
test('merge keeps a failed planEdit visible instead of reverting', () async {
  // arrange: projection has plan P; mutation store has a planEdit on P with syncStatus=failedDependency
  // act: final plans = await repo.listPlans();
  // assert: the returned plan reflects the edit (its edited name), not the server state
});
```

- [ ] **Step 2: Run to verify it fails.** Run: `flutter test test/application/planning/planning_local_read_repository_test.dart -p "keeps a failed planEdit visible"`. Expected: FAIL (reverts to server state).

- [ ] **Step 3: Add an actionable read.** Add `readActionableMutations({userId, organizationId})` to `PlanningMutationStore` (`planning_mutation_sync_types.dart:440-443` region) returning rows with status in `{pending, accepted, failedAuthorization, failedDependency, failedRemoteDelete, conflict}`. Implement in `drift_planning_mutation_store.dart` mirroring `readPendingMutations` but with an `isIn` filter on the status strings. Point `_readPendingMutations` in the read repo to the new method (rename it `_readActionableMutations`).

- [ ] **Step 4: LF-5 guard test — visible failed planEdit does not blank unset fields.**

```dart
test('a visible failed planEdit does not blank description/scheduledFor', () async {
  // arrange: plan P has description D and scheduledFor S; a planEdit mutation only changed the name,
  //          with description=null/scheduledFor=null in the record, status=conflict
  // act: final plans = await repo.listPlans();
  // assert: returned plan keeps description D and scheduledFor S (not blanked)
});
```

- [ ] **Step 5: Run to verify it fails.** Run: `flutter test test/application/planning/planning_local_read_repository_test.dart -p "does not blank"`. Expected: FAIL (merge at `:143-147` sets `description`/`scheduledFor` directly from the record → blanked).

- [ ] **Step 6: Implement the minimal LF-5 guard.** In `_mergePlanSummaries` `planEdit` branch (`:135-148`), change `description: mutation.description` → `description: mutation.description ?? existing.description` and `scheduledFor: mutation.scheduledFor` → `scheduledFor: mutation.scheduledFor ?? existing.scheduledFor` (mirroring how `name` already uses `?? existing.name`). Apply the same in the plan-detail merge path if present. (Full LF-5 fix remains deferred; this is the visible-edit guard only.)

- [ ] **Step 7: Run to verify it passes.** Run: `flutter test test/application/planning/planning_local_read_repository_test.dart`. Expected: PASS.

- [ ] **Step 8: Commit.**

```bash
git add apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart \
        apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart \
        apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart \
        apps/lyron_app/test/application/planning/planning_local_read_repository_test.dart
git commit -m "fix(planning): keep failed/conflict edits visible in main view (LF-4, LF-5 guard)"
```

---

## Task 7: Documentation

**Files:**
- Modify: `docs/architecture/architecture.md` (sync section)
- Modify: `docs/testing/testing-strategy.md`
- Create (if accepted-marker is durable): `docs/architecture/decisions/` ADR (relates to ADR-015, ADR-014)

- [ ] **Step 1: Update architecture sync section** to describe single-flight, batch-then-refresh, the `accepted` marker, offline discard/retry, and the actionable-merge.
- [ ] **Step 2: Update testing-strategy** to name the new sync-correctness regression coverage.
- [ ] **Step 3: Add/extend an ADR** for the accepted-marker exactly-once model.
- [ ] **Step 4: Commit.**

```bash
git add docs/architecture/architecture.md docs/testing/testing-strategy.md docs/architecture/decisions/
git commit -m "docs(planning): document sync correctness model (LF-1/2/3/4/7)"
```

---

## Final Verification

- [ ] Run the full planning suite: `flutter test test/application/planning/` — all green.
- [ ] Run `flutter analyze` — no new issues.
- [ ] Confirm characterization tests from Task 1 still pass (no behavior drift from later tasks).

---

## Self-Review Notes

- Spec coverage: Task 1↔Step 0, Task 2↔LF-2, Task 3↔LF-1, Task 4↔LF-3, Task 5↔LF-7, Task 6↔LF-4+LF-5 guard, Task 7↔docs. All spec sections covered.
- Type consistency: `readActionableMutations` defined in Task 6 and used only there; `PlanningMutationSyncStatus.accepted` defined Task 3, used Tasks 3 & 6; `_inFlight`/`_run` defined Task 4.
- No migration claim verified against `drift_planning_mutation_store.dart:423` (free-text status column).
