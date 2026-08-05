import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Adversarial coverage for `docs/specs/2026-08-05-sync-snapshot-identity.md`
/// (the PR #64 re-review finding): `PlanningMutationSyncController._run`
/// reads a snapshot of a pending mutation, sends it, and awaits the backend.
/// A local edit made to the SAME aggregate during that remote round trip
/// must survive -- not be silently overwritten by the post-sync
/// `saveSyncAttemptResult`/`clearMutation` writes, which are keyed only by
/// aggregate identity.
///
/// This suite drives the real `DriftPlanningMutationStore` (not a hand-
/// rolled fake) because the fix lives inside the storage boundary: a fake
/// store could easily "pass" this test by encoding the desired behaviour
/// directly, without proving the underlying conditional write is correct.
void main() {
  group('Planning sync snapshot identity (D2/D3)', () {
    test('a local edit made during the remote round trip survives -- the '
        'mutation stays pending with the newer content, and a second sync '
        'sends it', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );

      final remote = _GatedPlanningRemote();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final syncFuture = controller.syncPendingMutations(readContext);

      // Wait until the remote call has actually been reached (the
      // controller sent its snapshot) before racing a local edit against
      // it.
      await remote.entered.future;

      // The user keeps typing while the sync is in flight -- a further
      // local edit lands on the exact aggregate the in-flight remote call
      // is about to conclude.
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service',
          description: 'Edited while syncing',
        ),
      );

      remote.gate.complete();
      await syncFuture;

      final afterFirstSync = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );

      expect(
        afterFirstSync,
        isNotNull,
        reason: 'the newer edit must not be silently discarded',
      );
      expect(
        afterFirstSync!.syncStatus,
        PlanningMutationSyncStatus.pending,
        reason:
            'a stale post-sync write must leave the row pending (D3), '
            'not accepted or cleared',
      );
      expect(
        afterFirstSync.description,
        'Edited while syncing',
        reason: 'the row must carry the newer content, not the synced one',
      );

      // The next sync picks up the newer content and sends it.
      await controller.syncPendingMutations(readContext);

      expect(
        remote.syncedDescriptions,
        hasLength(2),
        reason: 'the second sync must resend the never-accepted content',
      );
      expect(remote.syncedDescriptions.last, 'Edited while syncing');
    });

    test(
      'the unchanged case still completes exactly as before -- accepted '
      'and cleared -- when nothing edits the aggregate during the sync',
      () async {
        final db = PlanningLocalDatabase.inMemory();
        addTearDown(db.close);
        final localStore = DriftPlanningLocalStore(db);
        final store = DriftPlanningMutationStore(
          database: db,
          localStore: localStore,
        );

        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        const readContext = ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Untouched description',
          ),
        );

        final remote = _GatedPlanningRemote();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => remote,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        // No concurrent edit this time -- release the gate immediately.
        remote.gate.complete();
        await controller.syncPendingMutations(readContext);

        expect(refreshCalls, 1);
        final afterSync = await store.readMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'plan',
          aggregateId: 'plan-1',
        );
        expect(
          afterSync,
          isNull,
          reason:
              'the ordinary path must still accept-then-clear exactly as '
              'before the D2 condition was added',
        );
        expect(remote.syncedDescriptions, ['Untouched description']);
      },
    );
  });
}

class _GatedPlanningRemote implements PlanningMutationRemoteRepository {
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  final List<String?> syncedDescriptions = [];

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    syncedDescriptions.add(record.description);
    if (!entered.isCompleted) {
      entered.complete();
      await gate.future;
    }
    return record.copyWith(syncStatus: PlanningMutationSyncStatus.accepted);
  }
}
