# Mutation Budget and Storage Eviction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound the local mutation store with an explicit byte budget, account for
the local storage footprint, and define an eviction policy that never touches
unsynced user intent.

**Architecture:** A `BudgetedPlanningMutationStore` decorator wraps
`DriftPlanningMutationStore` and is the single enforcement point. It guards only
the `record*` methods, measures mutation bytes through a
`PlanningStorageAccountant`, refuses new writes past the budget, and — on an
actual storage failure — evicts droppable catalog sources once and retries once
before propagating a typed failure. A `LocalStorageMonitor` combines the planning
and catalog accountants into a footprint and pressure level for the sync UI.

**Tech Stack:** Dart / Flutter, Drift (sqlite3 native, IndexedDB web), Riverpod 2,
`flutter_test`.

**Spec:** `docs/specs/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`

---

## File Structure

**Create:**

| path | responsibility |
|---|---|
| `apps/lyron_app/lib/src/application/storage/local_storage_footprint.dart` | `LocalStorageFootprint` value type, `LocalStoragePressure` enum |
| `apps/lyron_app/lib/src/application/storage/local_storage_budget.dart` | thresholds + classification |
| `apps/lyron_app/lib/src/application/storage/local_storage_write_failure.dart` | `LocalStorageWriteFailure` |
| `apps/lyron_app/lib/src/application/storage/planning_storage_accountant.dart` | mutation + projection byte estimates |
| `apps/lyron_app/lib/src/application/storage/catalog_storage_accountant.dart` | catalog byte estimate |
| `apps/lyron_app/lib/src/application/storage/song_catalog_evictor.dart` | droppable-source eviction |
| `apps/lyron_app/lib/src/application/storage/local_storage_monitor.dart` | footprint + pressure composition |
| `apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart` | the enforcement decorator |

**Modify:**

| path | change |
|---|---|
| `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart` | orphan session-item cleanup |
| `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart` | `PlanningMutationBudgetExceededException` |
| `apps/lyron_app/lib/src/application/core_providers.dart` | storage providers |
| `apps/lyron_app/lib/src/application/planning_providers.dart` | wrap the mutation store |
| `apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart` | carry `storagePressure` |
| `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart` | feed pressure into the overview |
| `apps/lyron_app/test/offline/adversarial/storage_pressure_probe_test.dart` | probe → enforced contract |

**Tests:** mirrored under `apps/lyron_app/test/application/storage/` and
`apps/lyron_app/test/offline/adversarial/`.

All test commands run from the repository root and use the repo's convention:
`(cd apps/lyron_app && flutter test <path>)`.

---

### Task 1: Pin the existing squash semantics before changing anything

The store already folds intent per aggregate. Before adding a budget or touching
the collapse paths, pin what those folds guarantee, so a later change cannot
silently break exactly-once sync (ADR-019) or OCC base-version semantics.

**Files:**
- Test: `apps/lyron_app/test/offline/adversarial/planning_squash_contract_test.dart` (create)

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// LF-T3 contract: folding repeated intent into one row per aggregate must
/// preserve exactly-once sync (ADR-019) and OCC base-version semantics.
/// A squashed record still has to reconcile correctly and must never
/// manufacture a conflict that the un-squashed sequence would not have had.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('DriftPlanningMutationStore squash contract', () {
    late PlanningLocalDatabase database;
    late DriftPlanningMutationStore store;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      store = DriftPlanningMutationStore(
        database: database,
        localStore: DriftPlanningLocalStore(database),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('planEdit folded into a pending planCreate leaves exactly one '
        'record, still a create', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Sunday Service',
          description: 'Second slot',
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(pending, hasLength(1));
      // Exactly-once: the fold must not turn one create into create+edit,
      // which would send the aggregate twice.
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.name, 'Sunday Service');
      expect(pending.single.description, 'Second slot');
      // A create has no base version to conflict against; folding an edit
      // into it must not invent one.
      expect(pending.single.baseVersion, isNull);
    });

    test('repeated planEdit keeps the FIRST captured base version and '
        'origin snapshot', () async {
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-2',
          name: 'First',
          baseVersion: 7,
          originSnapshot: {'name': 'Original'},
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-2',
          name: 'Second',
          baseVersion: 9,
          originSnapshot: {'name': 'Stale'},
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(pending, hasLength(1));
      expect(pending.single.name, 'Second');
      // OCC: the base version is the version the user actually started
      // from. Advancing it on a later local edit would silently defeat
      // conflict detection against a concurrent remote change.
      expect(pending.single.baseVersion, 7);
      expect(pending.single.originSnapshot, {'name': 'Original'});
    });

    test('sessionDelete of a still-pending sessionCreate removes the record '
        'entirely rather than queueing a delete', () async {
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-3',
          slug: 'first-set',
          name: 'First Set',
          position: 0,
        ),
      );
      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-3',
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      // Exactly-once: the session never existed remotely, so a delete must
      // not be sent for it.
      expect(pending, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test**

```bash
(cd apps/lyron_app && flutter test test/offline/adversarial/planning_squash_contract_test.dart)
```

Expected: PASS. These pin behaviour that already exists — they are a
regression harness, not a red test. If any of them fails, stop: the fold
semantics differ from what the spec assumed, and the plan needs revisiting
before continuing.

> **Not as specified — genuine RED, not a pure pin.** The suite did not pass
> on first run: the base-version fold disagreed with itself across the four
> non-reorder paths (`planEdit`, `sessionRename`, `sessionDelete`,
> `sessionItemDelete` let a later draft's `baseVersion` overwrite the first
> captured one; the reorder paths did not). That is a real OCC bug, not a
> pre-existing-behaviour assumption gone stale, so the correct move under
> `superpowers:systematic-debugging` was to stop, diagnose, and fix it before
> the suite could pin anything — which is what happened, in the same commit.
> See commit `89dc4ff`.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/planning_squash_contract_test.dart
git commit -m "test(planning): pin mutation squash exactly-once and OCC semantics"
```

> **Landed under a different message, combined with the fix it required.**
> Actual commit: `89dc4ff` — `fix(planning): keep the first captured base
> version when folding edits`. It carries both the new
> `planning_squash_contract_test.dart` suite and the four-path base-version
> fix Step 2 uncovered, because the suite could not pin a contract the code
> did not yet satisfy. The three original squash/OCC assertions and the
> exactly-once fold behaviour they pin are genuinely present and passing at
> HEAD; only the commit shape and message differ from what this step
> specified.

---

### Task 2: Fix orphaned session-item mutations

When `recordSessionDelete` collapses a still-pending `sessionCreate`, the pending
`session_item` mutations belonging to that session survive. They can never sync
(the parent session does not exist remotely, so they fail `dependencyBlocked`)
and they consume the budget Task 5 introduces.

**Files:**
- Test: `apps/lyron_app/test/offline/adversarial/planning_squash_contract_test.dart` (modify)
- Modify: `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`

- [x] **Step 1: Write the failing test**

Append inside the existing `group` in
`planning_squash_contract_test.dart`:

```dart
    test('sessionDelete of a pending sessionCreate also removes that '
        "session's pending item mutations", () async {
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-4',
          slug: 'second-set',
          name: 'Second Set',
          position: 1,
        ),
      );
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-2',
          planId: 'plan-4',
          songId: 'song-1',
          songTitle: 'Song One',
          position: 0,
        ),
      );
      await store.recordSessionItemReorder(
        context: context,
        draft: const PlanningSessionItemReorderMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-4',
          orderedSessionItemIds: ['item-1'],
        ),
      );

      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-4',
        ),
      );

      final remaining = await store.readAllMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      // Nothing may survive that references a session which never existed
      // remotely: those rows can only ever fail dependencyBlocked, and they
      // would consume the mutation budget forever.
      expect(remaining, isEmpty);
    });
