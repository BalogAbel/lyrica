import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/planning_run_fixtures.dart';

/// Adversarial coverage for S5b PR 1 (MG4): rule 1a of the content-version
/// advance runs only after a successful reconcile of the same record, for a
/// record whose run context is still active. Real storage boundary and sync
/// controller against a scripted backend.
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
  late PlanningMutationReconciler reconciler;
  var active = true;

  setUp(() async {
    active = true;
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
    PlanningMutationRemoteRepository remote, {
    PlanningRefreshTrigger? refreshPlanning,
    PlanningAcceptedMutationReconciler? reconcile,
  }) => PlanningMutationSyncController(
    mutationStore: () => store,
    remoteRepository: () => remote,
    refreshPlanning: refreshPlanning ?? (_) async => false,
    isRunContextActive: (_) => active,
    reconcileAcceptedMutation: reconcile ?? reconciler.reconcile,
  );

  Future<void> recordRename() => store.recordSessionRename(
    context: context,
    draft: const PlanningSessionRenameMutationDraft(
      sessionId: 'session-1',
      planId: 'plan-1',
      name: 'Renamed',
      baseVersion: 2,
    ),
  );

  Future<PlanDetail?> planDetail(String planId) => localStore.readPlanDetail(
    userId: 'user-1',
    organizationId: 'org-1',
    planId: planId,
  );

  Future<List<PlanningMutationRecord>> allRows() =>
      store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

  test('a context switch before the batch end leaves the old projection '
      'behind its content, never ahead', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote((record) async {
      active = false;
      return record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4);
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    final detail = (await planDetail('plan-1'))!;
    expect(detail.plan.contentVersion, 3);
    expect(detail.sessions.single.name, 'S');
    expect(await allRows(), isEmpty);
  });

  test('a context switch before the batch end skips the refresh of the new '
      'context', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote((record) async {
      active = false;
      return record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4);
    });
    var refreshCalls = 0;

    await controllerFor(
      remote,
      refreshPlanning: (_) async {
        refreshCalls += 1;
        return true;
      },
    ).syncPendingMutations(readContext);

    expect(refreshCalls, 0);
    expect((await planDetail('plan-1'))!.plan.contentVersion, 3);
  });

  test('a reconcile failure leaves the projection content version '
      'untouched', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote(
      (record) async =>
          record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4),
    );

    await controllerFor(
      remote,
      reconcile: (ctx, record) async =>
          throw ReconcileFieldError('name', PlanningMutationKind.sessionRename),
    ).syncPendingMutations(readContext);

    expect((await planDetail('plan-1'))!.plan.contentVersion, 3);
    final rows = await allRows();
    expect(rows.single.syncStatus, PlanningMutationSyncStatus.failedDependency);
  });

  test('a plan created and given a child in one batch still reaches content '
      'version 2', () async {
    await store.recordPlanCreate(
      context: context,
      draft: const PlanningPlanCreateMutationDraft(
        planId: 'plan-new',
        slug: 'plan-new',
        name: 'New plan',
      ),
    );
    await store.recordSessionCreate(
      context: context,
      draft: const PlanningSessionCreateMutationDraft(
        sessionId: 'session-new',
        planId: 'plan-new',
        slug: 'session-new',
        name: 'New session',
        position: 1,
      ),
    );
    final remote = ScriptedPlanningRemote((record) async {
      switch (record.kind) {
        case PlanningMutationKind.planCreate:
          return record.copyWith(acceptedPlanContentVersion: 1);
        case PlanningMutationKind.sessionCreate:
          return record.copyWith(baseVersion: 1, acceptedPlanContentVersion: 2);
        default:
          throw StateError('unexpected ${record.kind}');
      }
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    expect((await planDetail('plan-new'))!.plan.contentVersion, 2);
    expect(await allRows(), isEmpty);
  });

  test('a sign-out purge inside a run writes nothing back', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote((record) async {
      await localStore.deletePlanningDataForUser(userId: 'user-1');
      active = false;
      return record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4);
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    expect(await planDetail('plan-1'), isNull);
    expect(await allRows(), isEmpty);
  });
}
