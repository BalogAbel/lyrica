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

class PlanningMutationSyncController {
  const PlanningMutationSyncController({
    required PlanningMutationStoreReader mutationStore,
    required PlanningMutationRemoteRepositoryReader remoteRepository,
    required PlanningRefreshTrigger refreshPlanning,
    required PlanningAcceptedMutationReconciler reconcileAcceptedMutation,
  }) : _mutationStore = mutationStore,
       _remoteRepository = remoteRepository,
       _refreshPlanning = refreshPlanning,
       _reconcileAcceptedMutation = reconcileAcceptedMutation;

  final PlanningMutationStoreReader _mutationStore;
  final PlanningMutationRemoteRepositoryReader _remoteRepository;
  final PlanningRefreshTrigger _refreshPlanning;
  final PlanningAcceptedMutationReconciler _reconcileAcceptedMutation;

  Future<void> syncPendingMutations(ActivePlanningReadContext context) async {
    final pending = await _mutationStore().readPendingMutations(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    for (final mutation in pending) {
      try {
        final syncedMutation = await _remoteRepository().syncMutation(
          organizationId: context.organizationId,
          record: mutation,
        );
        final refreshed = await _refreshPlanning();
        if (!refreshed) {
          await _reconcileAcceptedMutation(context, syncedMutation);
        }
        await _mutationStore().clearMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateId: mutation.aggregateId,
        );
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
  }

  Future<void> retryMutation(
    ActivePlanningReadContext context, {
    required String aggregateId,
  }) async {
    await _mutationStore().retryMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateId: aggregateId,
    );
    await syncPendingMutations(context);
  }
}
