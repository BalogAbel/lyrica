import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

typedef PlanningMutationStoreReader = PlanningMutationStore Function();
typedef PlanningMutationRemoteRepositoryReader =
    PlanningMutationRemoteRepository Function();
typedef PlanningRefreshTrigger = Future<void> Function();

class PlanningMutationSyncController {
  const PlanningMutationSyncController({
    required PlanningMutationStoreReader mutationStore,
    required PlanningMutationRemoteRepositoryReader remoteRepository,
    required PlanningRefreshTrigger refreshPlanning,
  }) : _mutationStore = mutationStore,
       _remoteRepository = remoteRepository,
       _refreshPlanning = refreshPlanning;

  final PlanningMutationStoreReader _mutationStore;
  final PlanningMutationRemoteRepositoryReader _remoteRepository;
  final PlanningRefreshTrigger _refreshPlanning;

  Future<void> syncPendingMutations(ActivePlanningReadContext context) async {
    final pending = await _mutationStore().readPendingMutations(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    for (final mutation in pending) {
      try {
        await _remoteRepository().syncMutation(
          organizationId: context.organizationId,
          record: mutation,
        );
        await _refreshPlanning();
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
          PlanningMutationSyncErrorCode.unknown => PlanningMutationSyncStatus.pending,
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
