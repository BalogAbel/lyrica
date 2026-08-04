import 'dart:async';

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
      // Seed one mutation under a permissive budget so the store has a real
      // footprint. A budget refusal means "the store is ALREADY at or past
      // budget" -- against an empty store there is nothing to refuse.
      await storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      ).recordPlanCreate(
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

    test('a refused fold leaves the pending aggregate it would have folded '
        'into completely intact', () async {
      await storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      ).recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      await expectLater(
        () => exhausted.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-1',
            name: 'Renamed',
          ),
        ),
        throwsA(isA<PlanningMutationBudgetExceededException>()),
      );

      // Enforcing the budget must never destroy unsynced intent. An edit
      // that folds into a still-pending create must leave that create
      // exactly as it was -- not partially applied, and above all not
      // deleted as a side effect of refusing the edit.
      final pending = await exhausted.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(pending, hasLength(1));
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.name, 'Weekend Service');
      expect(pending.single.description, 'Original description');
    });

    test(
      'propagates a domain slug conflict without eviction or retry',
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
      },
    );

    test('serialises the measure-check-write sequence so concurrent writes for '
        'different aggregates in the same context cannot all pass the same '
        'pre-write measurement', () async {
      // Threshold of 1 admits only a store that is still empty (0 bytes).
      // Every real mutation row costs at least kLocalStorageRowOverheadBytes
      // (64), so once ANY one of these writes lands, every write measured
      // afterwards must see a footprint >= 1 and be refused. Without
      // serialising measure+check+write per context, three concurrent
      // writes can all measure the empty store before any of them lands,
      // so all three pass the check and all three write.
      final store = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      Future<Object?> asOutcome(Future<void> future) =>
          future.then<Object?>((_) => null, onError: (Object error) => error);

      final outcomes = await Future.wait<Object?>([
        asOutcome(
          store.recordPlanCreate(
            context: context,
            draft: const PlanningPlanCreateMutationDraft(
              planId: 'plan-1',
              slug: 'plan-one',
              name: 'Plan One',
            ),
          ),
        ),
        asOutcome(
          store.recordSessionCreate(
            context: context,
            draft: const PlanningSessionCreateMutationDraft(
              sessionId: 'session-1',
              planId: 'plan-x',
              slug: 'session-one',
              name: 'Session One',
              position: 0,
            ),
          ),
        ),
        asOutcome(
          store.recordSessionItemCreateSong(
            context: context,
            draft: const PlanningSessionItemCreateSongMutationDraft(
              sessionItemId: 'item-1',
              sessionId: 'session-x',
              planId: 'plan-x',
              songId: 'song-1',
              songTitle: 'Song One',
              position: 0,
            ),
          ),
        ),
      ]);

      final succeeded = outcomes.where((outcome) => outcome == null).length;
      final refused = outcomes
          .whereType<PlanningMutationBudgetExceededException>()
          .length;

      expect(
        succeeded,
        1,
        reason: 'exactly one concurrent write should be admitted: $outcomes',
      );
      expect(refused, 2);
    });

    test('does not serialise across different (userId, organizationId) '
        'contexts', () async {
      // A fake delegate lets this test control write timing directly,
      // independent of the real budget accounting (which would otherwise
      // interact with the concurrency being tested here). Context A's
      // write blocks on a completer that only context B's write --  a
      // DIFFERENT context -- completes. If serialisation were keyed
      // globally instead of per context, B's write would be queued behind
      // A's (which can never finish without B running first), deadlocking
      // forever. Per-context serialisation lets B run immediately.
      final delegateFake = _HookedPlanningMutationStore();
      final store = BudgetedPlanningMutationStore(
        delegate: delegateFake,
        accountant: accountant,
        evictor: evictor,
        budget: const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );

      const contextA = PlanningMutationContext(
        userId: 'user-a',
        organizationId: 'org-a',
      );
      const contextB = PlanningMutationContext(
        userId: 'user-b',
        organizationId: 'org-b',
      );

      final bStarted = Completer<void>();

      delegateFake.onRecordPlanCreate['user-a_org-a'] = () => bStarted.future;
      delegateFake.onRecordPlanCreate['user-b_org-b'] = () async {
        if (!bStarted.isCompleted) bStarted.complete();
      };

      final aFuture = store.recordPlanCreate(
        context: contextA,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-a',
          slug: 'plan-a',
          name: 'Plan A',
        ),
      );

      await store
          .recordPlanCreate(
            context: contextB,
            draft: const PlanningPlanCreateMutationDraft(
              planId: 'plan-b',
              slug: 'plan-b',
              name: 'Plan B',
            ),
          )
          .timeout(const Duration(seconds: 2));

      await aFuture.timeout(const Duration(seconds: 2));
    });

    test('admits a session delete that collapses a still-pending session '
        'create even at an exhausted budget, and removes the session plus '
        'its pending item and item-order rows', () async {
      final permissive = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );
      await permissive.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 0,
        ),
      );
      await permissive.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song One',
          position: 0,
        ),
      );
      await permissive.recordSessionItemReorder(
        context: context,
        draft: const PlanningSessionItemReorderMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          orderedSessionItemIds: ['item-1'],
        ),
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      // Must not throw PlanningMutationBudgetExceededException: deleting a
      // still-pending create shrinks the store, so it is admitted
      // regardless of budget.
      await exhausted.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      expect(
        await exhausted.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'session',
          aggregateId: 'session-1',
        ),
        isNull,
      );
      expect(
        await exhausted.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'session_item',
          aggregateId: 'item-1',
        ),
        isNull,
      );
      expect(
        await exhausted.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'session_item_order',
          aggregateId: 'session-1',
        ),
        isNull,
      );
    });

    test('admits a session-item delete that collapses a still-pending '
        'session-item create even at an exhausted budget', () async {
      final permissive = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );
      await permissive.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 0,
        ),
      );
      await permissive.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song One',
          position: 0,
        ),
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      await exhausted.recordSessionItemDelete(
        context: context,
        draft: const PlanningSessionItemDeleteMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      expect(
        await exhausted.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'session_item',
          aggregateId: 'item-1',
        ),
        isNull,
      );
    });

    test(
      'still refuses a session delete that is not collapsing a pending '
      'create, even though it is the same method as the collapse case',
      () async {
        // Seed an UNRELATED pending mutation so the store is genuinely over
        // budget. The session targeted below has no local mutation of its
        // own (as if it is synced and unmodified locally), so deleting it
        // adds a brand new sessionDelete row -- it grows the store rather
        // than shrinking it, and must stay subject to the budget exactly
        // like any other write. The admission decision has to come from
        // store state (is there a pending create to collapse?), not from
        // the method name alone.
        await storeWithBudget(
          const LocalStorageBudget(mutationRefuseBytes: 1000000),
        ).recordPlanCreate(
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
          () => exhausted.recordSessionDelete(
            context: context,
            draft: const PlanningSessionDeleteMutationDraft(
              sessionId: 'session-1',
              planId: 'plan-1',
            ),
          ),
          throwsA(isA<PlanningMutationBudgetExceededException>()),
        );
      },
    );
  });
}

/// Minimal fake delegate for concurrency tests that need direct control over
/// when a write's `Future` resolves, keyed by `'${userId}_${organizationId}'`.
/// Only `recordPlanCreate` is hooked; every other member is unused by these
/// tests and throws if called.
class _HookedPlanningMutationStore implements PlanningMutationStore {
  final Map<String, Future<void> Function()> onRecordPlanCreate = {};

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {
    final key = '${context.userId}_${context.organizationId}';
    final hook = onRecordPlanCreate[key];
    if (hook != null) await hook();
  }

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => throw UnimplementedError();

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) => throw UnimplementedError();

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) => throw UnimplementedError();

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) =>
      throw UnimplementedError();

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) => throw UnimplementedError();

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => throw UnimplementedError();

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => throw UnimplementedError();
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
