# Local-First Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an adversarial native test harness that proves the PR #55 offline/sync behaviour (ADR-019 exactly-once, ADR-020 non-destructive session) along failure/conflict/convergence paths, and fix every in-seam bug the harness exposes.

**Architecture:** Layered, native-only. Deterministic controller-fake unit tests carry fault injection, merge visibility, reconcile null-fields, migration, and two probes; integration tests against a local Supabase carry end-to-end relaunch and the two-device conflict matrix. Fixes land as `fix(...)` commits on the same branch.

**Tech Stack:** Dart / Flutter, `flutter_test`, Drift (native temp-file + in-memory), Riverpod, Supabase (local stack for integration).

---

## Spec Reference

`docs/specs/2026-06-29-local-first-validation.md`. Read it before starting. Findings: `LF-1`, `LF-2`, `LF-3`, `LF-4`, `LF-5`, `LF-6`, `LF-8`, `LF-T1`, `LF-T7` (full); `LF-T4`, `LF-T6` (probe + in-seam fix only).

## Pre-Verified Current State (read before writing tests — do not trust the 2026-06-22 review blindly)

The shipped code already addresses several findings. Each test below is labelled **VALIDATION** (expected green against current code, stands as a regression guard) or **FIX** (expected red, then made green by an in-seam change).

- `LF-1` planning crash-resend: durable `accepted` marker skip is implemented — `planning_mutation_sync_controller.dart:62-67`. → VALIDATION.
- `LF-2` planning partial-RPC + refresh-fail → reconcile: the `else` branch reconciles accepted records before clear — `planning_mutation_sync_controller.dart:116-138`. → VALIDATION.
- `LF-3` single-flight: planning HAS `_inFlight` coalescing (`planning_mutation_sync_controller.dart:35-43`); **song does NOT** (`song_mutation_sync_controller.dart` `syncPendingSongs` has no in-flight guard). → song = FIX.
- `LF-5` partial-edit blanking: merge already uses `?? existing` (`planning_local_read_repository.dart:143-148,211-216`). → VALIDATION.
- `LF-6` double-add same song: merge dedups by item id only (`planning_local_read_repository.dart:273`). → FIX.
- `LF-8` reconcile null-fields: `planning_mutation_reconciler.dart` coerces `?? ''`/`?? 0` for fields that must never be null on a create. → FIX.
- `LF-T6` clock: `planning_mutation_reconciler.dart:17` reads `DateTime.now().toUtc()` directly. → seam + probe.
- `LF-T7` catalog migration: `song_catalog_database.dart:32` declares `schemaVersion => 2` with **no** `MigrationStrategy`; planning has one (`planning_local_database.dart:33-61`). → FIX (defensive strategy) + test.

## File Structure

**New test support** (`apps/lyron_app/test/support/`):
- `fault_injecting_remote.dart` — configurable fake planning/song remote repos: accept-then-fail-refresh, crash-before-clear, concurrent-call counter, call-order log.
- `drift_relaunch.dart` — close + reopen a Drift temp-file database from the same file path.

**New tests** (`apps/lyron_app/test/`):
- `offline/adversarial/planning_fault_injection_test.dart` — LF-1/LF-2 (validation).
- `offline/adversarial/song_single_flight_test.dart` — LF-3 song (fix).
- `offline/adversarial/planning_merge_visibility_test.dart` — LF-4/LF-5 (validation), LF-6 (fix).
- `offline/adversarial/planning_reconcile_nullfield_test.dart` — LF-8 (fix).
- `offline/adversarial/planning_migration_test.dart` — LF-T7 planning (validation of v4→v5 with pending mutation).
- `offline/adversarial/song_catalog_migration_test.dart` — LF-T7 catalog (fix: strategy + reopen survival).
- `offline/adversarial/storage_pressure_probe_test.dart` — LF-T4 probe.
- `offline/adversarial/clock_skew_probe_test.dart` — LF-T6 probe.
- `integration/offline_edit_relaunch_sync_flow_test.dart` — scenario 1, skip-gated.
- `integration/two_device_conflict_matrix_test.dart` — scenario 2, skip-gated.

**Production fixes** (only as tests demand):
- `lib/src/application/song_library/song_mutation_sync_controller.dart` — single-flight guard (LF-3).
- `lib/src/application/planning/planning_local_read_repository.dart` — song-id dedup (LF-6).
- `lib/src/application/planning/planning_mutation_reconciler.dart` — null-field rejection (LF-8) + injectable clock (LF-T6 seam).
- `lib/src/offline/song_catalog/song_catalog_database.dart` — `MigrationStrategy` (LF-T7).

