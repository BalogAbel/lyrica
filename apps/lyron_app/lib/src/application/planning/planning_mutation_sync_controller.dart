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

    // `clearRevision` is the localRevision to gate the eventual clearMutation
    // on (D2) -- NOT necessarily `original.localRevision`, the value read at
    // snapshot time. For a mutation sent and accepted THIS run, the row was
    // just written by saveSyncAttemptResult, which bumped it; `clearRevision`
    // is that write's own reported outcome, so the final clear checks against
    // the content the accept-write actually landed on top of, not the
    // pre-send snapshot. For an already-`accepted` durable marker (no send
    // this run -- see below), nothing has written the row yet, so the
    // snapshot value is still current.
    final acceptedRecords =
        <
          (
            PlanningMutationRecord original,
            PlanningMutationRecord synced,
            int clearRevision,
          )
        >[];

    for (final mutation in candidates) {
      if (mutation.syncStatus == PlanningMutationSyncStatus.accepted) {
        // Durable marker: already accepted, skip remote send
        acceptedRecords.add((mutation, mutation, mutation.localRevision));
        continue;
      }

      try {
        final syncedMutation = await _remoteRepository().syncMutation(
          organizationId: context.organizationId,
          record: mutation,
        );
        // Durable marker: save accepted status immediately (survives
        // crash) -- but only if this row is still the exact content that
        // was just sent (D2). `expectedRevision` is the revision captured
        // BEFORE the remote round trip; the store compares it against the
        // row's CURRENT revision atomically, inside the write itself.
        final newRevision = await _mutationStore().saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: mutation.kind.aggregateType,
          aggregateId: mutation.aggregateId,
          syncStatus: PlanningMutationSyncStatus.accepted,
          expectedRevision: mutation.localRevision,
        );
        if (newRevision == null) {
          // D3: a local edit landed on this aggregate during the remote
          // round trip. Not an error -- the accepted remote write is not
          // undone (it happened), but this row is no longer that content:
          // the edit that moved the revision already reset it to `pending`
          // (every local write does), so it is already exactly where it
          // needs to be for the next sync to pick it up. Nothing further
          // to do: don't mark accepted, don't reconcile, don't clear.
          //
          // D4 (docs/specs/2026-08-06-in-flight-create-cancellation.md):
          // the same `null` also covers the row having vanished entirely
          // -- the user deleted a still-pending create while this exact
          // remote call was in flight, and the collapse path physically
          // removed it. Also not an error, and handled identically: skip
          // this record and continue the loop with whatever is queued
          // behind it. No user-facing signal is raised for either cause --
          // the row is already gone from every list the sync overview
          // reads (readActionableMutations/readAllMutations), which is
          // exactly the state a user-initiated delete asked for.
          continue;
        }
        acceptedRecords.add((mutation, syncedMutation, newRevision));
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
        // Not gated by revision: D2 scopes the snapshot-identity contract
        // to the ACCEPTED outcome and the clears that follow it, because
        // only that path can destroy unsynced intent by claiming the
        // backend accepted something it never received a later edit for.
        // A failure outcome never claims that, so it is out of scope here.
        //
        // D4: if the row has vanished (collapsed by a concurrent delete of
        // this still-pending create while the failed call above was in
        // flight), this write simply does not apply -- the return value is
        // deliberately unchecked, same as always: there is no accepted
        // outcome or clear to skip for a failure branch either way, and the
        // loop continues to the next candidate regardless.
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
      for (final (original, _, clearRevision) in acceptedRecords) {
        await _mutationStore().clearMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: original.kind.aggregateType,
          aggregateId: original.aggregateId,
          // D2/D3: if a local edit landed during the refresh await, this
          // no-ops and leaves the row pending with the newer content --
          // the next sync sends it. It does not need to be inspected here:
          // the edit already reset the row itself.
          expectedRevision: clearRevision,
        );
      }
    } else {
      for (final (original, synced, clearRevision) in acceptedRecords) {
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
          // auto-resent and loop forever. Not revision-gated, same reason
          // as the other failure-status write above.
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
          expectedRevision: clearRevision,
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

    // A background sync may already be running for this context. If it is,
    // it snapshotted its candidate list *before* the reset above and will
    // never pick up this record. syncPendingMutations coalesces onto that
    // same in-flight run rather than starting a new one, so calling it
    // directly here would let the retry ride along on a sync that can never
    // see the reset record -- the cleared errorCode would then look like
    // success even though nothing was resent. Wait out any such run first,
    // so the sync this retry triggers is guaranteed to start its own
    // candidate snapshot *after* the reset and therefore include it.
    final key = '${context.userId}_${context.organizationId}';
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      await inFlight;
    }
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
