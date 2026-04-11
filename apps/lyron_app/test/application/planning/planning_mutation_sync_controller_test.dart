import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

void main() {
  group('PlanningMutationSyncController', () {
    test(
      'successful sync refreshes projection and clears the mutation',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
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
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(refreshCalls, 1);
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );

    test(
      'authorization failures move mutations out of normal overlay states',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Weekend Service',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository(
          error: const PlanningMutationSyncException(
            PlanningMutationSyncErrorCode.authorizationDenied,
          ),
        );
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => true,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          store.lastSavedStatus,
          PlanningMutationSyncStatus.failedAuthorization,
        );
      },
    );

    test('connectivity failure stops the remaining queue', () async {
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
          PlanningMutationRecord(
            aggregateId: 'plan-2',
            organizationId: 'org-1',
            name: 'Plan Two',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final repository = _FakePlanningMutationRemoteRepository(
        error: const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.syncPendingMutations(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

      expect(repository.calls, 1);
      expect(store.clearedAggregateIds, isEmpty);
    });

    test(
      'retrying a failed mutation marks it pending and resubmits it',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [],
          all: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.conflict,
              errorCode: PlanningMutationSyncErrorCode.conflict,
              errorMessage: 'base_version_conflict',
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => true,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.retryMutation(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.retriedAggregateIds, ['plan-1']);
        expect(repository.calls, 1);
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );

    test(
      'successful sync reconciles the accepted mutation locally when refresh fails',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              slug: 'draft-slug',
              name: 'Draft name',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final syncedRecord = PlanningMutationRecord(
          aggregateId: 'plan-1',
          organizationId: 'org-1',
          slug: 'canonical-slug',
          name: 'Canonical name',
          kind: PlanningMutationKind.planCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          baseVersion: 3,
          updatedAt: DateTime.utc(2026),
        );
        final repository = _FakePlanningMutationRemoteRepository(
          result: syncedRecord,
        );
        PlanningMutationRecord? reconciledRecord;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, record) async {
            reconciledRecord = record;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(reconciledRecord, isNotNull);
        expect(reconciledRecord?.slug, 'canonical-slug');
        expect(reconciledRecord?.baseVersion, 3);
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );

    test(
      'successful session item sync reconciles locally when refresh fails',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'item-local-1',
              organizationId: 'org-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              songId: 'song-2',
              songTitle: 'Beta',
              kind: PlanningMutationKind.sessionItemCreateSong,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final syncedRecord = PlanningMutationRecord(
          aggregateId: 'item-9',
          organizationId: 'org-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          songId: 'song-2',
          songTitle: 'Beta',
          orderedSiblingIds: const ['item-1', 'item-9'],
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          baseVersion: 5,
          updatedAt: DateTime.utc(2026),
        );
        final repository = _FakePlanningMutationRemoteRepository(
          result: syncedRecord,
        );
        PlanningMutationRecord? reconciledRecord;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, record) async {
            reconciledRecord = record;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          reconciledRecord?.kind,
          PlanningMutationKind.sessionItemCreateSong,
        );
        expect(reconciledRecord?.aggregateId, 'item-9');
        expect(
          reconciledRecord?.orderedSiblingIds,
          orderedEquals(const ['item-1', 'item-9']),
        );
        expect(store.clearedAggregateIds, ['item-local-1']);
      },
    );

    test(
      'accepted-write fallback is skipped when the active boundary changed',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              slug: 'draft-slug',
              name: 'Draft name',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var reconcileCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => false,
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

        expect(reconcileCalls, 0);
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );
  });
}

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
  }) async => all;

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

class _FakePlanningMutationRemoteRepository
    implements PlanningMutationRemoteRepository {
  _FakePlanningMutationRemoteRepository({this.error, this.result});

  final PlanningMutationSyncException? error;
  final PlanningMutationRecord? result;
  int calls = 0;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    calls += 1;
    if (error != null) {
      throw error!;
    }
    return result ?? record;
  }
}