```

- [x] **Step 2: Run the test to verify it fails**

```bash
(cd apps/lyron_app && flutter test test/offline/adversarial/planning_squash_contract_test.dart)
```

Expected: FAIL — the item create and the item-order row survive, so
`remaining` has 2 entries.

- [x] **Step 3: Implement the cleanup**

In `drift_planning_mutation_store.dart`, inside `recordSessionDelete`, in the
`existing?.kind == PlanningMutationKind.sessionCreate` branch, add the item
cleanup before `return;`:

```dart
      if (existing?.kind == PlanningMutationKind.sessionCreate) {
        await (_database.delete(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(context.userId) &
                  table.organizationId.equals(context.organizationId) &
                  table.aggregateType.equals('session') &
                  table.aggregateId.equals(draft.sessionId),
            ))
            .go();
        // The session never reached the backend, so its pending item
        // mutations can never sync: they would fail dependencyBlocked
        // forever while consuming the mutation budget. Drop them with the
        // session, inside the same transaction.
        await _deletePendingMutationsForSession(
          context: context,
          sessionId: draft.sessionId,
        );
        await _removeSessionFromPendingReorder(
          context: context,
          planId: draft.planId,
          sessionId: draft.sessionId,
        );
        return;
      }
```

Add the private helper next to `_removeSessionFromPendingReorder`:

```dart
  Future<void> _deletePendingMutationsForSession({
    required PlanningMutationContext context,
    required String sessionId,
  }) async {
    await (_database.delete(_database.cachedPlanningMutations)..where(
          (table) =>
              table.userId.equals(context.userId) &
              table.organizationId.equals(context.organizationId) &
              table.aggregateType.equals('session_item') &
              table.sessionId.equals(sessionId),
        ))
        .go();
    await (_database.delete(_database.cachedPlanningMutations)..where(
          (table) =>
              table.userId.equals(context.userId) &
              table.organizationId.equals(context.organizationId) &
              table.aggregateType.equals('session_item_order') &
              table.aggregateId.equals(sessionId),
        ))
        .go();
  }
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
(cd apps/lyron_app && flutter test test/offline/adversarial/)
```

Expected: PASS, all adversarial suites.

- [x] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart \
        apps/lyron_app/test/offline/adversarial/planning_squash_contract_test.dart
git commit -m "fix(planning): drop pending item mutations with a collapsed session create"
```

---

### Task 3: Footprint, pressure and budget value types

**Files:**
- Create: `apps/lyron_app/lib/src/application/storage/local_storage_footprint.dart`
- Create: `apps/lyron_app/lib/src/application/storage/local_storage_budget.dart`
- Test: `apps/lyron_app/test/application/storage/local_storage_budget_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';

void main() {
  group('LocalStorageBudget', () {
    const budget = LocalStorageBudget(
      mutationWarnBytes: 100,
      mutationRefuseBytes: 200,
      totalWarnBytes: 1000,
      totalCriticalBytes: 2000,
    );

    LocalStorageFootprint footprint({
      int mutationBytes = 0,
      int projectionBytes = 0,
      int catalogBytes = 0,
    }) => LocalStorageFootprint(
      mutationBytes: mutationBytes,
      mutationCount: 0,
      projectionBytes: projectionBytes,
      catalogBytes: catalogBytes,
    );

    test('totalBytes sums every measured segment', () {
      expect(
        footprint(
          mutationBytes: 1,
          projectionBytes: 2,
          catalogBytes: 4,
        ).totalBytes,
        7,
      );
    });

    test('classifies ok below every threshold', () {
      expect(
        budget.classify(footprint(mutationBytes: 99)),
        LocalStoragePressure.ok,
      );
    });

    test('classifies warning at the mutation warn threshold', () {
      expect(
        budget.classify(footprint(mutationBytes: 100)),
        LocalStoragePressure.warning,
      );
    });

    test('classifies critical at the mutation refuse threshold', () {
      expect(
        budget.classify(footprint(mutationBytes: 200)),
        LocalStoragePressure.critical,
      );
    });

    test('classifies warning and critical on total bytes too', () {
      expect(
        budget.classify(footprint(catalogBytes: 1000)),
        LocalStoragePressure.warning,
      );
      expect(
        budget.classify(footprint(catalogBytes: 2000)),
        LocalStoragePressure.critical,
      );
    });

    test('refusesNewMutation only at or above the refuse threshold', () {
      expect(budget.refusesNewMutation(199), isFalse);
      expect(budget.refusesNewMutation(200), isTrue);
    });
  });
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
(cd apps/lyron_app && flutter test test/application/storage/local_storage_budget_test.dart)
```

Expected: FAIL — `Target of URI doesn't exist` for both new libraries.

- [x] **Step 3: Write the implementation**

`local_storage_footprint.dart`:

```dart
/// How much local storage the app is using, estimated from row content.
///
/// These are content-derived estimates (see `LocalStorageAccountant`), not
/// true on-disk sizes: they exclude index and page overhead, and on web they
/// say nothing about what the browser has actually allocated. They are
/// comparable to each other and stable for a fixed corpus, which is what the
/// budget and the pressure classification need.
class LocalStorageFootprint {
  const LocalStorageFootprint({
    required this.mutationBytes,
    required this.mutationCount,
    required this.projectionBytes,
    required this.catalogBytes,
  });

  const LocalStorageFootprint.empty()
    : this(
        mutationBytes: 0,
        mutationCount: 0,
        projectionBytes: 0,
        catalogBytes: 0,
      );

  /// Pending planning mutations — unsynced user intent, never evictable.
  final int mutationBytes;

  /// Number of planning mutation rows, for the user-facing warning.
  final int mutationCount;

  /// Cached planning projection — re-fetchable, but never evicted: offline it
  /// is the only readable view.
  final int projectionBytes;

  /// Cached song catalog, including its own pending song mutations.
  final int catalogBytes;

  int get totalBytes => mutationBytes + projectionBytes + catalogBytes;
}

enum LocalStoragePressure { ok, warning, critical }
```

