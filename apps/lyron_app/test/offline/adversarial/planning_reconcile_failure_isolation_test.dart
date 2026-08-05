import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// Regression for the LF-8 follow-up: `PlanningMutationReconciler.reconcile`
/// throws a typed `ReconcileFieldError` for a corrupt backend-accepted
/// mutation (a required-on-create field is null). That throw is correct in
/// isolation, but `PlanningMutationSyncController._run`'s refresh-failed
/// (`else`) branch did not contain it:
///
///   1. The reconcile loop aborted -- any HEALTHY accepted record queued
///      after the corrupt one never got `clearMutation`, so it would be
///      reconciled and "cleared" again (and again) on every future run.
///   2. The exception propagated out of `syncPendingMutations`, and
///      `PlanningWriteService._scheduleSync` does not catch it, so an
///      unrelated NEW write (e.g. addSongSessionItem) could throw because of
///      an old, unrelated corrupt mutation sitting in the queue.
///
/// This test drives the real `_run` path (real `PlanningMutationReconciler`,
/// forced into the refresh-failed branch) with one corrupt and one healthy
/// accepted record, and asserts the failure is contained: no exception
/// escapes, the healthy record still clears, and the corrupt record is
/// preserved (not cleared) and marked with a visible failed status instead
/// of being silently retried forever.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningMutationSyncController reconcile failure isolation', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late PlanningMutationReconciler reconciler;

    const userId = 'user-1';
    const organizationId = 'org-1';

    final testContext = const ActivePlanningReadContext(
      userId: userId,
      organizationId: organizationId,
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      reconciler = PlanningMutationReconciler(localStore: () => localStore);

      await localStore.replaceActiveProjection(
        userId: userId,
        organizationId: organizationId,
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'team-rehearsal',
            name: 'Team Rehearsal',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            slug: 'warm-up',
            position: 10,
            name: 'Warm-Up',
          ),
        ],
        items: const [],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('a corrupt accepted record cannot block or fail healthy records, '
        'and does not escape syncPendingMutations', () async {
      // CORRUPT: sessionItemCreateSong with a null songId. The reconciler
      // throws ReconcileFieldError for this -- this is the bug trigger.
      final corruptRecord = PlanningMutationRecord(
        aggregateId: 'item-corrupt',
        organizationId: organizationId,
        kind: PlanningMutationKind.sessionItemCreateSong,
        syncStatus: PlanningMutationSyncStatus.accepted,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        planId: 'plan-1',
        sessionId: 'session-1',
        songId: null,
        songTitle: 'Corrupt Song',
        position: 20,
        baseVersion: 1,
      );

      // HEALTHY: a normal, valid accepted record queued AFTER the corrupt
      // one, so an aborted loop would never reach it.
      final healthyRecord = PlanningMutationRecord(
        aggregateId: 'item-healthy',
        organizationId: organizationId,
        kind: PlanningMutationKind.sessionItemCreateSong,
        syncStatus: PlanningMutationSyncStatus.accepted,
        orderKey: 2,
        updatedAt: DateTime.utc(2026, 4, 11, 12),
        planId: 'plan-1',
        sessionId: 'session-1',
        songId: 'song-1',
        songTitle: 'Healthy Song',
        position: 21,
        baseVersion: 1,
      );

      final store = _FakePlanningMutationStore(
        all: [corruptRecord, healthyRecord],
      );

      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => _UnusedRemoteRepository(),
        // Force the refresh-failed (else / reconcile) branch.
        refreshPlanning: () async => false,
        shouldReconcileAcceptedMutation: (_) async => true,
        // Faithful: delegate to the REAL reconciler.
        reconcileAcceptedMutation: reconciler.reconcile,
      );

      // (a) must not throw -- the bug today lets ReconcileFieldError
      // escape this call.
      await controller.syncPendingMutations(testContext);

      // (b) the healthy record, queued after the corrupt one, must still
      // be cleared -- the bug today aborts the loop before reaching it.
      expect(
        store.clearedAggregateIds,
        contains('item-healthy'),
        reason: 'healthy record after the corrupt one must still clear',
      );

      // (c) the corrupt record must NOT be cleared (preserved for
      // inspection/discard) and must be marked with a visible failed
      // status instead of being silently retried forever.
      expect(
        store.clearedAggregateIds,
        isNot(contains('item-corrupt')),
        reason: 'corrupt record must be preserved, not cleared',
      );
      expect(
        store.savedStatusesByAggregateId['item-corrupt'],
        PlanningMutationSyncStatus.failedDependency,
        reason: 'corrupt record must be marked failed and visible',
      );
    });
  });
}

/// Extends the shared fake shape with per-aggregate saved-status tracking,
/// needed to assert (c) above. Mirrors
/// `planning_mutation_sync_controller_test.dart`'s `_FakePlanningMutationStore`
/// but is local to this file to keep this regression test self-contained.
class _FakePlanningMutationStore implements PlanningMutationStore {
  _FakePlanningMutationStore({required this.all});

  final List<PlanningMutationRecord> all;
  final List<String> clearedAggregateIds = [];
  final Map<String, PlanningMutationSyncStatus> savedStatusesByAggregateId = {};

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async {
    clearedAggregateIds.add(aggregateId);
    return true;
  }

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'unused';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'unused';

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async => false;

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => all;

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    for (final record in all) {
      if (record.kind.aggregateType == aggregateType &&
          record.aggregateId == aggregateId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {}

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}
  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

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
  }) async {
    savedStatusesByAggregateId[aggregateId] = syncStatus;
    return 1;
  }
}

class _UnusedRemoteRepository implements PlanningMutationRemoteRepository {
  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) {
    throw UnimplementedError(
      'syncMutation must not be called for already-accepted records',
    );
  }
}
