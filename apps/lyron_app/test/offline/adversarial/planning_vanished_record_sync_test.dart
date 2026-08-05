import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Adversarial coverage for D4 of
/// `docs/specs/2026-08-06-in-flight-create-cancellation.md`:
/// `PlanningMutationSyncController._run` snapshots every pending/accepted
/// mutation up front, then sends them one at a time. If the row backing one
/// of those mutations physically vanishes while its remote call is in
/// flight -- e.g. the collapse path for a delete of a still-pending create
/// (ADR-028 D10) -- the concluding `saveSyncAttemptResult` write has nothing
/// to write to. That must not abort the loop: every OTHER queued mutation
/// still has to reach the backend.
///
/// This suite drives the real `DriftPlanningMutationStore` (not a hand-
/// rolled fake) because the fix lives inside the storage boundary: a fake
/// store could easily "pass" this test by encoding the desired behaviour
/// directly, without proving the underlying store method actually stopped
/// throwing.
void main() {
  group('Planning sync survives a vanished record (D4)', () {
    test('a record removed mid-flight is skipped, and the mutations queued '
        'behind it still reach the backend', () async {
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

      // Three independent pending creates, queued in this order.
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-one',
          name: 'Plan One',
        ),
      );
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-2',
          slug: 'plan-two',
          name: 'Plan Two',
        ),
      );
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-3',
          slug: 'plan-three',
          name: 'Plan Three',
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

      // Wait until the FIRST mutation's remote call is actually in
      // flight before racing a concurrent delete against it.
      await remote.entered.future;

      // The user deletes plan-1 while its create is still awaiting the
      // backend. This mirrors the collapse path
      // (DriftPlanningMutationStore.recordSessionDelete's pendingCreate
      // branch, ADR-028 D10) directly through the public store API:
      // clearMutation with no expectedRevision deletes unconditionally,
      // exactly as the collapse does.
      final collapsed = await store.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(collapsed, isTrue, reason: 'the row must exist to collapse');

      // Release the gate: plan-1's remote call now succeeds, but the row
      // it was supposed to conclude is gone.
      remote.gate.complete();

      // Pre-fix: DriftPlanningMutationStore.saveSyncAttemptResult throws
      // StateError('Planning mutation record not found: plan-1') because
      // the row vanished, and that Error escapes _run uncaught, aborting
      // the entire sync pass before plan-2 and plan-3 are ever attempted.
      await syncFuture;

      expect(
        remote.syncedIds,
        containsAll(<String>['plan-1', 'plan-2', 'plan-3']),
        reason:
            'plan-1 must still have been attempted (its content was '
            'sent before the row vanished), and -- the actual point of '
            'this test -- plan-2 and plan-3, queued behind it, must not '
            'be abandoned just because plan-1 could not be concluded',
      );

      final plan2After = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-2',
      );
      final plan3After = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-3',
      );
      expect(
        plan2After,
        isNull,
        reason: 'plan-2 synced and cleared normally, undisturbed',
      );
      expect(
        plan3After,
        isNull,
        reason: 'plan-3 synced and cleared normally, undisturbed',
      );
    });
  });
}

class _GatedPlanningRemote implements PlanningMutationRemoteRepository {
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  final List<String> syncedIds = [];

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    syncedIds.add(record.aggregateId);
    if (!entered.isCompleted) {
      entered.complete();
      await gate.future;
    }
    return record.copyWith(syncStatus: PlanningMutationSyncStatus.accepted);
  }
}