`local_storage_budget.dart`:

```dart
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';

/// Thresholds for the two storage ladders.
///
/// The mutation thresholds bound unsynced local intent (LF-T3). Catalog
/// eviction cannot relieve them, because pending mutations are protected, so
/// the only remedies are syncing or discarding.
///
/// The total thresholds describe overall storage pressure (LF-T4) and are the
/// ones eviction responds to.
///
/// Defaults are deliberately out of reach of normal use. A budget that bites
/// during ordinary planning would be the wrong budget: the purpose is to make
/// growth bounded and observable, and to give a signal before the storage
/// substrate fails. They are constructor parameters so tests can use tiny
/// budgets.
class LocalStorageBudget {
  const LocalStorageBudget({
    this.mutationWarnBytes = 1 * 1024 * 1024,
    this.mutationRefuseBytes = 4 * 1024 * 1024,
    this.totalWarnBytes = 128 * 1024 * 1024,
    this.totalCriticalBytes = 192 * 1024 * 1024,
  });

  final int mutationWarnBytes;
  final int mutationRefuseBytes;
  final int totalWarnBytes;
  final int totalCriticalBytes;

  bool refusesNewMutation(int mutationBytes) =>
      mutationBytes >= mutationRefuseBytes;

  LocalStoragePressure classify(LocalStorageFootprint footprint) {
    if (footprint.mutationBytes >= mutationRefuseBytes ||
        footprint.totalBytes >= totalCriticalBytes) {
      return LocalStoragePressure.critical;
    }
    if (footprint.mutationBytes >= mutationWarnBytes ||
        footprint.totalBytes >= totalWarnBytes) {
      return LocalStoragePressure.warning;
    }
    return LocalStoragePressure.ok;
  }
}
```

- [x] **Step 4: Run the test to verify it passes**

```bash
(cd apps/lyron_app && flutter test test/application/storage/local_storage_budget_test.dart)
```

Expected: PASS, 6 tests.

- [x] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/storage/ \
        apps/lyron_app/test/application/storage/