**Docs:**
- `docs/testing/testing-strategy.md`, `ADR-019`, `ADR-020`, `docs/architecture/repository-review-2026-06-22.md`.
- `docs/deferred/2026-06-29-web-offline-e2e.md`, `…-server-clock-anchor-lf-t6.md`, `…-storage-eviction-policy-lf-t4.md`.

## Conventions

- Run a single test file: `cd apps/lyron_app && flutter test test/<path> -r expanded`.
- Run all unit tests: `cd apps/lyron_app && flutter test`.
- Integration tests are **skip-gated** by `String.fromEnvironment('SUPABASE_URL'/'SUPABASE_ANON_KEY')` (pattern: `test/integration/local_first_authenticated_song_reader_flow_test.dart:25-26,132`). With no env they skip → CI stays green without a stack; run them with `--dart-define SUPABASE_URL=… --dart-define SUPABASE_ANON_KEY=…` against the local stack (`scripts/supabase-start.sh`).
- Reuse the existing record/context builders and fakes in `test/application/planning/planning_mutation_sync_controller_test.dart` (`_FakePlanningMutationStore`, `_FakePlanningMutationRemoteRepository`, and its `PlanningMutationRecord` construction helper) rather than re-deriving constructors. Read that file first; mirror its helpers into the shared support file.
- Each step is one action. Commit after each green task. Commit type reflects the change (`test:`, `fix:`, `docs:`), not the branch name.

---

## Phase 0 — Shared Test Support

### Task 1: Fault-injecting remote fake

**Files:**
- Create: `apps/lyron_app/test/support/fault_injecting_remote.dart`
- Read first: `test/application/planning/planning_mutation_sync_controller_test.dart:1041-1075` (existing `_FakePlanningMutationRemoteRepository`)

- [ ] **Step 1: Write the fake**

```dart
import 'dart:async';

import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

/// A planning remote repo that records call order and can be made to accept a
/// mutation but fail the subsequent refresh, simulating a partial RPC success
/// (LF-2) and a crash window before the local clear (LF-1).
class FaultInjectingPlanningRemote implements PlanningMutationRemoteRepository {
  FaultInjectingPlanningRemote({this.failAfterAccept = false});

  /// When true, [syncMutation] accepts (records the call) and returns normally,
  /// but the caller's refresh is expected to fail (configure the refresh trigger
  /// in the test). Used to drive the reconcile branch.
  final bool failAfterAccept;

  final List<String> syncedAggregateIds = [];
  int concurrentPeak = 0;
  int _inFlight = 0;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    _inFlight += 1;
    concurrentPeak = _inFlight > concurrentPeak ? _inFlight : concurrentPeak;
    await Future<void>.delayed(Duration.zero);
    syncedAggregateIds.add(record.aggregateId);
    _inFlight -= 1;
    return record;
  }
}
```

- [ ] **Step 2: Analyze**

Run: `cd apps/lyron_app && dart analyze test/support/fault_injecting_remote.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/support/fault_injecting_remote.dart
git commit -m "test(support): fault-injecting planning remote fake

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 2: Drift relaunch helper

**Files:**
- Create: `apps/lyron_app/test/support/drift_relaunch.dart`
- Read first: `test/integration/local_first_authenticated_song_reader_flow_test.dart:44-60` (temp-file open pattern)

- [ ] **Step 1: Write the helper**

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

/// Creates a temp directory + a sqlite file path for a relaunch-style test.
Future<File> createRelaunchDbFile(String name) async {
  final dir = await Directory.systemTemp.createTemp(name);
  return File(p.join(dir.path, '$name.sqlite'));
}

/// Opens a native executor over [file]. Call once per "launch"; close the
/// returned database, then call again on the same [file] to simulate relaunch.
NativeDatabase openRelaunchExecutor(File file) => NativeDatabase(file);
```

- [ ] **Step 2: Analyze**

Run: `cd apps/lyron_app && dart analyze test/support/drift_relaunch.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/support/drift_relaunch.dart
git commit -m "test(support): drift relaunch (close+reopen) helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 1 — Fault Injection (LF-1, LF-2, LF-3)

### Task 3: Planning crash + partial-refresh validation (LF-1, LF-2)

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/planning_fault_injection_test.dart`
- Under test: `lib/src/application/planning/planning_mutation_sync_controller.dart`
- Read first: `test/application/planning/planning_mutation_sync_controller_test.dart` (record/context helpers + `_FakePlanningMutationStore`)

