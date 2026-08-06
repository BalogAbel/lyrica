import 'dart:async';

import 'package:drift/backends.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';
import '../../support/insert_failing_executor.dart'
    show StorageQuotaSimulatedException;

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
        recovery: LocalStorageWriteRecovery(evictor: evictor),
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
        recovery: LocalStorageWriteRecovery(evictor: evictor),
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

    test(
      'asserts instead of silently deadlocking when a delegate call reenters '
      'the queue for the SAME context (N4, PR #64 review) -- pins the '
      "invariant _enqueue's own doc already states in prose",
      () async {
        final reentrant = _ReentrantPlanningMutationStore();
        final store = BudgetedPlanningMutationStore(
          delegate: reentrant,
          accountant: accountant,
          recovery: LocalStorageWriteRecovery(evictor: evictor),
          budget: const LocalStorageBudget(mutationRefuseBytes: 1000000),
        );
        const reentrantDraft = PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        );
        reentrant.reentrantTarget = store;
        reentrant.reentrantContext = context;
        reentrant.reentrantDraft = reentrantDraft;

        await expectLater(
          () => store.recordPlanCreate(context: context, draft: reentrantDraft),
          throwsA(isA<AssertionError>()),
        );
      },
    );

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

    test('admits a session delete against a `sending` pending create even at '
        'an exhausted budget, rewriting it as a cancellation tombstone rather '
        'than a fresh row (ADR-028 D10: this does not shrink the store -- it '
        'is admitted because refusing it would strand the delete intent for '
        'a create already in flight to the backend)', () async {
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
      final created = await permissive.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      // Simulate the sync's D1 durable marker, written immediately before
      // the remote call (docs/specs/2026-08-06-in-flight-create-cancellation.md).
      await permissive.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
        syncStatus: PlanningMutationSyncStatus.sending,
        expectedRevision: created!.localRevision,
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      // Must not throw PlanningMutationBudgetExceededException, even
      // though rewriting the row in place cannot shrink the store the
      // way a physical collapse does.
      await exhausted.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      final afterDelete = await exhausted.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      expect(afterDelete, isNotNull);
      expect(afterDelete!.kind, PlanningMutationKind.sessionCreate);
      expect(afterDelete.syncStatus, PlanningMutationSyncStatus.cancelling);
    });

    test('admits a session delete against an accepted-but-uncleared pending '
        'create even at an exhausted budget, converting it to a real pending '
        'delete rather than a fresh row (ADR-028 D10: this does not shrink '
        'the store either -- it is admitted because the backend already has '
        'the create, so refusing it would strand a delete the user can no '
        'longer express any other way)', () async {
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
      final created = await permissive.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      // Simulate the accepted-but-uncleared window: the backend confirmed
      // the create, but the sync's own clearMutation has not run yet.
      await permissive.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
        expectedRevision: created!.localRevision,
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      await exhausted.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      final afterDelete = await exhausted.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      expect(afterDelete, isNotNull);
      expect(afterDelete!.kind, PlanningMutationKind.sessionDelete);
      expect(afterDelete.syncStatus, PlanningMutationSyncStatus.pending);
    });

    test('saveSyncAttemptResult is never refused for budget reasons, even '
        'with the budget exhausted', () async {
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

      // Must not throw PlanningMutationBudgetExceededException: this is
      // sync bookkeeping for a mutation the backend already accepted --
      // refusing it would strand the durable marker that prevents a resend
      // (ADR-019 exactly-once).
      await exhausted.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      final record = await exhausted.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(record?.syncStatus, PlanningMutationSyncStatus.accepted);
    });

    test('the collapse race: a clearMutation concurrent with a collapsing '
        'recordSessionDelete never results in a new delete row admitted '
        'without a budget check -- either the collapse lands, or (if the '
        'race were resolved the other way) the write would be refused by '
        'the budget, but never silently grown', () async {
      // A fake delegate, not real Drift, so the interleaving is gated
      // purely by Completers -- no reliance on real-database timing.
      // readMutation (used by the decorator's collapse decision) always
      // answers from current state instantly; recordSessionDelete pauses
      // BEFORE its own internal re-check (mirroring
      // DriftPlanningMutationStore.recordSessionDelete's `existing =
      // await readMutation(...)` inside its own transaction), so a
      // concurrent clearMutation issued while it is paused can be
      // observed by that re-check exactly like the real delegate would.
      final fakeDelegate = _CollapseRaceMutationStore(
        initialSessionKind: PlanningMutationKind.sessionCreate,
      );
      final store = BudgetedPlanningMutationStore(
        delegate: fakeDelegate,
        accountant: accountant,
        recovery: LocalStorageWriteRecovery(evictor: evictor),
        budget: const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      final pauseGate = Completer<void>();
      fakeDelegate.gateNextRecordSessionDelete(pauseGate);

      final deleteFuture = store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      // Blocks until the decorator's collapse decision has already run
      // (it must, in program order, before recordSessionDelete's paused
      // body is even reached) and the fake's write is now paused, having
      // not yet re-read or mutated state.
      await fakeDelegate.entered.future;

      // Issued while the write is paused. Whether this actually mutates
      // state before or after the write's own re-check is exactly what
      // this test pins: unqueued (today), the fake delegate's body runs
      // synchronously here, before the write resumes. Queued (after the
      // fix), it is chained behind the write's still-pending queue slot
      // and cannot run until the write settles.
      final clearFuture = store.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session',
        aggregateId: 'session-1',
      );

      pauseGate.complete();

      await Future.wait([
        deleteFuture,
        clearFuture,
      ]).timeout(const Duration(seconds: 2));

      // Never a new sessionDelete row admitted without ever passing the
      // budget check: the outcome must be the collapse (kind == null),
      // not growth.
      expect(
        fakeDelegate.currentSessionKind,
        isNot(PlanningMutationKind.sessionDelete),
      );
      expect(fakeDelegate.currentSessionKind, isNull);
    });
  });

  group('BudgetedPlanningMutationStore.saveSyncAttemptResult recovery '
      '(finding 1)', () {
    late PlanningLocalDatabase failingDatabase;
    late SongCatalogDatabase evictionDatabase;
    late _RecordingEvictor recordingEvictor;

    const seedContext = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    tearDown(() async {
      await failingDatabase.close();
      await evictionDatabase.close();
    });

    // Builds a real Drift-backed store whose INSERT calls fail on the
    // 0-indexed call numbers in `failOnCalls`. Call #0 is always the seed
    // write (recordPlanCreate), so every scenario below starts from a real
    // pending mutation that saveSyncAttemptResult can update.
    Future<BudgetedPlanningMutationStore> buildStoreFailingOnCalls(
      Set<int> failOnCalls,
    ) async {
      final script = _InsertCallScript(failOnCalls);
      failingDatabase = PlanningLocalDatabase.connect(
        _ScriptedInsertExecutor(NativeDatabase.memory(), script),
      );
      evictionDatabase = SongCatalogDatabase.inMemory();
      recordingEvictor = _RecordingEvictor(
        SongCatalogEvictor(
          database: evictionDatabase,
          accountant: CatalogStorageAccountant(evictionDatabase),
        ),
      );

      final delegate = DriftPlanningMutationStore(
        database: failingDatabase,
        localStore: DriftPlanningLocalStore(failingDatabase),
      );
      final store = BudgetedPlanningMutationStore(
        delegate: delegate,
        accountant: PlanningStorageAccountant(failingDatabase),
        recovery: LocalStorageWriteRecovery(evictor: recordingEvictor),
        budget: const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );

      await store.recordPlanCreate(
        context: seedContext,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      return store;
    }

    test('evicts droppable sources, retries once, and -- when the retry still '
        'fails -- surfaces a typed LocalStorageWriteFailure rather than the '
        'raw storage exception', () async {
      // Insert #0 is the seed (succeeds); #1 is the first status-write
      // attempt and #2 is its retry -- both fail.
      final store = await buildStoreFailingOnCalls({1, 2});

      await expectLater(
        () => store.saveSyncAttemptResult(
          userId: seedContext.userId,
          organizationId: seedContext.organizationId,
          aggregateType: 'plan',
          aggregateId: 'plan-1',
          syncStatus: PlanningMutationSyncStatus.accepted,
        ),
        throwsA(
          isA<LocalStorageWriteFailure>().having(
            (failure) => failure.cause,
            'cause',
            isA<StorageQuotaSimulatedException>(),
          ),
        ),
      );

      expect(recordingEvictor.calls, 1);
    });

    test('a transient failure on the status write recovers on retry, and the '
        'record carries the new status afterwards', () async {
      // Insert #0 is the seed (succeeds); #1 (the first attempt) fails;
      // #2 (the retry) is not in the script, so it succeeds.
      final store = await buildStoreFailingOnCalls({1});

      await store.saveSyncAttemptResult(
        userId: seedContext.userId,
        organizationId: seedContext.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      expect(recordingEvictor.calls, 1);
      final record = await store.readMutation(
        userId: seedContext.userId,
        organizationId: seedContext.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(record?.syncStatus, PlanningMutationSyncStatus.accepted);
    });
  });
}

/// A delegate that (incorrectly) calls back into its own owning
/// [BudgetedPlanningMutationStore] for the SAME context from inside
/// `recordPlanCreate` -- exactly the self-deadlock `_enqueue`'s class doc
/// prohibits in prose. Used only to pin the N4 reentrancy assert; every
/// other member is unused and throws if called.
class _ReentrantPlanningMutationStore implements PlanningMutationStore {
  late BudgetedPlanningMutationStore reentrantTarget;
  late PlanningMutationContext reentrantContext;
  late PlanningPlanCreateMutationDraft reentrantDraft;

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) {
    return reentrantTarget.recordPlanCreate(
      context: reentrantContext,
      draft: reentrantDraft,
    );
  }

  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) => throw UnimplementedError();

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
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => throw UnimplementedError();

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) => throw UnimplementedError();
}