git commit -m "feat(storage): add local storage footprint, pressure and budget"
```

---

### Task 4: Planning storage accountant

Measures mutation and projection bytes from the planning database with SQL
aggregates over the text columns, plus a fixed per-row overhead standing in for
keys, integers and timestamps.

**Files:**
- Create: `apps/lyron_app/lib/src/application/storage/planning_storage_accountant.dart`
- Test: `apps/lyron_app/test/application/storage/planning_storage_accountant_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningStorageAccountant', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore mutationStore;
    late PlanningStorageAccountant accountant;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      accountant = PlanningStorageAccountant(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('reports zero for an empty store', () async {
      expect(
        await accountant.measureMutationBytes(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        0,
      );
      expect(
        await accountant.measureMutationCount(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        0,
      );
    });

    test('grows with mutation content and shrinks when cleared', () async {
      await mutationStore.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      final afterSmall = await accountant.measureMutationBytes(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(afterSmall, greaterThan(0));

      await mutationStore.recordPlanCreate(
        context: context,
        draft: PlanningPlanCreateMutationDraft(
          planId: 'plan-2',
          slug: 'midweek-service',
          name: 'Midweek Service',
          description: 'x' * 5000,
        ),
      );
      final afterLarge = await accountant.measureMutationBytes(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      // A 5000-character description must actually register: an accountant
      // that only counted rows would be blind to exactly the payloads that
      // make the store grow.
      expect(afterLarge - afterSmall, greaterThan(5000));

      expect(
        await accountant.measureMutationCount(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        2,
      );

      await mutationStore.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-2',
      );
      expect(
        await accountant.measureMutationBytes(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        afterSmall,
      );
    });

    test('scopes measurement to the given user and organization', () async {
      await mutationStore.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      expect(
        await accountant.measureMutationBytes(
          userId: 'other-user',
          organizationId: context.organizationId,
        ),
        0,
      );
    });

    test('measures the projection separately from mutations', () async {
      expect(await accountant.measureProjectionBytes(), 0);

      await localStore.replaceActiveProjection(
        userId: context.userId,
        organizationId: context.organizationId,
        plans: const [],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 7, 30),
      );

      // An owner row alone is still measurable footprint.
      expect(await accountant.measureProjectionBytes(), greaterThan(0));
    });
  });
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
(cd apps/lyron_app && flutter test test/application/storage/planning_storage_accountant_test.dart)
```

Expected: FAIL — `Target of URI doesn't exist:
'.../planning_storage_accountant.dart'`.

- [x] **Step 3: Write the implementation**

```dart
import 'package:drift/drift.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';

/// Fixed per-row allowance covering the columns that are not measured
/// directly — integer keys, versions, positions and timestamps — plus a
/// nominal share of sqlite row overhead. Deliberately coarse: the accountant
/// is a comparable estimate, not a true on-disk size.
const int kLocalStorageRowOverheadBytes = 64;

/// Measures the planning database's footprint from row content.
///
/// Uses `length(...)` over the text columns rather than a file size or a
/// browser quota API, so the same code runs on native and web and can be
/// exercised deterministically against an in-memory database.
class PlanningStorageAccountant {
  const PlanningStorageAccountant(this._database);

  final PlanningLocalDatabase _database;

  Future<int> measureMutationBytes({
    required String userId,
    required String organizationId,
  }) async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(SUM('
          'length(aggregate_type) + length(aggregate_id) + '
          'length(mutation_kind) + length(sync_status) + '
          "length(COALESCE(plan_id, '')) + "
          "length(COALESCE(session_id, '')) + "
          "length(COALESCE(slug, '')) + "
          "length(COALESCE(name, '')) + "
          "length(COALESCE(description, '')) + "
          "length(COALESCE(song_id, '')) + "
          "length(COALESCE(song_title, '')) + "
          "length(COALESCE(ordered_sibling_ids, '')) + "
          "length(COALESCE(origin_snapshot_json, '')) + "
          "length(COALESCE(error_code, '')) + "
          "length(COALESCE(error_message, '')) + "
          '$kLocalStorageRowOverheadBytes'
          '), 0) AS byte_estimate '
          'FROM cached_planning_mutations '
          'WHERE user_id = ?1 AND organization_id = ?2',
          variables: [Variable<String>(userId), Variable<String>(organizationId)],
          readsFrom: {_database.cachedPlanningMutations},
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }

  Future<int> measureMutationCount({
    required String userId,
    required String organizationId,
  }) async {
    final countExpression = _database.cachedPlanningMutations.aggregateId
        .count();
    final query = _database.selectOnly(_database.cachedPlanningMutations)
      ..addColumns([countExpression])
      ..where(
        _database.cachedPlanningMutations.userId.equals(userId) &
            _database.cachedPlanningMutations.organizationId.equals(
              organizationId,
            ),
      );
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  /// Projection footprint across every cached owner. The projection is never
  /// evicted, so this is reported for the monitor rather than acted on.
  Future<int> measureProjectionBytes() async {
    final row = await _database
        .customSelect(
          'SELECT ('
          '(SELECT COALESCE(SUM(length(user_id) + length(organization_id) + '
          "$kLocalStorageRowOverheadBytes), 0) "
          'FROM planning_projection_owners) + '
          '(SELECT COALESCE(SUM(length(plan_id) + length(slug) + '
          "length(name) + length(COALESCE(description, '')) + "
          "$kLocalStorageRowOverheadBytes), 0) "
          'FROM cached_planning_plans) + '
          '(SELECT COALESCE(SUM(length(session_id) + length(plan_id) + '
          "length(slug) + length(name) + $kLocalStorageRowOverheadBytes), 0) "
          'FROM cached_planning_sessions) + '
          '(SELECT COALESCE(SUM(length(session_item_id) + length(plan_id) + '
          'length(session_id) + length(song_id) + length(song_title) + '
          "$kLocalStorageRowOverheadBytes), 0) "
          'FROM cached_planning_session_items)'
          ') AS byte_estimate',
          readsFrom: {
            _database.planningProjectionOwners,
            _database.cachedPlanningPlans,
            _database.cachedPlanningSessions,
            _database.cachedPlanningSessionItems,
          },
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }
}
```

- [x] **Step 4: Run the test to verify it passes**

```bash
(cd apps/lyron_app && flutter test test/application/storage/planning_storage_accountant_test.dart)
```

Expected: PASS, 4 tests. If a column name is rejected by sqlite, check the
generated names in
`apps/lyron_app/lib/src/offline/planning/planning_local_database.g.dart` — Drift
maps Dart camelCase getters to snake_case columns.

- [x] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/storage/planning_storage_accountant.dart \
        apps/lyron_app/test/application/storage/planning_storage_accountant_test.dart
git commit -m "feat(storage): measure planning mutation and projection footprint"
```

---

### Task 5: Catalog accountant and evictor

The catalog database holds both droppable snapshot data and pending song
intent. Eviction deletes cached **sources** (the ChordPro bodies — the largest
payload) for songs that have no pending song mutation. Summaries stay, so the
song list remains browsable; a song whose body was evicted needs connectivity to
be read again until the next refresh.

**Files:**
- Create: `apps/lyron_app/lib/src/application/storage/catalog_storage_accountant.dart`
- Create: `apps/lyron_app/lib/src/application/storage/song_catalog_evictor.dart`
- Test: `apps/lyron_app/test/application/storage/song_catalog_evictor_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('SongCatalogEvictor', () {
    late SongCatalogDatabase database;
    late CatalogStorageAccountant accountant;
    late SongCatalogEvictor evictor;

    setUp(() async {
      database = SongCatalogDatabase.inMemory();
      accountant = CatalogStorageAccountant(database);
      evictor = SongCatalogEvictor(database: database, accountant: accountant);

      await database
          .into(database.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      for (final songId in ['song-clean', 'song-dirty']) {
        await database
            .into(database.cachedCatalogSummaries)
            .insert(
              CachedCatalogSummariesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: songId,
                slug: songId,
                title: songId,
                version: 1,
              ),
            );
        await database
            .into(database.cachedCatalogSources)
            .insert(
              CachedCatalogSourcesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: songId,
                source: 'body ' * 200,
              ),
            );
      }
      await database
          .into(database.cachedCatalogSongMutations)
          .insert(
            CachedCatalogSongMutationsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-dirty',
              slug: 'song-dirty',
              title: 'song-dirty',
              source: 'edited body',
              version: 2,
              syncStatus: 'pending',
            ),
          );
    });

    tearDown(() async {
      await database.close();
    });

    test('drops sources for songs without pending mutations and reports the '
        'bytes freed', () async {
      final before = await accountant.measureCatalogBytes();

      final freed = await evictor.evictDroppable();

      expect(freed, greaterThan(0));
      final after = await accountant.measureCatalogBytes();
      expect(after, before - freed);
    });

    test('never drops the source of a song with a pending mutation', () async {
      await evictor.evictDroppable();

      final sources = await database.select(database.cachedCatalogSources).get();
      expect(sources.map((row) => row.songId), ['song-dirty']);
    });

    test('never drops pending song mutations or summaries', () async {
      await evictor.evictDroppable();

      final mutations = await database
          .select(database.cachedCatalogSongMutations)
          .get();
      expect(mutations, hasLength(1));

      final summaries = await database
          .select(database.cachedCatalogSummaries)
          .get();
      expect(summaries, hasLength(2));
    });

    test('is idempotent: a second eviction frees nothing', () async {
      await evictor.evictDroppable();
      expect(await evictor.evictDroppable(), 0);
    });
  });
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
(cd apps/lyron_app && flutter test test/application/storage/song_catalog_evictor_test.dart)
```

Expected: FAIL — both new libraries are missing.

- [x] **Step 3: Write the implementation**

`catalog_storage_accountant.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart'
    show kLocalStorageRowOverheadBytes;
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// Measures the song catalog database's footprint from row content, on the
/// same content-derived basis as [PlanningStorageAccountant].
class CatalogStorageAccountant {
  const CatalogStorageAccountant(this._database);

  final SongCatalogDatabase _database;

  /// Total catalog footprint, including pending song mutations. Pending song
  /// mutations count towards pressure even though they are never evictable.
  Future<int> measureCatalogBytes() async {
    final row = await _database
        .customSelect(
          'SELECT ('
          '(SELECT COALESCE(SUM(length(song_id) + length(slug) + '
          "length(title) + $kLocalStorageRowOverheadBytes), 0) "
          'FROM cached_catalog_summaries) + '
          '(SELECT COALESCE(SUM(length(song_id) + length(source) + '
          "$kLocalStorageRowOverheadBytes), 0) "
          'FROM cached_catalog_sources) + '
          '(SELECT COALESCE(SUM(length(song_id) + length(slug) + '
          'length(title) + length(source) + '
          "length(COALESCE(sync_error_context, '')) + "
          "$kLocalStorageRowOverheadBytes), 0) "
          'FROM cached_catalog_song_mutations)'
          ') AS byte_estimate',
          readsFrom: {
            _database.cachedCatalogSummaries,
            _database.cachedCatalogSources,
            _database.cachedCatalogSongMutations,
          },
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }

  /// Bytes currently eligible for eviction: cached sources whose song has no
  /// pending mutation.
  Future<int> measureDroppableBytes() async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(SUM(length(song_id) + length(source) + '
          "$kLocalStorageRowOverheadBytes), 0) AS byte_estimate "
          'FROM cached_catalog_sources AS s '
          'WHERE NOT EXISTS ('
          'SELECT 1 FROM cached_catalog_song_mutations AS m '
          'WHERE m.user_id = s.user_id '
          'AND m.organization_id = s.organization_id '
          'AND m.song_id = s.song_id)',
          readsFrom: {
            _database.cachedCatalogSources,
            _database.cachedCatalogSongMutations,
          },
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }
}
```

`song_catalog_evictor.dart`:

```dart
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// The only eviction the app performs.
///
/// Deletes cached song **sources** for songs that carry no pending song
/// mutation. Sources are the largest cached payload and are re-fetchable, so
/// they are the one thing that can be given up under storage pressure.
///
/// Never touched: pending song mutations and pending planning mutations
/// (unsynced intent), cached summaries (they back the browsable list), the
/// planning projection (offline it is the only readable view) and the
/// last-known identity store (ADR-020).
///
/// This is local storage policy, never an authorization decision.
class SongCatalogEvictor {
  const SongCatalogEvictor({
    required SongCatalogDatabase database,
    required CatalogStorageAccountant accountant,
  }) : _database = database,
       _accountant = accountant;

  final SongCatalogDatabase _database;
  final CatalogStorageAccountant _accountant;

  /// Returns the estimated bytes freed.
  Future<int> evictDroppable() async {
    final droppableBytes = await _accountant.measureDroppableBytes();
    if (droppableBytes == 0) {
      return 0;
    }
    await _database.customStatement(
      'DELETE FROM cached_catalog_sources AS s '
      'WHERE NOT EXISTS ('
      'SELECT 1 FROM cached_catalog_song_mutations AS m '
      'WHERE m.user_id = s.user_id '
      'AND m.organization_id = s.organization_id '
      'AND m.song_id = s.song_id)',
    );
    return droppableBytes;
  }
}
```

- [x] **Step 4: Run the test to verify it passes**

```bash
(cd apps/lyron_app && flutter test test/application/storage/song_catalog_evictor_test.dart)
```

Expected: PASS, 4 tests. If sqlite rejects the `AS s` alias in `DELETE`, drop
the alias and qualify with the bare table name — older sqlite builds do not
accept aliases in `DELETE FROM`:

```sql
DELETE FROM cached_catalog_sources
WHERE NOT EXISTS (
  SELECT 1 FROM cached_catalog_song_mutations AS m
  WHERE m.user_id = cached_catalog_sources.user_id
  AND m.organization_id = cached_catalog_sources.organization_id
  AND m.song_id = cached_catalog_sources.song_id)
```

- [x] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/storage/catalog_storage_accountant.dart \
        apps/lyron_app/lib/src/application/storage/song_catalog_evictor.dart \
        apps/lyron_app/test/application/storage/song_catalog_evictor_test.dart
git commit -m "feat(storage): evict droppable catalog sources, never pending intent"
```

---

### Task 6: The enforcement decorator

**Files:**
- Create: `apps/lyron_app/lib/src/application/storage/local_storage_write_failure.dart`
- Create: `apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart`
- Test: `apps/lyron_app/test/application/planning/budgeted_planning_mutation_store_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('BudgetedPlanningMutationStore', () {
    late PlanningLocalDatabase database;
    late SongCatalogDatabase catalogDatabase;
    late DriftPlanningMutationStore delegate;
    late PlanningStorageAccountant accountant;
    late _RecordingEvictor evictor;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      catalogDatabase = SongCatalogDatabase.inMemory();
      delegate = DriftPlanningMutationStore(
        database: database,
        localStore: DriftPlanningLocalStore(database),
      );
      accountant = PlanningStorageAccountant(database);
      evictor = _RecordingEvictor(
        SongCatalogEvictor(
          database: catalogDatabase,
          accountant: CatalogStorageAccountant(catalogDatabase),
        ),
      );
    });

    tearDown(() async {
      await database.close();
      await catalogDatabase.close();
    });

    BudgetedPlanningMutationStore storeWithBudget(LocalStorageBudget budget) {
      return BudgetedPlanningMutationStore(
        delegate: delegate,
        accountant: accountant,
        evictor: evictor,
        budget: budget,
      );
    }

    test('allows writes below the refuse threshold', () async {
      final store = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      expect(
        await store.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        hasLength(1),
      );
    });

    test('refuses a new write once the mutation budget is exhausted, without '
        'evicting anything', () async {
      final store = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      await expectLater(
        () => store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        ),
        throwsA(isA<PlanningMutationBudgetExceededException>()),
      );

      // Catalog eviction cannot free mutation budget, so attempting it here
      // would destroy cached data for no benefit.
      expect(evictor.calls, 0);
    });

    test('a refused write leaves existing pending mutations untouched, and '
        'discard still works', () async {
      final permissive = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );
      await permissive.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );
      await expectLater(
        () => exhausted.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-2',
            slug: 'midweek-service',
            name: 'Midweek Service',
          ),
        ),
        throwsA(isA<PlanningMutationBudgetExceededException>()),
      );

      expect(
        await exhausted.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        hasLength(1),
      );

      // A full store must always be drainable: guarding clearMutation would
      // make the budget a trap with no way out.
      await exhausted.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(
        await exhausted.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        isEmpty,
      );
    });

    test('propagates a domain slug conflict without eviction or retry',
        () async {
      final store = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      await expectLater(
        () => store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-2',
            slug: 'weekend-service',
            name: 'Duplicate',
          ),
        ),
        throwsA(isA<LocalPlanningSlugConflictException>()),
      );
      expect(evictor.calls, 0);
    });
  });
}