- [ ] **Step 1: Write the failing test — LF-1 crash leaves accepted marker, next run does not re-send**

Mirror the existing controller test's setup. Two assertions:

```dart
// Arrange: one mutation already persisted with syncStatus == accepted
// (simulating a crash after backend-accept, before clearMutation).
// Act: run syncPendingMutations once.
// Assert: the remote was NOT called for the accepted record (no double-send),
// it was reconciled, and then cleared.
test('accepted-but-uncleared mutation is reconciled, not re-sent (LF-1)', () async {
  final remote = FaultInjectingPlanningRemote();
  final store = _FakePlanningMutationStore(
    pending: const [],
    all: [/* one record with syncStatus: accepted — use the test's record helper */],
  );
  final controller = PlanningMutationSyncController(
    mutationStore: () => store,
    remoteRepository: () => remote,
    refreshPlanning: () async => false, // force the reconcile branch
    reconcileAcceptedMutation: (_, __) async {},
    shouldReconcileAcceptedMutation: (_) async => true,
  );

  await controller.syncPendingMutations(/* context helper */);

  expect(remote.syncedAggregateIds, isEmpty); // never re-sent
  expect(store.clearedAggregateIds, hasLength(1)); // cleared after reconcile
});
```

- [ ] **Step 2: Run — expected PASS (validation of shipped behaviour)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_fault_injection_test.dart -r expanded`
Expected: PASS. If it FAILS, LF-1 regressed — fix the controller's accepted-skip (`:62-67`) before continuing.

- [ ] **Step 3: Add the LF-2 case — partial accept then refresh failure reconciles before clear**

```dart
test('refresh failure after accept reconciles each accepted record before clear (LF-2)', () async {
  final reconciled = <String>[];
  final store = _FakePlanningMutationStore(pending: [/* one pending record */]);
  final controller = PlanningMutationSyncController(
    mutationStore: () => store,
    remoteRepository: () => FaultInjectingPlanningRemote(),
    refreshPlanning: () async => false, // refresh "fails" → reconcile branch
    reconcileAcceptedMutation: (_, record) async => reconciled.add(record.aggregateId),
    shouldReconcileAcceptedMutation: (_) async => true,
  );

  await controller.syncPendingMutations(/* context */);

  expect(reconciled, hasLength(1)); // reconciled, not lost
  expect(store.clearedAggregateIds, hasLength(1));
  expect(store.lastSavedStatus, PlanningMutationSyncStatus.accepted);
});
```

- [ ] **Step 4: Run — expected PASS**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_fault_injection_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/planning_fault_injection_test.dart
git commit -m "test(planning): adversarial crash + partial-refresh sync coverage (LF-1, LF-2)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 4: Song single-flight (LF-3) — FIX

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/song_single_flight_test.dart`
- Modify: `lib/src/application/song_library/song_mutation_sync_controller.dart`
- Read first: `lib/src/application/song_library/song_mutation_sync_controller.dart:5-60` (current `syncPendingSongs`, no in-flight guard); planning guard for the pattern (`planning_mutation_sync_controller.dart:35-43`).

- [ ] **Step 1: Write the failing test — concurrent triggers must coalesce**

Use a slow remote (a `Completer` gate) so two `syncPendingSongs` calls overlap; assert the remote saw the mutation once.

```dart
test('concurrent syncPendingSongs coalesce into one in-flight run (LF-3)', () async {
  final gate = Completer<void>();
  // Build a song remote/store fake whose send awaits `gate` and counts calls
  // (mirror the song controller test fakes already in
  //  test/application/song_library/song_mutation_sync_controller_test.dart).
  final controller = /* SongMutationSyncController with the gated fake */;

  final first = controller.syncPendingSongs(/* context */);
  final second = controller.syncPendingSongs(/* context */); // while first in flight
  gate.complete();
  await Future.wait([first, second]);

  expect(/* remote send count */, 1); // not 2 — single-flight
});
```

- [ ] **Step 2: Run — expected FAIL (song has no single-flight)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/song_single_flight_test.dart -r expanded`
Expected: FAIL — the mutation is sent twice.

- [ ] **Step 3: Add single-flight to the song controller**

Mirror planning. In `SongMutationSyncController`:

```dart
Future<void>? _inFlight;

