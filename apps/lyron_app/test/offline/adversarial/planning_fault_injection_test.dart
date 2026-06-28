import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

import '../../support/fault_injecting_remote.dart';

/// Adversarial coverage for ADR-019 exactly-once planning mutation sync.
///
/// These tests prove already-shipped behaviour in
/// `PlanningMutationSyncController._run`:
///  - LF-1: a mutation durably marked `accepted` (crash after backend-accept,
///    before the local clear) must never be re-sent to the remote on the next
///    sync attempt.
///  - LF-2: when `refreshPlanning()` fails (partial-refresh / offline), an
///    accepted mutation must still be reconciled locally and cleared, never
///    silently dropped.
void main() {
  group('Planning mutation sync fault injection (LF-1, LF-2)', () {
    test(
      'LF-1: an already-accepted mutation is not re-sent after a crash',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [],
          all: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.accepted,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final remote = FaultInjectingPlanningRemote();
        var reconcileCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => remote,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {
            reconcileCalls += 1;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          remote.syncedAggregateIds,
          isEmpty,
          reason: 'accepted record must not be re-sent to remote (no double-send)',
        );
        expect(reconcileCalls, 1, reason: 'accepted record must be reconciled');
        expect(store.clearedAggregateIds, hasLength(1));
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );

    test(
      'LF-2: a pending mutation is reconciled and cleared when refresh fails',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-2',
              organizationId: 'org-1',
              slug: 'weekend-service',
              name: 'Weekend Service',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final remote = FaultInjectingPlanningRemote();
        final reconciledAggregateIds = <String>[];
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => remote,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, record) async {
            reconciledAggregateIds.add(record.aggregateId);
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          reconciledAggregateIds,
          hasLength(1),
          reason: 'accepted mutation must be reconciled, not lost',
        );
        expect(reconciledAggregateIds, ['plan-2']);
        expect(store.clearedAggregateIds, ['plan-2']);
        expect(store.lastSavedStatus, PlanningMutationSyncStatus.accepted);
      },
    );
  });
}

/// Minimal fake mirroring `_FakePlanningMutationStore` from
/// `planning_mutation_sync_controller_test.dart`, scoped to what these
/// adversarial tests exercise.
class _FakePlanningMutationStore implements PlanningMutationStore {
  _FakePlanningMutationStore({
    required this.pending,
    List<PlanningMutationRecord>? all,
  }) : all = all ?? pending;

  final List<PlanningMutationRecord> pending;
  final List<PlanningMutationRecord> all;
  final List<String> clearedAggregateIds = [];
  final List<String> retriedAggregateIds = [];
  PlanningMutationSyncStatus? lastSavedStatus;

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    clearedAggregateIds.add(aggregateId);
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
  Future<bool> hasUnsyncedMutations({required String userId}) async =>
      pending.isNotEmpty;

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async {
    final seen = <String>{};
    final merged = <PlanningMutationRecord>[];
    for (final p in pending) {
      merged.add(p);
      seen.add(p.aggregateId);
    }
    for (final a in all) {
      if (!seen.contains(a.aggregateId)) {
        merged.add(a);
      }
    }
    merged.sort((x, y) {
      final cmp = x.orderKey.compareTo(y.orderKey);
      if (cmp != 0) return cmp;
      return x.aggregateId.compareTo(y.aggregateId);
    });
    return merged;
  }

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    for (final record in pending) {
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
  }) async => pending;

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => pending;

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    retriedAggregateIds.add(aggregateId);
    final match = all.firstWhere(
      (record) =>
          record.kind.aggregateType == aggregateType &&
          record.aggregateId == aggregateId,
    );
    pending.add(
      match.copyWith(
        syncStatus: PlanningMutationSyncStatus.pending,
        clearErrorCode: true,
        clearErrorMessage: true,
      ),
    );
  }

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
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {
    lastSavedStatus = syncStatus;
  }
}
