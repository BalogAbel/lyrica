import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

typedef PlanningMutationStoreReader = PlanningMutationStore Function();
typedef PlanningMutationRemoteRepositoryReader =
    PlanningMutationRemoteRepository Function();
typedef PlanningRefreshTrigger = Future<bool> Function();
typedef PlanningAcceptedMutationReconciler =
    Future<void> Function(
      ActivePlanningReadContext context,
      PlanningMutationRecord record,
    );
typedef PlanningAcceptedMutationGuard =
    Future<bool> Function(ActivePlanningReadContext context);

class PlanningMutationSyncController {
  const PlanningMutationSyncController({
    required PlanningMutationStoreReader mutationStore,
    required PlanningMutationRemoteRepositoryReader remoteRepository,
    required PlanningRefreshTrigger refreshPlanning,
    required PlanningAcceptedMutationReconciler reconcileAcceptedMutation,
    required PlanningAcceptedMutationGuard shouldReconcileAcceptedMutation,
  }) : _mutationStore = mutationStore,
       _remoteRepository = remoteRepository,
       _refreshPlanning = refreshPlanning,
       _reconcileAcceptedMutation = reconcileAcceptedMutation,
       _shouldReconcileAcceptedMutation = shouldReconcileAcceptedMutation;

  final PlanningMutationStoreReader _mutationStore;
  final PlanningMutationRemoteRepositoryReader _remoteRepository;
  final PlanningRefreshTrigger _refreshPlanning;
  final PlanningAcceptedMutationReconciler _reconcileAcceptedMutation;
  final PlanningAcceptedMutationGuard _shouldReconcileAcceptedMutation;

  Future<void> syncPendingMutations(ActivePlanningReadContext context) async {
    final allMutations = await _mutationStore().readAllMutations(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    final candidates = allMutations
        .where((m) =>
            m.syncStatus == PlanningMutationSyncStatus.pending ||
            m.syncStatus == PlanningMutationSyncStatus.accepted)
        .toList(growable: false);

    final acceptedRecords = <(PlanningMutationRecord original, PlanningMutationRecord synced)>[];

    for (final mutation in candidates) {
      if (mutation.syncStatus == PlanningMutationSyncStatus.accepted) {
        // Durable marker: already accepted, skip remote send
        acceptedRecords.add((mutation, mutation));
        continue;
      }

      try {
        final syncedMutation = await _remoteRepository().syncMutation(
          organizationId: context.organizationId,
          record: mutation,
        );
        // Durable marker: save accepted status immediately (survives crash)
        await _mutationStore().saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: mutation.kind.aggregateType,
          aggregateId: mutation.aggregateId,
          syncStatus: PlanningMutationSyncStatus.accepted,
        );
        acceptedRecords.add((mutation, syncedMutation));
      } on PlanningMutationSyncException catch (error) {
        final syncStatus = switch (error.code) {
          PlanningMutationSyncErrorCode.authorizationDenied =>
            PlanningMutationSyncStatus.failedAuthorization,
          PlanningMutationSyncErrorCode.dependencyBlocked =>
            PlanningMutationSyncStatus.failedDependency,
          PlanningMutationSyncErrorCode.remoteMissing =>
            PlanningMutationSyncStatus.failedRemoteDelete,
          PlanningMutationSyncErrorCode.conflict =>
            PlanningMutationSyncStatus.conflict,
          PlanningMutationSyncErrorCode.connectivityFailure ||
          PlanningMutationSyncErrorCode.unknown =>
            PlanningMutationSyncStatus.pending,
        };
        await _mutationStore().saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: mutation.kind.aggregateType,
          aggregateId: mutation.aggregateId,
          syncStatus: syncStatus,
          errorCode: error.code,
          errorMessage: error.message,
        );
        if (error.code == PlanningMutationSyncErrorCode.connectivityFailure) {
          break;
        }
      }
    }

    if (acceptedRecords.isEmpty) {
      return;
    }

    final refreshed = await _refreshPlanning();
    if (refreshed) {
      for (final (original, _) in acceptedRecords) {
        await _mutationStore().clearMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: original.kind.aggregateType,
          aggregateId: original.aggregateId,
        );
      }
    } else {
      for (final (original, synced) in acceptedRecords) {
        if (await _shouldReconcileAcceptedMutation(context)) {
          await _reconcileAcceptedMutation(context, synced);
        }
        await _mutationStore().clearMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: original.kind.aggregateType,
          aggregateId: original.aggregateId,
        );
      }
    }
  }

  Future<void> retryMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    if (!await _refreshPlanning()) {
      return;
    }
    await _mutationStore().retryMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    await syncPendingMutations(context);
  }

  Future<void> discardMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    if (!await _refreshPlanning()) {
      return;
    }
    await _mutationStore().clearMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    await syncPendingMutations(context);
  }
}