Future<void> syncPendingSongs(SongMutationContext context) {
  final inFlight = _inFlight;
  if (inFlight != null) return inFlight;
  final run = _runSync(context).whenComplete(() => _inFlight = null);
  _inFlight = run;
  return run;
}

// Rename the current body of syncPendingSongs to _runSync(context).
```

- [ ] **Step 4: Run — expected PASS**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/song_single_flight_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Run the existing song controller suite (no regression)**

Run: `cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/song_single_flight_test.dart \
        apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart
git commit -m "fix(song): single-flight guard for syncPendingSongs (LF-3)

Coalesce concurrent sync triggers into one in-flight run, mirroring the
planning controller, to prevent double-send / clear races.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 2 — Merge Visibility & Field Preservation (LF-4, LF-5, LF-6)

### Task 5: Failed/conflict edit visibility + partial-edit preservation (LF-4, LF-5) — VALIDATION

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/planning_merge_visibility_test.dart`
- Under test: `lib/src/application/planning/planning_local_read_repository.dart`
- Read first: the merge functions `:120-176` (`_mergePlans`) and `:178-216` (`_mergePlanDetail`), plus how the existing `test/application/planning/*` tests build base plans + mutation records.

- [ ] **Step 1: Write LF-4 test — a `conflict`/`failed` planEdit stays in the merged read**

```dart
test('a conflicted plan edit remains visible in the merged read (LF-4)', () async {
  // base plan version 1; a planEdit mutation with syncStatus == conflict.
  // Build the repository over fakes and read the merged plan list.
  // Assert the edited name is present (not reverted to the base name).
});
```

- [ ] **Step 2: Write LF-5 test — a name-only edit does not blank description/scheduledFor**

```dart
test('name-only edit preserves existing description and scheduledFor (LF-5)', () async {
  // base plan with description + scheduledFor set; a planEdit with only name set
  // (description == null, scheduledFor == null on the mutation).
  // Assert merged plan keeps the base description and scheduledFor.
});
```

- [ ] **Step 3: Run — expected PASS (both validate shipped behaviour)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_merge_visibility_test.dart -r expanded`
Expected: PASS. (If LF-4/LF-5 fail, the merge regressed — fix `_mergePlans`/`_mergePlanDetail` `?? existing` and the actionable-mutation overlay before continuing.)

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/planning_merge_visibility_test.dart
git commit -m "test(planning): merge visibility + partial-edit preservation (LF-4, LF-5)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 6: Double-add same song offline (LF-6) — FIX

**Files:**
- Modify (test): `apps/lyron_app/test/offline/adversarial/planning_merge_visibility_test.dart`
- Modify (prod): `lib/src/application/planning/planning_local_read_repository.dart:264-283` (`sessionItemCreateSong` merge)
- Read first: `:264-283` — current dedup is `removeWhere((item) => item.id == mutation.aggregateId)` (item id only).

- [ ] **Step 1: Write the failing test — same song added twice with distinct item ids appears once**

```dart
test('adding the same song twice offline does not duplicate it in the session (LF-6)', () async {
  // two sessionItemCreateSong mutations, different aggregateId (item id), same songId.
  // Assert the merged session items contain the song exactly once.
});
```

- [ ] **Step 2: Run — expected FAIL (both items appear)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_merge_visibility_test.dart -r expanded`
Expected: FAIL — the song appears twice.

- [ ] **Step 3: Fix the merge to dedup by songId as well as item id**

In the `sessionItemCreateSong` branch (`:264-283`), before adding, drop any existing item with the same `songId` (in addition to the same item id), so a second offline add of the same song collapses to one local item:

```dart
final newSongId = mutation.songId;
sessionItems.removeWhere(
  (item) => item.id == mutation.aggregateId ||
      (newSongId != null && item.song.id == newSongId),
);
```

- [ ] **Step 4: Run — expected PASS**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_merge_visibility_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Run the planning read-repository suite (no regression)**

Run: `cd apps/lyron_app && flutter test test/application/planning/ test/offline/planning/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/planning_merge_visibility_test.dart \
        apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart
git commit -m "fix(planning): dedup duplicate offline song-adds by songId in merge (LF-6)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 3 — Reconcile Null-Field Hardening (LF-8) — FIX

### Task 7: Reject null required fields in the reconciler instead of silent coercion

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/planning_reconcile_nullfield_test.dart`
- Modify: `lib/src/application/planning/planning_mutation_reconciler.dart`
- Read first: the whole reconciler — the `?? ''`/`?? 0` coercions for `planId`, `sessionId`, `songId`, `slug` on create paths (`:45-85`).

- [ ] **Step 1: Decide the contract**

Required-on-create fields (a `sessionItemCreateSong` with a null `songId`/`sessionId`, or a `sessionCreate` with a null `planId`) indicate a corrupt mutation record; silently writing `''`/`0` into the projection hides the corruption. The fix: throw a typed `ReconcileFieldError` for these, so the sync run surfaces it instead of persisting empty data. Non-required fields (e.g. `description`) keep their nullable handling.

- [ ] **Step 2: Write the failing test**

```dart
test('reconciling a session-item create with a null songId is rejected, not coerced (LF-8)', () async {
  final reconciler = PlanningMutationReconciler(localStore: () => _RecordingLocalStore());
  // a sessionItemCreateSong record with songId == null, sessionId set.
  expect(
    () => reconciler.reconcile(/* context */, /* record with null songId */),
    throwsA(isA<ReconcileFieldError>()),
  );
});
```

- [ ] **Step 3: Run — expected FAIL (currently coerces to '' and writes)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_reconcile_nullfield_test.dart -r expanded`
Expected: FAIL — no throw; an empty-songId record is written.