/// Minimal fake delegate for concurrency tests that need direct control over
/// when a write's `Future` resolves, keyed by `'${userId}_${organizationId}'`.
/// Only `recordPlanCreate` is hooked; every other member is unused by these
/// tests and throws if called.
class _HookedPlanningMutationStore implements PlanningMutationStore {
  // Stub for docs/specs/2026-08-06-in-flight-create-cancellation.md (D3):
  // none of these tests exercise the in-flight-create-cancellation
  // tombstone path, which is covered against the real
  // DriftPlanningMutationStore in
  // test/offline/adversarial/planning_in_flight_create_cancellation_test.dart.
  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) async => false;
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
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => throw UnimplementedError();

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
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

/// Shared mutable counter for [_ScriptedInsertExecutor] /
/// [_ScriptedInsertTransactionExecutor]: unlike `InsertFailureBudget`'s
/// "fail the next N inserts forever" (test/support/insert_failing_executor.dart),
/// a storage-recovery test on `saveSyncAttemptResult` needs to seed a real
/// pending mutation first (an INSERT that must succeed) and only then fail
/// the status write under test -- so failures are scripted by 0-indexed
/// call number instead of a countdown. Shared by reference across every
/// executor spawned from the same root, since Drift issues the real
/// `INSERT` through a fresh [TransactionExecutor] inside
/// `database.transaction`, not the top-level [QueryExecutor]
/// `saveSyncAttemptResult` itself uses.
class _InsertCallScript {
  _InsertCallScript(this._failOnCalls);