/// Counts eviction calls so the tests can assert that eviction happens only
/// on a storage failure, never on a budget refusal.
class _RecordingEvictor implements SongCatalogEvictor {
  _RecordingEvictor(this._delegate);

  final SongCatalogEvictor _delegate;
  int calls = 0;

  @override
  Future<int> evictDroppable() {
    calls += 1;
    return _delegate.evictDroppable();
  }
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
(cd apps/lyron_app && flutter test test/application/planning/budgeted_planning_mutation_store_test.dart)
```

Expected: FAIL — `budgeted_planning_mutation_store.dart` and
`PlanningMutationBudgetExceededException` do not exist.

Note: `_RecordingEvictor implements SongCatalogEvictor` requires
`SongCatalogEvictor` to be implementable — it is a plain class with a single
public method, so `implements` works without extra changes.

- [x] **Step 3: Write the implementation**

Add to `planning_mutation_sync_types.dart`, next to
`LocalPlanningSlugConflictException`:

```dart
/// Thrown when a new planning mutation would push the local mutation store
/// past its byte budget (LF-T3).
///
/// The remedy is to sync or discard pending work: catalog eviction cannot
/// free mutation budget, because pending mutations are never evictable.
class PlanningMutationBudgetExceededException implements Exception {
  const PlanningMutationBudgetExceededException({
    required this.mutationBytes,
    required this.refuseBytes,
  });