- [ ] **Step 4: Implement the rejection**

Add the error type and a helper, and replace the `?? ''`/`?? 0` on required-on-create fields:

```dart
class ReconcileFieldError extends StateError {
  ReconcileFieldError(String field, PlanningMutationKind kind)
      : super('Missing required field "$field" reconciling ${kind.value}');
}

T _required<T>(T? value, String field, PlanningMutationKind kind) =>
    value ?? (throw ReconcileFieldError(field, kind));
```

Then in `sessionItemCreateSong`: `songId: _required(record.songId, 'songId', record.kind)`, `sessionId: _required(record.sessionId, 'sessionId', record.kind)`; in `sessionCreate`: `planId: _required(record.planId, 'planId', record.kind)`. Leave `description` and other genuinely optional fields nullable. Keep `?? 1` for `version` defaults (a legitimate default), but document why with a one-line comment.

- [ ] **Step 5: Run — expected PASS**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_reconcile_nullfield_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 6: Run the reconciler suite (no regression)**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_mutation_reconciler_test.dart`
Expected: PASS. (Adjust any existing test that relied on silent coercion to supply the now-required field; that reliance was the bug.)

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/planning_reconcile_nullfield_test.dart \
        apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart
git commit -m "fix(planning): reject null required fields in reconciler (LF-8)

Replace silent '' / 0 coercion on create paths with a typed
ReconcileFieldError so corrupt mutation records surface instead of writing
empty projection rows.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 4 — Migration With Pending Mutations (LF-T7)

### Task 8: Planning v4→v5 migration preserves a pending mutation — VALIDATION

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/planning_migration_test.dart`
- Under test: `lib/src/offline/planning/planning_local_database.dart:33-64`
- Read first: the planning migration strategy and `test/offline/planning/planning_mutation_store_test.dart` for how rows are written/read.

- [ ] **Step 1: Write the test — open at v4 schema, insert a pending mutation, upgrade to v5, assert it survives**

Use a native temp-file DB. Insert a row through a v4-shaped schema (or insert via the current schema then assert the `onUpgrade` `addColumn` calls do not drop data). Concretely: create the DB at the current version, write a pending mutation, close, reopen, and assert the mutation reads back with all v5 columns present and `syncStatus == pending`.

```dart
test('a pending planning mutation survives a database reopen across the v5 schema (LF-T7)', () async {
  final file = await createRelaunchDbFile('planning-migration');
  var db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
  // write a pending mutation via the store
  await db.close();
  db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
  // read it back; assert syncStatus pending and columns intact
  await db.close();
});
```