  final Set<int> _failOnCalls;
  int _calls = 0;

  bool shouldFail() {
    final index = _calls;
    _calls += 1;
    return _failOnCalls.contains(index);
  }
}

/// Whether [statement] is the `UPDATE ... RETURNING ...` Drift generates for
/// `saveSyncAttemptResult` (M2, PR #64 review): that statement returns rows
/// (the new `local_revision`), so -- unlike a plain `UPDATE` -- Drift's
/// [QueryExecutor] contract requires it to be dispatched through [runSelect],
/// not [runUpdate]. A prefix check is enough to tell it apart from the
/// store's ordinary reads (budget measurement, `readMutation`, ...), none of
/// which are `UPDATE` statements.
bool _looksLikeUpdateReturning(String statement) =>
    statement.trimLeft().toUpperCase().startsWith('UPDATE');

/// A [QueryExecutor] decorator that delegates everything except `runInsert`,
/// `runUpdate`, and the `UPDATE ... RETURNING` subset of `runSelect`
/// ([_looksLikeUpdateReturning]), which fail on the call numbers named in the
/// shared [_InsertCallScript]. Mirrors `test/support/insert_failing_executor.dart`'s
/// `InsertFailingExecutor` shape, just with a script instead of a countdown.
///
/// All three share the SAME counter (not independent ones):
/// `saveSyncAttemptResult`'s status write (docs/specs/2026-08-05-sync-
/// snapshot-identity.md, D2) is a targeted, revision-guarded `UPDATE ...
/// RETURNING`, not the `INSERT ... ON CONFLICT DO UPDATE` upsert every
/// `record*` write uses -- the atomic WHERE-guarded write the D2 conditional
/// write requires cannot be expressed as an upsert, and the `RETURNING`
/// clause (needed so the new `local_revision` is read atomically with the
/// write itself, M2) is why it goes through `runSelect` rather than
/// `runUpdate`. The seed write below (`recordPlanCreate`) is still an
/// INSERT, so it is call #0 either way.
class _ScriptedInsertExecutor implements QueryExecutor {
  _ScriptedInsertExecutor(this._delegate, this._script);