  final int mutationBytes;
  final int refuseBytes;

  @override
  String toString() =>
      'PlanningMutationBudgetExceededException('
      'mutationBytes: $mutationBytes, refuseBytes: $refuseBytes)';
}
```

`local_storage_write_failure.dart`:

```dart
/// Thrown when a local write fails at the storage layer and still fails after
/// eviction and one retry (LF-T4).
///
/// The failure is never swallowed: the caller learns that the edit did not
/// reach local storage.
class LocalStorageWriteFailure implements Exception {
  const LocalStorageWriteFailure({
    required this.cause,
    required this.bytesFreedByEviction,
  });

  final Object cause;
  final int bytesFreedByEviction;

  @override
  String toString() =>
      'LocalStorageWriteFailure(cause: $cause, '
      'bytesFreedByEviction: $bytesFreedByEviction)';
}
```

`budgeted_planning_mutation_store.dart`:

```dart
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';

/// Enforces the local storage policy on the planning mutation store.
///
/// Only the `record*` methods are guarded: they are the ones that can
/// introduce a new aggregate. `saveSyncAttemptResult`, `retryMutation` and
/// `clearMutation` pass through, because they modify or shrink an existing
/// row — guarding them would make a full store unrecoverable, since discard
/// itself would become impossible.
class BudgetedPlanningMutationStore implements PlanningMutationStore {
  const BudgetedPlanningMutationStore({
    required PlanningMutationStore delegate,
    required PlanningStorageAccountant accountant,
    required SongCatalogEvictor evictor,
    required LocalStorageBudget budget,
  }) : _delegate = delegate,
       _accountant = accountant,
       _evictor = evictor,
       _budget = budget;

  final PlanningMutationStore _delegate;
  final PlanningStorageAccountant _accountant;
  final SongCatalogEvictor _evictor;
  final LocalStorageBudget _budget;