- [ ] **Step 2: Run — expected PASS**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_migration_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/planning_migration_test.dart
git commit -m "test(offline): pending planning mutation survives schema reopen (LF-T7)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 9: Catalog migration strategy + reopen survival (LF-T7) — FIX

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/song_catalog_migration_test.dart`
- Modify: `lib/src/offline/song_catalog/song_catalog_database.dart`
- Read first: `song_catalog_database.dart` (schemaVersion 2, NO migration), `song_catalog_tables.dart` (table set), planning's `MigrationStrategy` for the pattern.

- [ ] **Step 1: Write the failing test — a pending song mutation survives reopen, and a migration strategy exists**

```dart
test('a pending song mutation survives a catalog database reopen (LF-T7)', () async {
  final file = await createRelaunchDbFile('catalog-migration');
  var db = SongCatalogDatabase.connect(openRelaunchExecutor(file));
  // write a pending CachedCatalogSongMutations row via the store
  await db.close();
  db = SongCatalogDatabase.connect(openRelaunchExecutor(file));
  // assert it reads back intact
  await db.close();
});

test('SongCatalogDatabase declares an explicit migration strategy (LF-T7)', () {
  final db = SongCatalogDatabase.inMemory();
  expect(db.migration, isNotNull);
});
```

- [ ] **Step 2: Run — expected FAIL on the strategy assertion (no `migration` override)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/song_catalog_migration_test.dart -r expanded`
Expected: FAIL — `migration` is the default; the explicit-strategy test fails (and any future upgrade is unguarded).

- [ ] **Step 3: Add an explicit MigrationStrategy mirroring planning**

In `SongCatalogDatabase`:

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async => m.createAll(),
  // schemaVersion 2 was the initial shipped schema; no historical column
  // delta exists. This explicit onUpgrade is the forward-safe seam for future
  // bumps and documents the migration contract (LF-T7).
  onUpgrade: (m, from, to) async {
    // No historical upgrades yet. Future column additions go here, e.g.:
    //   if (from < 3) await m.addColumn(table, table.newColumn);
  },
);
```

Keep `schemaVersion => 2`.

- [ ] **Step 4: Run — expected PASS**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/song_catalog_migration_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Run catalog store suite + migration lint (no regression)**

Run: `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/song_catalog_migration_test.dart \
        apps/lyron_app/lib/src/offline/song_catalog/song_catalog_database.dart
git commit -m "fix(offline): explicit catalog migration strategy (LF-T7)

SongCatalogDatabase declared schemaVersion 2 with no MigrationStrategy,
leaving future upgrades unguarded. Add an explicit onCreate/onUpgrade
strategy mirroring the planning database and cover reopen survival.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 5 — Probes (LF-T4, LF-T6)

### Task 10: Storage-pressure probe (LF-T4)

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/storage_pressure_probe_test.dart`
- Read first: `lib/src/application/planning/drift_planning_mutation_store.dart` (the write path), `test/offline/planning/planning_mutation_store_test.dart`.

- [ ] **Step 1: Write the probe — a write failure while persisting a mutation must not silently lose it**

Inject a `QueryExecutor` (or wrap the store's DB) that throws on the mutation insert, then assert the failure is observable (an exception propagates to the caller), not swallowed.

```dart
test('a storage write failure when queuing a mutation surfaces, not silently dropped (LF-T4 probe)', () async {
  // Build the store over a DB whose mutation insert throws (simulated quota/IO error).
  // Assert: queuing throws (observable) AND no half-written row is left behind.
});
```

- [ ] **Step 2: Run — observe behaviour**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/storage_pressure_probe_test.dart -r expanded`
- If it PASSES (failure surfaces): this is a characterization test — keep it, reference `LF-T4` in a comment, done.
- If it FAILS because the error is swallowed and the mutation is lost: this is an **in-seam bug** — fix the store to propagate the write error (do not catch-and-ignore), then make the test green. Commit the fix as `fix(offline): …`.

- [ ] **Step 3: Document the deferred eviction policy**

