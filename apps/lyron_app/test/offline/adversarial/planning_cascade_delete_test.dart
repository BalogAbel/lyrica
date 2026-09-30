import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Adversarial coverage for
/// docs/specs/2026-09-29-plan-delete-and-session-cascade.md (D5-D10, I2/I3):
/// the real storage boundary and sync controller against a scripted backend.
void main() {
  const context = PlanningMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  const readContext = ActivePlanningReadContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );

  late PlanningLocalDatabase db;
  late DriftPlanningLocalStore localStore;
  late DriftPlanningMutationStore store;
  late PlanningLocalReadRepository reads;

  setUp(() async {
    db = PlanningLocalDatabase.inMemory();
    localStore = DriftPlanningLocalStore(db);
    store = DriftPlanningMutationStore(database: db, localStore: localStore);
    reads = PlanningLocalReadRepository(
      store: localStore,
      mutationStore: store,
      contextReader: () async => readContext,
    );
    await seedProjection(localStore, contentVersion: 3);
  });

  tearDown(() async {
    await db.close();
  });

  PlanningMutationSyncController controllerFor(
    PlanningMutationRemoteRepository remote,
  ) {
    final reconciler = PlanningMutationReconciler(localStore: () => localStore);
    return PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () => remote,
      refreshPlanning: () async => false,
      shouldReconcileAcceptedMutation: (_) async => true,
      reconcileAcceptedMutation: (ctx, record) =>
          reconciler.reconcile(ctx, record),
    );
  }

  Future<PlanningMutationRecord?> planRow() => store.readMutation(
    userId: 'user-1',
    organizationId: 'org-1',
    aggregateType: 'plan',
    aggregateId: 'plan-1',
  );

  Future<List<PlanningMutationRecord>> allRows() =>
      store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

  Future<void> recordNewSession() => store.recordSessionCreate(
    context: context,
    draft: const PlanningSessionCreateMutationDraft(
      sessionId: 's-new',
      planId: 'plan-1',
      slug: 's-new',
      name: 'New',
      position: 2,
    ),
  );

  test('an own in-flight child write does not make the plan delete conflict '
      'with itself (acceptance 4)', () async {
    await recordNewSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    final remote = _ScriptedPlanningRemote((record) async {
      switch (record.kind) {
        case PlanningMutationKind.sessionCreate:
          entered.complete();
          await release.future;
          return record.copyWith(baseVersion: 1, acceptedPlanContentVersion: 4);
        case PlanningMutationKind.planDelete:
          // Backend truth: version 2, content version 3 + own create = 4.
          if (record.baseVersion != 2 || record.baseContentVersion != 4) {
            throw const PlanningMutationSyncException(
              PlanningMutationSyncErrorCode.conflict,
            );
          }
          return record.copyWith(baseVersion: 2);
        default:
          throw StateError('unexpected ${record.kind}');
      }
    });
    final controller = controllerFor(remote);

    final firstRun = controller.syncPendingMutations(readContext);
    await entered.future;
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(
        planId: 'plan-1',
        baseVersion: 2,
        baseContentVersion: 3,
      ),
    );
    release.complete();
    await firstRun;

    expect((await planRow())!.baseContentVersion, 4);

    await controller.syncPendingMutations(readContext);

    expect(remote.calls.map((record) => record.kind), [
      PlanningMutationKind.sessionCreate,
      PlanningMutationKind.planDelete,
    ]);
    expect(await allRows(), isEmpty);
    expect(
      await localStore.readPlanDetail(
        userId: 'user-1',
        organizationId: 'org-1',
        planId: 'plan-1',
      ),
      isNull,
    );
  });

  test('a foreign write between view and delete is a visible conflict; retry '
      'after a refresh deletes (acceptance 3)', () async {
    await recordNewSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    final remote = _ScriptedPlanningRemote((record) async {
      switch (record.kind) {
        case PlanningMutationKind.sessionCreate:
          entered.complete();
          await release.future;
          // One foreign write landed before ours: 3 + 1 + 1.
          return record.copyWith(baseVersion: 1, acceptedPlanContentVersion: 5);
        case PlanningMutationKind.planDelete:
          if (record.baseContentVersion != 5) {
            throw const PlanningMutationSyncException(
              PlanningMutationSyncErrorCode.conflict,
            );
          }
          return record.copyWith(baseVersion: 2);
        default:
          throw StateError('unexpected ${record.kind}');
      }
    });
    final controller = controllerFor(remote);

    final firstRun = controller.syncPendingMutations(readContext);
    await entered.future;
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(
        planId: 'plan-1',
        baseVersion: 2,
        baseContentVersion: 3,
      ),
    );
    release.complete();
    await firstRun;
    expect((await planRow())!.baseContentVersion, 3, reason: 'gap: no rebase');

    await controller.syncPendingMutations(readContext);
    expect((await planRow())!.syncStatus, PlanningMutationSyncStatus.conflict);
    expect(await reads.listPlans(), isEmpty, reason: 'still hidden (D10)');

    // A later refresh shows the plan as it now is.
    await seedProjection(localStore, contentVersion: 5);
    await controller.retryMutation(
      readContext,
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    );

    expect(remote.calls.last.kind, PlanningMutationKind.planDelete);
    expect(remote.calls.last.baseContentVersion, 5);
    expect(await allRows(), isEmpty);
  });

  test('a connectivity-failed plan delete retried after a foreign write '
      'conflicts visibly instead of absorbing it (review gate 3 F1)', () async {
    var backendContentVersion = 3;
    final remote = _ScriptedPlanningRemote((record) async {
      if (record.kind != PlanningMutationKind.planDelete) {
        throw StateError('unexpected ${record.kind}');
      }
      if (backendContentVersion == 3) {
        throw const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        );
      }
      // Someone else added content after the user's view; only a delete
      // based on the new content version would be accepted.
      if (record.baseContentVersion != backendContentVersion) {
        throw const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.conflict,
        );
      }
      return record.copyWith(baseVersion: 2);
    });
    final controller = controllerFor(remote);
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(
        planId: 'plan-1',
        baseVersion: 2,
        baseContentVersion: 3,
      ),
    );

    await controller.syncPendingMutations(readContext);
    expect(
      (await planRow())!.errorCode,
      PlanningMutationSyncErrorCode.connectivityFailure,
    );

    // The foreign write lands and a refresh brings it in; the plan stays
    // hidden behind the pending delete (D10), so the user never sees it.
    backendContentVersion = 4;
    await seedProjection(localStore, contentVersion: 4);
    await controller.retryMutation(
      readContext,
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    );

    expect(remote.calls.last.kind, PlanningMutationKind.planDelete);
    expect(remote.calls.last.baseContentVersion, 3);
    expect((await planRow())!.syncStatus, PlanningMutationSyncStatus.conflict);
    expect(await reads.listPlans(), isEmpty, reason: 'still hidden (D10)');
  });

  test('a crash-resumed accepted child never rebases a pending session '
      'delete (spec D7)', () async {
    await store.recordSessionItemCreateSong(
      context: context,
      draft: const PlanningSessionItemCreateSongMutationDraft(
        sessionItemId: 'item-9',
        sessionId: 'session-1',
        planId: 'plan-1',
        songId: 'song-9',
        songTitle: 'Song',
        position: 2,
        baseVersion: 2,
      ),
    );
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session_item',
      aggregateId: 'item-9',
      syncStatus: PlanningMutationSyncStatus.accepted,
    );
    await store.recordSessionDelete(
      context: context,
      draft: const PlanningSessionDeleteMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        baseVersion: 1,
      ),
    );
    final remote = _ScriptedPlanningRemote((record) async {
      throw const PlanningMutationSyncException(
        PlanningMutationSyncErrorCode.connectivityFailure,
      );
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    final sessionDelete = (await store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
    ))!;
    expect(
      sessionDelete.baseVersion,
      1,
      reason:
          'the resumed marker carries its pre-write base (2); treating it as '
          'a response would have moved 1 -> 2',
    );
  });
}

Future<void> seedProjection(
  DriftPlanningLocalStore localStore, {
  required int contentVersion,
}) => localStore.replaceActiveProjection(
  userId: 'user-1',
  organizationId: 'org-1',
  plans: [
    CachedPlanRecord(
      id: 'plan-1',
      slug: 'plan-1',
      name: 'Plan',
      description: null,
      scheduledFor: null,
      updatedAt: DateTime.utc(2026),
      version: 2,
      contentVersion: contentVersion,
    ),
  ],
  sessions: const [
    CachedSessionRecord(
      id: 'session-1',
      planId: 'plan-1',
      position: 1,
      name: 'S',
      version: 2,
    ),
  ],
  items: const [
    CachedSessionItemRecord(
      id: 'item-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      position: 1,
      songId: 'song-1',
      songTitle: 'Song',
    ),
  ],
  refreshedAt: DateTime.utc(2026),
);

class _ScriptedPlanningRemote implements PlanningMutationRemoteRepository {
  _ScriptedPlanningRemote(this._respond);

  final Future<PlanningMutationRecord> Function(PlanningMutationRecord record)
  _respond;
  final List<PlanningMutationRecord> calls = [];

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) {
    calls.add(record);
    return _respond(record);
  }
}