  final QueryExecutor _delegate;
  final _InsertCallScript _script;

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _delegate.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) {
    if (_looksLikeUpdateReturning(statement) && _script.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    if (_script.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    if (_script.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() =>
      _ScriptedInsertTransactionExecutor(_delegate.beginTransaction(), _script);

  @override
  QueryExecutor beginExclusive() =>
      _ScriptedInsertExecutor(_delegate.beginExclusive(), _script);

  @override
  Future<void> close() => _delegate.close();
}

/// Transaction-scoped counterpart of [_ScriptedInsertExecutor], sharing the
/// same [_InsertCallScript] so call numbering is consistent whether an
/// INSERT lands via the top-level executor or inside a
/// `database.transaction` block.
class _ScriptedInsertTransactionExecutor implements TransactionExecutor {
  _ScriptedInsertTransactionExecutor(this._delegate, this._script);

  final TransactionExecutor _delegate;
  final _InsertCallScript _script;

  @override
  bool get supportsNestedTransactions => _delegate.supportsNestedTransactions;

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _delegate.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) {
    if (_looksLikeUpdateReturning(statement) && _script.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    if (_script.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    if (_script.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() =>
      _ScriptedInsertTransactionExecutor(_delegate.beginTransaction(), _script);

  @override
  QueryExecutor beginExclusive() =>
      _ScriptedInsertExecutor(_delegate.beginExclusive(), _script);

  @override
  Future<void> send() => _delegate.send();

  @override
  Future<void> rollback() => _delegate.rollback();

  @override
  Future<void> close() => _delegate.close();
}

/// Fake delegate for the finding-2 collapse-race test. Deliberately not a
/// real Drift store: the race is gated purely by Completers, so it must be
/// possible to pause `recordSessionDelete` at an exact point with no real
/// storage/IO uncertainty in between.
///
/// `readMutation` always answers instantly from current state -- it models
/// the decorator's OWN early collapse-decision read
/// (`_collapsesPendingCreate`), which must never be paused, since pausing
/// it would test something other than the race this exists to reproduce.
///
/// `recordSessionDelete` pauses on the gate installed by
/// [gateNextRecordSessionDelete] BEFORE doing anything else, then -- once
/// released -- re-reads `_sessionKind` and either collapses (kind was still
/// `sessionCreate`: clears it) or grows (anything else: sets it to
/// `sessionDelete`), mirroring
/// `DriftPlanningMutationStore.recordSessionDelete`'s own internal
/// `existing?.kind == sessionCreate` re-check inside its transaction.
class _CollapseRaceMutationStore implements PlanningMutationStore {
  // Stub for docs/specs/2026-08-06-in-flight-create-cancellation.md (D3):
  // none of these tests exercise the in-flight-create-cancellation
  // tombstone path, which is covered against the real
  // DriftPlanningMutationStore in
  // test/offline/adversarial/planning_in_flight_create_cancellation_test.dart.
  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) async => false;
  _CollapseRaceMutationStore({
    required PlanningMutationKind? initialSessionKind,
  }) : _sessionKind = initialSessionKind;

  PlanningMutationKind? _sessionKind;
  Completer<void>? _pauseGate;

  /// Completes the moment `recordSessionDelete` is entered and about to
  /// await the pause gate -- proof that the decorator's collapse decision
  /// (which runs strictly earlier, in `_admitAndWrite`'s program order) has
  /// already resolved.
  final Completer<void> entered = Completer<void>();

  PlanningMutationKind? get currentSessionKind => _sessionKind;

  void gateNextRecordSessionDelete(Completer<void> gate) {
    _pauseGate = gate;
  }

  bool _isSessionOne(String aggregateType, String aggregateId) =>
      aggregateType == 'session' && aggregateId == 'session-1';

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    if (!_isSessionOne(aggregateType, aggregateId) || _sessionKind == null) {
      return null;
    }
    return PlanningMutationRecord(
      aggregateId: aggregateId,
      organizationId: organizationId,
      kind: _sessionKind!,
      syncStatus: PlanningMutationSyncStatus.pending,
      orderKey: 0,
      updatedAt: DateTime.utc(2026, 8, 4),
    );
  }

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {
    final gate = _pauseGate;
    if (gate != null) {
      _pauseGate = null;
      if (!entered.isCompleted) {
        entered.complete();
      }
      await gate.future;
    }
    _sessionKind = _sessionKind == PlanningMutationKind.sessionCreate
        ? null
        : PlanningMutationKind.sessionDelete;
  }

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async {
    if (_isSessionOne(aggregateType, aggregateId)) {
      _sessionKind = null;
      return true;
    }
    return false;
  }

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) => throw UnimplementedError();

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
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => throw UnimplementedError();
}