Whatever the outcome, the full size-monitor + eviction policy is out of scope; ensure `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md` exists (Task 14) and reference it in the test file header.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/storage_pressure_probe_test.dart
# include the store fix in this commit only if Step 2 required one
git commit -m "test(offline): storage-pressure probe for mutation persistence (LF-T4)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 11: Clock-skew probe + injectable clock seam (LF-T6)

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/clock_skew_probe_test.dart`
- Modify: `lib/src/application/planning/planning_mutation_reconciler.dart:17`
- Read first: the reconciler (`reconciledAt = DateTime.now().toUtc()`), and any provider that constructs `PlanningMutationReconciler` (search `PlanningMutationReconciler(`).

- [ ] **Step 1: Add the clock seam (minimal, no server anchor)**

Make the reconciler read an injectable clock, defaulting to wall-clock:

```dart
class PlanningMutationReconciler {
  const PlanningMutationReconciler({
    required PlanningLocalStore Function() localStore,
    DateTime Function() now = _wallClockNow,
  })  : _localStore = localStore,
        _now = now;

  final PlanningLocalStore Function() _localStore;
  final DateTime Function() _now;

  static DateTime _wallClockNow() => DateTime.now().toUtc();
  // ... use _now() in place of DateTime.now().toUtc() at the top of reconcile().
}
```

Leave every existing construction site unchanged (the default keeps current behaviour).

- [ ] **Step 2: Run the existing reconciler suite — expected PASS (default unchanged)**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_mutation_reconciler_test.dart`
Expected: PASS.

- [ ] **Step 3: Write the probe — a skewed clock produces a skewed reconciledAt (characterization)**

```dart
test('reconcile stamps records with the injected clock; device skew flows through (LF-T6 probe)', () async {
  final skewed = DateTime.utc(2030, 1, 1);
  final store = _RecordingLocalStore();
  final reconciler = PlanningMutationReconciler(
    localStore: () => store,
    now: () => skewed,
  );
  await reconciler.reconcile(/* context */, /* a planCreate record */);
  expect(store.lastUpsertedPlan.updatedAt, skewed); // device clock flows through, no server anchor
});
```

- [ ] **Step 4: Run — expected PASS (documents current behaviour)**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/clock_skew_probe_test.dart -r expanded`
Expected: PASS. Reference `LF-T6` + the deferred server-clock-anchor doc in the test header.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/clock_skew_probe_test.dart \
        apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart
git commit -m "test(planning): clock-skew probe + injectable reconciler clock (LF-T6)

Add a minimal injectable-clock seam (default unchanged) and characterize how
device-clock skew flows into reconciled timestamps. The server-clock anchor
fix is deferred.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 6 — Integration: Relaunch & Two-Device (scenarios 1, 2)

### Task 12: Offline edit → relaunch → sync → convergence (skip-gated)

**Files:**
- Create: `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart`
- Read first: `test/integration/local_first_authenticated_song_reader_flow_test.dart` (env consts, `skip:`, temp-file DB, `_PassthroughHttpOverrides`, real `SupabaseClient`).

- [ ] **Step 1: Write the test — edit a plan offline, reopen the DB, then sync and converge**

```dart
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

test(
  'an offline plan edit survives relaunch and converges after sync',
  () async {
    // 1. authenticate against the local stack; seed a plan.
    // 2. go offline (no network / passthrough blocked); edit the plan → pending mutation.
    // 3. close the planning DB; reopen from the same file (relaunch) → assert the edit is still visible.
    // 4. go online; run syncPendingMutations.
    // 5. assert: backend reflects the edit AND the local mutation is cleared (converged).
  },
  skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
);
```

- [ ] **Step 2: Run with the local stack**

Run:
```bash
cd apps/lyron_app && flutter test test/integration/offline_edit_relaunch_sync_flow_test.dart \
  --dart-define SUPABASE_URL="$SUPABASE_URL" --dart-define SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" -r expanded
```
Expected: PASS (start the stack via `scripts/supabase-start.sh` first). With no env it skips.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart
git commit -m "test(integration): offline edit -> relaunch -> sync convergence (LF-T1)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 13: Two-device conflict matrix (skip-gated)

**Files:**
- Create: `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart`
- Read first: the planning mutation repository integration (`test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`) for how OCC `base_version` conflicts surface.

- [ ] **Step 1: Write the matrix — two clients, stale base_version, assert convergence + loser visibility**

One `group` with a sub-`test` per operation pair, each skip-gated. Pairs: rename↔rename, reorder↔reorder, edit↔remote-delete, add-same-song-twice (LF-6), partial-edit↔full-edit (LF-5).

```dart
group('two-device conflict matrix', () {
  test('rename vs rename: later sync sees an OCC conflict, both edits remain inspectable', () async {
    // device A and device B each rename the same session from base_version N.
    // A syncs (accepted). B syncs (conflict). Assert: B's mutation is in `conflict`
    // status and still visible in B's merged read (LF-4), backend holds A's value.
  }, skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty);

  // … one test per remaining pair, same skip guard.
});
```

- [ ] **Step 2: Run with the local stack**

Run: `cd apps/lyron_app && flutter test test/integration/two_device_conflict_matrix_test.dart --dart-define SUPABASE_URL="$SUPABASE_URL" --dart-define SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" -r expanded`
Expected: PASS. Any non-converging or silently-reverting pair is an in-seam bug → fix it (red→green) and note the finding in the commit.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart
git commit -m "test(integration): two-device conflict matrix (LF-1, LF-4, LF-5, LF-6)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 7 — Documentation & Closeout

### Task 14: Deferred entries

**Files:**
- Create: `docs/deferred/2026-06-29-web-offline-e2e.md`
- Create: `docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`
- Create: `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`
- Read first: `docs/deferred/README.md` for the entry format.

- [ ] **Step 1: Write each deferred entry**

Each: title, finding id, why deferred (new subsystem, not in-seam), what the probe/native-suite covers instead, and the trigger to revisit (per `docs/deferred/README.md`: "becomes priority when a slice re-enters this area").

- [ ] **Step 2: Commit**

```bash
git add docs/deferred/2026-06-29-*.md
git commit -m "docs(deferred): web offline e2e, server-clock anchor (LF-T6), storage eviction (LF-T4)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 15: Testing strategy + ADR + review annotations

**Files:**
- Modify: `docs/testing/testing-strategy.md` (record the adversarial suites; remove matching §10 gaps)
- Modify: `docs/architecture/decisions/ADR-019-exactly-once-planning-mutation-sync.md` (Validation note linking the suites)
- Modify: `docs/architecture/decisions/ADR-020-non-destructive-session-and-offline-authenticated-state.md` (Validation note → integration relaunch suite)
- Modify: `docs/architecture/repository-review-2026-06-22.md` (annotate validated/fixed findings)

- [ ] **Step 1: Update testing-strategy** — add an "Adversarial offline/sync" subsection listing each new suite and the finding it proves; strike the now-covered items in the §10 gap list.

- [ ] **Step 2: Add a "Validation" note to ADR-019 and ADR-020** linking the suite paths that prove each decision (exactly-once → Task 3/4; non-destructive relaunch → Task 12).

- [ ] **Step 3: Annotate the review** — mark `LF-1/2/3/4/5/6/8/T7` as validated/fixed with the suite path; note `LF-T4/T6` characterized + deferred.

- [ ] **Step 4: Commit**

```bash
git add docs/testing/testing-strategy.md docs/architecture/decisions/ADR-019-*.md \
        docs/architecture/decisions/ADR-020-*.md docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(testing): record adversarial offline/sync validation; annotate findings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 16: Full verify + PR

- [ ] **Step 1: Run the full unit suite**

Run: `cd apps/lyron_app && flutter test`
Expected: PASS (integration suites skip without env).

- [ ] **Step 2: Analyze + format**

Run: `cd apps/lyron_app && dart format --set-exit-if-changed lib test && flutter analyze`
Expected: No changes / no issues.

- [ ] **Step 3: Run integration suites against the local stack** (if available)

Run: `scripts/supabase-start.sh` then the two integration files with the dart-defines from Task 12/13.
Expected: PASS.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin test/local-first-validation
gh pr create --fill --base main
```
PR body: link the spec + this plan; list validated findings and the fixes (LF-3 song single-flight, LF-6 dedup, LF-8 null-field rejection, LF-T7 catalog strategy, plus any probe-surfaced fix); list deferred items. End with the Claude Code attribution. Merge only on green CI (AGENTS.md #7).

---

## Self-Review (completed during planning)

- **Spec coverage:** scenarios 1–6 → Tasks 12/13 (1,2), 3/4 (3a/b/d), 7 (3c), 5/6 (3e), 8/9 (4), 10 (5), 11 (6). Fix policy → labelled FIX/VALIDATION per task. Docs duties → Tasks 14/15. Deferred → Task 14. ✓
- **Placeholder scan:** test bodies that depend on existing record/context builders point to the exact file to mirror rather than inventing constructors; fixes show concrete code. No "TBD"/"add error handling". ✓
- **Type consistency:** `syncPendingMutations`/`syncPendingSongs`, `_inFlight`/`_runSync`, `ReconcileFieldError`, `createRelaunchDbFile`/`openRelaunchExecutor`, `FaultInjectingPlanningRemote` used consistently across tasks. ✓
- **Note for the executor:** confirm each VALIDATION test is actually green before moving on — a red VALIDATION test means a regression, not an expected fix.
