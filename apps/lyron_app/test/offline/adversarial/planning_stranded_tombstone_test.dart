import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/planning_run_fixtures.dart';

/// Adversarial coverage for S5b PR 2 (MG6): a `cancelling` create tombstone
/// that no run resolved (a crash between the create's response and
/// `resolveCancelledCreate`) is converted into a pending delete at the start
/// of the next run, and that delete's `*_not_found` answer closes the row only
/// while the row still carries the tombstone-origin marker. Real storage
/// boundary and sync controller against a scripted backend.
void main() {
  const context = PlanningMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  const readContext = ActivePlanningReadContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  const remoteMissing = PlanningMutationSyncException(
    PlanningMutationSyncErrorCode.remoteMissing,
  );

  late PlanningLocalDatabase db;
  late DriftPlanningLocalStore localStore;
  late DriftPlanningMutationStore store;
  late PlanningMutationReconciler reconciler;

  setUp(() async {
    db = PlanningLocalDatabase.inMemory();
    localStore = DriftPlanningLocalStore(db);
    store = DriftPlanningMutationStore(database: db, localStore: localStore);
    reconciler = PlanningMutationReconciler(localStore: () => localStore);
    await seedPlanningProjection(localStore, contentVersion: 3);
  });

  tearDown(() async {
    await db.close();
  });

  PlanningMutationSyncController controllerFor(
    PlanningMutationRemoteRepository remote,
  ) => PlanningMutationSyncController(
    mutationStore: () => store,
    remoteRepository: () => remote,
    refreshPlanning: (_) async => false,
    isRunContextActive: (_) => true,
    reconcileAcceptedMutation: reconciler.reconcile,
  );

  Future<List<PlanningMutationRecord>> allRows() =>
      store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

  Future<PlanningMutationRecord?> read(String aggregateType, String id) =>
      store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: aggregateType,
        aggregateId: id,
      );

  Future<void> markSending(String aggregateType, String aggregateId) async {
    final row = await read(aggregateType, aggregateId);
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      syncStatus: PlanningMutationSyncStatus.sending,
      expectedRevision: row!.localRevision,
    );
  }

  // Strands a tombstone: the create was `sending` when the user deleted the
  // aggregate and no run ever resolved the row.
  Future<void> strandPlan() async {
    await store.recordPlanCreate(
      context: context,
      draft: const PlanningPlanCreateMutationDraft(
        planId: 'plan-1',
        slug: 'plan-1',
        name: 'Created',
      ),
    );
    await markSending('plan', 'plan-1');
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(planId: 'plan-1'),
    );
  }

  Future<void> strandSession() async {
    await store.recordSessionCreate(
      context: context,
      draft: const PlanningSessionCreateMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        slug: 'session-1',
        name: 'Created',
        position: 1,
      ),
    );
    await markSending('session', 'session-1');
    await store.recordSessionDelete(
      context: context,
      draft: const PlanningSessionDeleteMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
      ),
    );
  }

  Future<void> strandItem({int baseVersion = 2}) async {
    await store.recordSessionItemCreateSong(
      context: context,
      draft: PlanningSessionItemCreateSongMutationDraft(
        sessionItemId: 'item-9',
        sessionId: 'session-1',
        planId: 'plan-1',
        songId: 'song-1',
        songTitle: 'Song',
        position: 2,
        baseVersion: baseVersion,
      ),
    );
    await markSending('session_item', 'item-9');
    await store.recordSessionItemDelete(
      context: context,
      draft: const PlanningSessionItemDeleteMutationDraft(
        sessionItemId: 'item-9',
        sessionId: 'session-1',
        planId: 'plan-1',
      ),
    );
  }

  test('a stranded plan create tombstone whose create committed is deleted '
      'by the next run', () async {
    await strandPlan();
    final remote = ScriptedPlanningRemote((record) async => record);

    await controllerFor(remote).syncPendingMutations(readContext);

    final call = remote.calls.single;
    expect(call.kind, PlanningMutationKind.planDelete);
    expect(call.baseVersion, 1);
    expect(call.baseContentVersion, 1);
    expect(await allRows(), isEmpty);
  });

  test('a stranded plan create tombstone whose create never committed closes '
      'on plan_not_found and purges its child rows', () async {
    await strandPlan();
    await store.recordSessionCreate(
      context: context,
      draft: const PlanningSessionCreateMutationDraft(
        sessionId: 'session-child',
        planId: 'plan-1',
        slug: 'child',
        name: 'Child',
        position: 1,
      ),
    );
    final remote = ScriptedPlanningRemote(
      (record) async => throw remoteMissing,
    );

    await controllerFor(remote).syncPendingMutations(readContext);

    expect(remote.calls.map((record) => record.kind), [
      PlanningMutationKind.sessionCreate,
      PlanningMutationKind.planDelete,
    ]);
    expect(await allRows(), isEmpty);
  });

  test('a stranded session create tombstone whose create committed is '
      'deleted by the next run', () async {
    await strandSession();
    final remote = ScriptedPlanningRemote((record) async => record);

    await controllerFor(remote).syncPendingMutations(readContext);

    final call = remote.calls.single;
    expect(call.kind, PlanningMutationKind.sessionDelete);
    expect(call.baseVersion, 1);
    expect(await allRows(), isEmpty);
  });

  test('a stranded session create tombstone whose create never committed '
      'closes on session_not_found', () async {
    await strandSession();
    final remote = ScriptedPlanningRemote(
      (record) async => throw remoteMissing,
    );

    await controllerFor(remote).syncPendingMutations(readContext);

    final call = remote.calls.single;
    expect(call.kind, PlanningMutationKind.sessionDelete);
    expect(call.baseVersion, 1);
    expect(await allRows(), isEmpty);
  });

  test('a stranded item create tombstone sends its delete based on '
      'b + 1', () async {
    await strandItem(baseVersion: 2);
    final remote = ScriptedPlanningRemote((record) async => record);

    await controllerFor(remote).syncPendingMutations(readContext);

    final call = remote.calls.single;
    expect(call.kind, PlanningMutationKind.sessionItemDelete);
    expect(call.baseVersion, 3);
    expect(await allRows(), isEmpty);
  });

  test('an uncommitted item create in a quiet session conflicts once, then '
      'Keep mine closes it', () async {
    await strandItem(baseVersion: 2);
    var answers = 0;
    final remote = ScriptedPlanningRemote((record) async {
      answers += 1;
      throw answers == 1
          ? const PlanningMutationSyncException(
              PlanningMutationSyncErrorCode.conflict,
            )
          : remoteMissing;
    });
    final controller = controllerFor(remote);

    await controller.syncPendingMutations(readContext);

    final conflicted = (await read('session_item', 'item-9'))!;
    expect(conflicted.syncStatus, PlanningMutationSyncStatus.conflict);
    expect(conflicted.resolvesCancelledCreate, isTrue);
    expect(remote.calls.single.baseVersion, 3);

    await controller.retryMutation(
      readContext,
      aggregateType: 'session_item',
      aggregateId: 'item-9',
    );

    expect(remote.calls, hasLength(2));
    expect(remote.calls.last.kind, PlanningMutationKind.sessionItemDelete);
    expect(remote.calls.last.baseVersion, 2);
    expect(await allRows(), isEmpty);
  });

  test('a connectivity failure keeps the converted delete pending and '
      'marked', () async {
    await strandSession();
    final remote = ScriptedPlanningRemote(
      (record) async => throw const PlanningMutationSyncException(
        PlanningMutationSyncErrorCode.connectivityFailure,
      ),
    );

    await controllerFor(remote).syncPendingMutations(readContext);

    final row = (await read('session', 'session-1'))!;
    expect(row.kind, PlanningMutationKind.sessionDelete);
    expect(row.syncStatus, PlanningMutationSyncStatus.pending);
    expect(row.resolvesCancelledCreate, isTrue);
  });

  test(
    'a user-recorded delete answered not_found stays visible (D9)',
    () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 3,
        ),
      );
      final remote = ScriptedPlanningRemote(
        (record) async => throw remoteMissing,
      );

      await controllerFor(remote).syncPendingMutations(readContext);

      final row = (await read('plan', 'plan-1'))!;
      expect(row.kind, PlanningMutationKind.planDelete);
      expect(row.syncStatus, PlanningMutationSyncStatus.failedRemoteDelete);
    },
  );

  test('a delete recorded over a converted row is no longer closed by '
      'not_found', () async {
    await strandSession();
    await store.convertStaleCreateTombstones(
      userId: 'user-1',
      organizationId: 'org-1',
    );
    await store.recordSessionDelete(
      context: context,
      draft: const PlanningSessionDeleteMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        baseVersion: 2,
      ),
    );
    final remote = ScriptedPlanningRemote(
      (record) async => throw remoteMissing,
    );

    await controllerFor(remote).syncPendingMutations(readContext);

    final row = (await read('session', 'session-1'))!;
    expect(row.kind, PlanningMutationKind.sessionDelete);
    expect(row.syncStatus, PlanningMutationSyncStatus.failedRemoteDelete);
    expect(row.resolvesCancelledCreate, isFalse);
  });
}
