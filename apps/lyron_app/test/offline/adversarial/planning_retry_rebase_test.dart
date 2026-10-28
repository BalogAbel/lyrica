import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/planning_run_fixtures.dart';

/// Adversarial coverage for S5b PR 2 (MG8): a retry rebases onto the
/// projection only from a visible conflict (ADR-038 decision 5), so a rename
/// that failed on connectivity is resent with its original base and a foreign
/// rename surfaces as a conflict instead of being silently overwritten.
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

  test('a rename that failed on connectivity is resent with its original base '
      'and surfaces a foreign rename as a conflict', () async {
    await store.recordSessionRename(
      context: context,
      draft: const PlanningSessionRenameMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        name: 'Mine',
        baseVersion: 2,
      ),
    );
    var call = 0;
    final remote = ScriptedPlanningRemote((record) async {
      call++;
      if (call == 1) {
        throw const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        );
      }
      if (record.baseVersion != 5) {
        throw const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.conflict,
        );
      }
      return record;
    });
    final controller = PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () => remote,
      refreshPlanning: (_) async => false,
      isRunContextActive: (_) => true,
      reconcileAcceptedMutation: reconciler.reconcile,
    );
    Future<PlanningMutationRecord?> row() => store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
    );
    Future<void> retry() => store.retryMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
    );

    await controller.syncPendingMutations(readContext);
    expect(remote.calls.single.baseVersion, 2);

    // A foreign rename lands: the projection now shows session-1 at v5.
    await localStore.replaceActiveProjection(
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
          contentVersion: 3,
        ),
      ],
      sessions: const [
        CachedSessionRecord(
          id: 'session-1',
          planId: 'plan-1',
          position: 1,
          name: 'Foreign',
          version: 5,
        ),
      ],
      items: const [],
      refreshedAt: DateTime.utc(2026),
    );
    await retry();
    await controller.syncPendingMutations(readContext);
    expect(remote.calls, hasLength(2));
    expect(remote.calls[1].baseVersion, 2);
    expect((await row())!.syncStatus, PlanningMutationSyncStatus.conflict);

    // Keep mine: the retry of a visible conflict rebases.
    await retry();
    await controller.syncPendingMutations(readContext);
    expect(remote.calls, hasLength(3));
    expect(remote.calls[2].baseVersion, 5);
    expect(
      await store.readAllMutations(userId: 'user-1', organizationId: 'org-1'),
      isEmpty,
    );
  });
}