  Future<void> _guardedWrite(
    PlanningMutationContext context,
    Future<void> Function() write,
  ) async {
    final mutationBytes = await _accountant.measureMutationBytes(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    if (_budget.refusesNewMutation(mutationBytes)) {
      throw PlanningMutationBudgetExceededException(
        mutationBytes: mutationBytes,
        refuseBytes: _budget.mutationRefuseBytes,
      );
    }

    try {
      await write();
    } on LocalPlanningSlugConflictException {
      // A domain rejection, not storage pressure. Retrying it would fail
      // identically and evicting would destroy cached data for nothing.
      rethrow;
    } on PlanningMutationBudgetExceededException {
      rethrow;
    } catch (_) {
      // Storage failure. Give up droppable catalog sources, then retry once.
      // Every record* write is an upsert keyed by aggregate, so the retry is
      // idempotent: a partially applied first attempt cannot duplicate.
      final freed = await _evictor.evictDroppable();
      try {
        await write();
      } catch (retryError) {
        throw LocalStorageWriteFailure(
          cause: retryError,
          bytesFreedByEviction: freed,
        );
      }
    }
  }

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordPlanCreate(context: context, draft: draft),
  );

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordPlanEdit(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionCreate(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionRename(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionDelete(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionReorder(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionItemCreateSong(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionItemDelete(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionItemReorder(context: context, draft: draft),
  );

  // Unguarded pass-through: reads, and writes that modify or shrink an
  // existing row.

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) => _delegate.readPendingMutations(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) => _delegate.readActionableMutations(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) => _delegate.readAllMutations(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _delegate.readMutation(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) => _delegate.allocatePlanSlug(
    userId: userId,
    organizationId: organizationId,
    name: name,
  );

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) => _delegate.allocateSessionSlug(
    userId: userId,
    organizationId: organizationId,
    planId: planId,
    name: name,
  );

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) =>
      _delegate.hasUnsyncedMutations(userId: userId);

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) => _delegate.saveSyncAttemptResult(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    syncStatus: syncStatus,
    errorCode: errorCode,
    errorMessage: errorMessage,
  );

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _delegate.retryMutation(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _delegate.clearMutation(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );
}
```

- [x] **Step 4: Run the test to verify it passes**

```bash
(cd apps/lyron_app && flutter test test/application/planning/budgeted_planning_mutation_store_test.dart)
```

Expected: PASS, 5 tests.

- [x] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart \
        apps/lyron_app/lib/src/application/storage/local_storage_write_failure.dart \
        apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart \
        apps/lyron_app/test/application/planning/budgeted_planning_mutation_store_test.dart
git commit -m "feat(planning): enforce the mutation budget in a store decorator"
```

---

### Task 7: Promote the storage-pressure probe to an enforced contract

`storage_pressure_probe_test.dart` currently documents that a failed write
propagates. Now that there is a policy, it must assert the whole chain: failure
→ eviction attempted → one retry → typed `LocalStorageWriteFailure`.

**Files:**
- Modify: `apps/lyron_app/test/offline/adversarial/storage_pressure_probe_test.dart`

- [x] **Step 1: Rewrite the test body**

Keep `_InsertFailingExecutor`, `_InsertFailingTransactionExecutor` and
`StorageQuotaSimulatedException` exactly as they are. Replace the file's leading
doc comment and the `group`/`test` block with:

```dart
/// LF-T4 contract: when persisting a mutation FAILS at the storage layer
/// (simulated with a [QueryExecutor] decorator that throws on every INSERT,
/// standing in for a quota/IO failure), the app must give up droppable
/// catalog sources, retry once, and then surface a typed
/// [LocalStorageWriteFailure] to the caller. A swallowed failure would lose
/// the user's offline edit with no signal that it never reached storage.
///
/// This was a characterization probe until the mutation budget and eviction
/// policy landed; it now enforces the policy rather than observing behaviour.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('BudgetedPlanningMutationStore (LF-T4 storage pressure)', () {
    test('a failed write evicts droppable catalog sources, retries once, and '
        'surfaces a typed failure', () async {
      final failingExecutor = _InsertFailingExecutor(NativeDatabase.memory());
      final database = PlanningLocalDatabase.connect(failingExecutor);
      final localStore = DriftPlanningLocalStore(database);
      final catalogDatabase = SongCatalogDatabase.inMemory();
      addTearDown(database.close);
      addTearDown(catalogDatabase.close);

      await catalogDatabase
          .into(catalogDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'song-1',
              source: 'body ' * 200,
            ),
          );

      final store = BudgetedPlanningMutationStore(
        delegate: DriftPlanningMutationStore(
          database: database,
          localStore: localStore,
        ),
        accountant: PlanningStorageAccountant(database),
        evictor: SongCatalogEvictor(
          database: catalogDatabase,
          accountant: CatalogStorageAccountant(catalogDatabase),
        ),
        budget: const LocalStorageBudget(),
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await expectLater(
        () => store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-local-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        ),
        throwsA(
          isA<LocalStorageWriteFailure>().having(
            (failure) => failure.cause,
            'cause',
            isA<StorageQuotaSimulatedException>(),
          ),
        ),
      );

      // Eviction actually ran: the droppable source is gone.
      final remainingSources = await catalogDatabase
          .select(catalogDatabase.cachedCatalogSources)
          .get();
      expect(remainingSources, isEmpty);

      // The failed mutation must not be visible later either: it never
      // reached storage, so there is nothing to read back. This guards
      // against a "throws but partially commits anyway" false positive.
      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(pending, isEmpty);
    });
  });
}
```

Update the imports at the top of the file to add:

```dart
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
```

- [x] **Step 2: Run the test**

```bash
(cd apps/lyron_app && flutter test test/offline/adversarial/storage_pressure_probe_test.dart)
```

Expected: PASS.

If it fails because `readPendingMutations` also throws (the failing executor
only fails INSERTs, so SELECT should work), read the actual error before
changing anything — use superpowers:systematic-debugging rather than adjusting
the assertion to match.

- [x] **Step 3: Rename the file to match its new role**

```bash
git mv apps/lyron_app/test/offline/adversarial/storage_pressure_probe_test.dart \
       apps/lyron_app/test/offline/adversarial/storage_pressure_contract_test.dart
(cd apps/lyron_app && flutter test test/offline/adversarial/storage_pressure_contract_test.dart)
```

Expected: PASS.

- [x] **Step 4: Commit**

```bash
git add apps/lyron_app/test/offline/adversarial/
git commit -m "test(storage): enforce the storage-failure contract, not just observe it"
```

---

### Task 8: Monitor, providers and the sync UI warning

**Files:**
- Create: `apps/lyron_app/lib/src/application/storage/local_storage_monitor.dart`
- Modify: `apps/lyron_app/lib/src/application/core_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart`
- Modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart`
- Test: `apps/lyron_app/test/application/storage/local_storage_monitor_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/storage/local_storage_monitor.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('LocalStorageMonitor', () {
    late PlanningLocalDatabase database;
    late SongCatalogDatabase catalogDatabase;
    late DriftPlanningMutationStore mutationStore;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      catalogDatabase = SongCatalogDatabase.inMemory();
      mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: DriftPlanningLocalStore(database),
      );
    });

    tearDown(() async {
      await database.close();
      await catalogDatabase.close();
    });

    LocalStorageMonitor monitorWith(LocalStorageBudget budget) {
      return LocalStorageMonitor(
        planningAccountant: PlanningStorageAccountant(database),
        catalogAccountant: CatalogStorageAccountant(catalogDatabase),
        budget: budget,
      );
    }

    test('reports an empty footprint and ok pressure with no data', () async {
      final monitor = monitorWith(const LocalStorageBudget());

      final footprint = await monitor.measure(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(footprint.totalBytes, 0);
      expect(monitor.pressureOf(footprint), LocalStoragePressure.ok);
    });

    test('reports mutation bytes, count and warning pressure', () async {
      await mutationStore.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      final monitor = monitorWith(
        const LocalStorageBudget(
          mutationWarnBytes: 1,
          mutationRefuseBytes: 1000000,
        ),
      );

      final footprint = await monitor.measure(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(footprint.mutationCount, 1);
      expect(footprint.mutationBytes, greaterThan(0));
      expect(monitor.pressureOf(footprint), LocalStoragePressure.warning);
    });
  });
}
```

- [x] **Step 2: Run the test to verify it fails**

```bash
(cd apps/lyron_app && flutter test test/application/storage/local_storage_monitor_test.dart)
```

Expected: FAIL — `local_storage_monitor.dart` does not exist.

- [x] **Step 3: Write the monitor**

```dart
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';

/// Composes the planning and catalog accountants into one footprint and its
/// pressure level.
///
/// Runs on demand — when the sync surface asks — not on the write path. The
/// write path measures only mutation bytes, which is a single aggregate over
/// a small table.
class LocalStorageMonitor {
  const LocalStorageMonitor({
    required PlanningStorageAccountant planningAccountant,
    required CatalogStorageAccountant catalogAccountant,
    required LocalStorageBudget budget,
  }) : _planningAccountant = planningAccountant,
       _catalogAccountant = catalogAccountant,
       _budget = budget;

  final PlanningStorageAccountant _planningAccountant;
  final CatalogStorageAccountant _catalogAccountant;
  final LocalStorageBudget _budget;

  Future<LocalStorageFootprint> measure({
    required String userId,
    required String organizationId,
  }) async {
    final mutationBytes = await _planningAccountant.measureMutationBytes(
      userId: userId,
      organizationId: organizationId,
    );
    final mutationCount = await _planningAccountant.measureMutationCount(
      userId: userId,
      organizationId: organizationId,
    );
    final projectionBytes = await _planningAccountant.measureProjectionBytes();
    final catalogBytes = await _catalogAccountant.measureCatalogBytes();

    return LocalStorageFootprint(
      mutationBytes: mutationBytes,
      mutationCount: mutationCount,
      projectionBytes: projectionBytes,
      catalogBytes: catalogBytes,
    );
  }

  LocalStoragePressure pressureOf(LocalStorageFootprint footprint) =>
      _budget.classify(footprint);
}
```

- [x] **Step 4: Run the test to verify it passes**

```bash
(cd apps/lyron_app && flutter test test/application/storage/local_storage_monitor_test.dart)
```

Expected: PASS, 2 tests.

- [x] **Step 5: Wire the providers**

In `core_providers.dart` (both databases already live there), add after the
database providers:

```dart
final localStorageBudgetProvider = Provider<LocalStorageBudget>((ref) {
  return const LocalStorageBudget();
});

final planningStorageAccountantProvider = Provider<PlanningStorageAccountant>((
  ref,
) {
  return PlanningStorageAccountant(ref.watch(planningLocalDatabaseProvider));
});

final catalogStorageAccountantProvider = Provider<CatalogStorageAccountant>((
  ref,
) {
  return CatalogStorageAccountant(ref.watch(songCatalogDatabaseProvider));
});

final songCatalogEvictorProvider = Provider<SongCatalogEvictor>((ref) {
  return SongCatalogEvictor(
    database: ref.watch(songCatalogDatabaseProvider),
    accountant: ref.watch(catalogStorageAccountantProvider),
  );
});

final localStorageMonitorProvider = Provider<LocalStorageMonitor>((ref) {
  return LocalStorageMonitor(
    planningAccountant: ref.watch(planningStorageAccountantProvider),
    catalogAccountant: ref.watch(catalogStorageAccountantProvider),
    budget: ref.watch(localStorageBudgetProvider),
  );
});
```

with the matching imports:

```dart
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_monitor.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
```

In `planning_providers.dart`, wrap the existing store:

```dart
final planningMutationStoreProvider = Provider<PlanningMutationStore>((ref) {
  return BudgetedPlanningMutationStore(
    delegate: DriftPlanningMutationStore(
      database: ref.watch(planningLocalDatabaseProvider),
      localStore: ref.watch(planningLocalStoreProvider),
    ),
    accountant: ref.watch(planningStorageAccountantProvider),
    evictor: ref.watch(songCatalogEvictorProvider),
    budget: ref.watch(localStorageBudgetProvider),
  );
});
```

with the import:

```dart
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
```

- [x] **Step 6: Surface the pressure in the sync overview**

In `unified_sync_overview.dart`, add the field to `UnifiedSyncOverview`:

```dart
class UnifiedSyncOverview {
  const UnifiedSyncOverview({
    required this.headerStatus,
    required this.activity,
    required this.connectivity,
    required this.freshness,
    required this.songRows,
    required this.planRows,
    required this.hasUnsyncedWork,
    this.storagePressure = LocalStoragePressure.ok,
    this.pendingMutationCount = 0,
  });
```

Add the fields next to `hasUnsyncedWork`:

```dart
  /// Local storage pressure (LF-T4). `warning` means the user should sync
  /// soon; `critical` means new offline edits may be refused.
  final LocalStoragePressure storagePressure;

  /// Pending planning mutation count, shown alongside the pressure warning so
  /// the user can see what syncing would drain.
  final int pendingMutationCount;
```

and the import:

```dart
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
```

The `const UnifiedSyncOverview.initial()` constructor keeps working because both
new fields have defaults.

In `unified_sync_providers.dart`, find where `UnifiedSyncOverview` is
constructed and pass the measured values through, reading
`localStorageMonitorProvider` for the active context. Follow the file's existing
composition style rather than introducing a new pattern.

- [x] **Step 7: Run the whole suite**

```bash
(cd apps/lyron_app && flutter test)
```

Expected: PASS. Existing tests that construct `UnifiedSyncOverview` are
unaffected because the new fields are optional.

- [x] **Step 8: Commit**

```bash
git add apps/lyron_app/lib/src/application/storage/local_storage_monitor.dart \
        apps/lyron_app/lib/src/application/core_providers.dart \
        apps/lyron_app/lib/src/application/planning_providers.dart \
        apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart \
        apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart \
        apps/lyron_app/test/application/storage/local_storage_monitor_test.dart
git commit -m "feat(storage): surface local storage pressure in the sync overview"
```

---

### Task 9: Documentation

**Files:**
- Create: `docs/architecture/decisions/ADR-028-local-storage-budget-and-eviction-policy.md`
- Modify: `docs/architecture/architecture.md` (Offline Strategy)
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/architecture/repository-review-2026-06-22.md`
- Delete: `docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`

- [x] **Step 1: Write the ADR**

Follow the structure of `docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md`.
Carry decisions D1–D6 from the spec, and state explicitly:

- the two ladders, and why catalog eviction cannot relieve the mutation budget;
- the protection order, including that catalog **summaries** stay and only
  **sources** are droppable;
- that accounting is a content-derived proxy, not true on-disk size;
- that verification is native-only, that the web IndexedDB assumptions are
  therefore unverified, and that
  `docs/deferred/2026-06-29-web-offline-e2e.md` remains the prerequisite for
  relying on IndexedDB capacity assumptions;
- the consequence that after eviction a song body requires connectivity until
  the next catalog refresh;
- that eviction and budgeting are local storage policy and never an
  authorization decision (AGENTS.md rule 5).

- [x] **Step 2: Update `architecture.md`**

In the Offline Strategy section, replace the "one active snapshot" framing with
the protection order and the accounting seam, and link the ADR.

- [x] **Step 3: Update `testing-strategy.md`**

Record the new contracts: the squash/OCC contract suite, the eviction protection
contracts, and that the former storage-pressure *probe* is now an enforced
contract.

- [x] **Step 4: Mark LF-T3 and LF-T4 fixed**

In `docs/architecture/repository-review-2026-06-22.md`, strike both rows using
the existing `~~struck~~ **Done (...)**` convention, and update the §6 status
block in the same style already used there.

- [x] **Step 5: Remove the resolved deferred doc**

```bash
git rm docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md
```

Leave `docs/deferred/2026-06-29-web-offline-e2e.md` untouched.

- [x] **Step 6: Verify and commit**

```bash
./scripts/verify.sh --skip-migrations --skip-backend-write-contracts
```

Expected: format clean, analyze clean, all tests pass, coverage gate passes.

```bash
git add docs/
git commit -m "docs(storage): ADR-028 local storage budget and eviction policy"
```

---

## Self-Review

**Spec coverage:**

| spec item | task |
|---|---|
| D1 two ladders | 6 (refuse vs. evict-and-retry) |
| D2 content-derived accounting | 4, 5 |
| D3 decorator enforcement | 6 |
| D4 protection order | 5 (evictor), 6 (guard exclusions) |
| D5 native-only verification | 9 (ADR) |
| D6 thresholds | 3 |
| squash correctness fix | 1, 2 |
| testing contracts 1–7 | 1 (1), 5 (2, 3), 6 (4), 7 (5), 2 (6), 4 (7) |
| warning surface | 8 |
| documentation | 9 |

**Type consistency:** `measureMutationBytes` / `measureMutationCount` /
`measureProjectionBytes` (planning), `measureCatalogBytes` /
`measureDroppableBytes` (catalog), `evictDroppable` (evictor), `classify` /
`refusesNewMutation` (budget), `measure` / `pressureOf` (monitor) — used
consistently in Tasks 4–8 and in the provider wiring.

**Known follow-up left open deliberately:** `unified_sync_providers.dart` step 6
describes the integration rather than showing final code, because the file's
composition shape must be read at implementation time; the contract it must
satisfy (pass measured footprint and pressure into `UnifiedSyncOverview`) is
fixed here.
