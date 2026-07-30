import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
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
  PlanningMutationSyncController({
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

  // Single-flight keyed by sync context. This controller is an app-scoped
  // singleton, so a global in-flight future would let a sync for one
  // user/organization coalesce a concurrent sync for a *different* one,
  // skipping the second context's pending mutations. Key by user +
  // organization so coalescing only ever merges triggers for the same context.
  final Map<String, Future<void>> _inFlight = {};

  Future<void> syncPendingMutations(ActivePlanningReadContext context) {
    final key = '${context.userId}_${context.organizationId}';
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    // Block body: Map.remove returns the removed future, and a whenComplete
    // callback that returns a future would wait on it (here, the very future
    // being completed) and deadlock. Discard the return value.
    final run = _run(context).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = run;
    return run;
  }

  Future<void> _run(ActivePlanningReadContext context) async {
    final allMutations = await _mutationStore().readAllMutations(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    final candidates = allMutations
        .where(
          (m) =>
              m.syncStatus == PlanningMutationSyncStatus.pending ||
              m.syncStatus == PlanningMutationSyncStatus.accepted,
        )
        .toList(growable: false);

    final acceptedRecords =
        <(PlanningMutationRecord original, PlanningMutationRecord synced)>[];

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
        try {
          if (await _shouldReconcileAcceptedMutation(context)) {
            await _reconcileAcceptedMutation(context, synced);
          }
        } on ReconcileFieldError catch (error) {
          // LF-8 follow-up: a corrupt backend-accepted mutation must not
          // abort this loop (other accepted records still need to clear)
          // nor escape syncPendingMutations (callers like
          // PlanningWriteService._scheduleSync do not catch broadly, so an
          // uncontained throw here could make an unrelated NEW write fail
          // because of an old, unrelated corrupt mutation). Mark it failed
          // and visible (LF-4 sync UI) instead, and leave it un-cleared so
          // it can be inspected/discarded. failedDependency is not in the
          // pending||accepted candidate filter above, so it will not be
          // auto-resent and loop forever.
          await _mutationStore().saveSyncAttemptResult(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: original.kind.aggregateType,
            aggregateId: original.aggregateId,
            syncStatus: PlanningMutationSyncStatus.failedDependency,
            errorCode: PlanningMutationSyncErrorCode.unknown,
            errorMessage: error.toString(),
          );
          continue;
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
    await _mutationStore().retryMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    await syncPendingMutations(context);

    // syncPendingMutations swallows a connectivity failure so that ordinary
    // background syncing -- which finds no network all the time -- stays
    // quiet. An explicit, user-initiated retry needs the opposite: it must
    // tell the caller the attempt never left the device rather than return
    // as if it had run. Inspect the record's post-sync error code instead of
    // catching, since the failure was already recorded there by _run.
    final record = await _mutationStore().readMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    if (record?.errorCode ==
        PlanningMutationSyncErrorCode.connectivityFailure) {
      throw PlanningMutationSyncException(
        PlanningMutationSyncErrorCode.connectivityFailure,
        message: record?.errorMessage,
      );
    }
  }

  Future<void> discardMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    await _mutationStore().clearMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    await syncPendingMutations(context);
  }
}
