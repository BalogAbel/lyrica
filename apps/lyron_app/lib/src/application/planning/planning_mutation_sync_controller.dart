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

/// N3 (PR #64 review, second remediation round): invoked synchronously,
/// in-band, at the moment `_run` catches a `PlanningMutationSyncException`
/// for a candidate -- BEFORE the gated failure-status write below it runs
/// and regardless of whether that write ends up applying. `retryMutation`
/// uses this to learn its OWN retry's remote outcome directly, instead of
/// re-reading `errorCode` from the store after the fact: a concurrent edit
/// landing during the remote round trip can make the gated write a no-op
/// (D3 -- not an error, the row self-heals to `pending` with the newer
/// content), which would silently clear `errorCode` and make a stale
/// post-sync read report "no failure" even though this exact remote call
/// genuinely failed. The observer sidesteps that: it reports what actually
/// happened to THIS send, not what the row's row-level status happens to
/// read afterward.
typedef PlanningMutationFailureObserver =
    void Function(
      String aggregateType,
      String aggregateId,
      PlanningMutationSyncException exception,
    );

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

  Future<void> syncPendingMutations(
    ActivePlanningReadContext context, {
    PlanningMutationFailureObserver? onMutationFailure,
  }) {
    final key = '${context.userId}_${context.organizationId}';
    final inFlight = _inFlight[key];
    // N3: if this call coalesces onto an already-in-flight run (started
    // without an observer, by a different caller), [onMutationFailure] is
    // simply never invoked -- the same "no signal" outcome retryMutation
    // already had to tolerate before this fix, and retryMutation itself
    // never reaches this coalescing branch: it explicitly awaits any
    // existing in-flight run first (see its own comment) specifically so
    // its call here always starts a fresh run.
    if (inFlight != null) return inFlight;
    // Block body: Map.remove returns the removed future, and a whenComplete
    // callback that returns a future would wait on it (here, the very future
    // being completed) and deadlock. Discard the return value.
    final run = _run(context, onMutationFailure: onMutationFailure)
        .whenComplete(() {
          _inFlight.remove(key);
        });
    _inFlight[key] = run;
    return run;
  }

  Future<void> _run(
    ActivePlanningReadContext context, {
    PlanningMutationFailureObserver? onMutationFailure,
  }) async {
    final allMutations = await _mutationStore().readAllMutations(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    final candidates = allMutations
        .where(
          (m) =>
              m.syncStatus == PlanningMutationSyncStatus.pending ||
              m.syncStatus == PlanningMutationSyncStatus.accepted ||
              // D1 (docs/specs/2026-08-06-in-flight-create-cancellation.md):
              // a `sending` row is a record a PRIOR run durably marked as
              // in flight and then crashed before hearing back. That crash
              // means the same uncertainty the `accepted` marker exists to
              // bound -- it may or may not have reached the backend -- so it
              // is treated as pending and resent here, not skipped the way
              // `accepted` is. Leaving `sending` out of this filter would
              // strand such a record forever: nothing else ever revisits it.
              m.syncStatus == PlanningMutationSyncStatus.sending,
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

      // D1: durably mark this row `sending` BEFORE the remote call --
      // mirroring the `accepted` marker ADR-019 already writes immediately
      // AFTER it. Between this write and the accept/failure write below,
      // the record is known to be in flight: recordSessionDelete /
      // recordSessionItemDelete read this status to decide whether a
      // concurrent delete must keep a cancellation tombstone (D2) instead
      // of physically collapsing the row. Gated on the snapshot revision
      // the same way the accept-write always has been (D2/D3 of ADR-030):
      // a `null` result means a local edit landed (or the row vanished,
      // D4) before this send even started, so there is nothing to send.
      final sendingRevision = await _mutationStore().saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: mutation.kind.aggregateType,
        aggregateId: mutation.aggregateId,
        syncStatus: PlanningMutationSyncStatus.sending,
        expectedRevision: mutation.localRevision,
      );
      if (sendingRevision == null) {
        continue;
      }

      final isCancellableCreate =
          mutation.kind == PlanningMutationKind.sessionCreate ||
          mutation.kind == PlanningMutationKind.sessionItemCreateSong;

      try {
        final syncedMutation = await _remoteRepository().syncMutation(
          organizationId: context.organizationId,
          record: mutation,
        );
        // Durable marker: save accepted status immediately (survives
        // crash) -- but only if this row is still the exact content that
        // was just sent (D2). `expectedRevision` is the `sending` write's
        // OWN reported revision, not the pre-send snapshot: that write is
        // itself a local write and so also advances localRevision (same
        // reasoning ADR-030 D2 already applies to `clearRevision` below).
        final newRevision = await _mutationStore().saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: mutation.kind.aggregateType,
          aggregateId: mutation.aggregateId,
          syncStatus: PlanningMutationSyncStatus.accepted,
          expectedRevision: sendingRevision,
        );
        if (newRevision == null) {
          // D3: the row is no longer the exact content that was just sent.
          // Two distinct causes land here, and this write is safely gated
          // against both because it never applies unless the revision still
          // matches:
          //
          // - An ordinary local edit/fold landed on this aggregate during
          //   the remote round trip (e.g. a rename folded onto the create).
          //   Not an error -- the edit already reset the row to `pending`
          //   with the newer content, so it is already exactly where it
          //   needs to be for the next sync to pick it up. Nothing further
          //   to do here.
          // - D2: the row is now a cancellation tombstone -- the user
          //   deleted this still-`sending` create while this exact remote
          //   call was in flight. The create that WAS the row just
          //   succeeded, so the tombstone must become a real pending
          //   delete (D3) rather than being silently left as-is (a stale
          //   tombstone would otherwise stay invisible forever --
          //   `cancelling` is excluded from readActionableMutations -- and
          //   the object it names would never be deleted). Resolved only
          //   for the two kinds that can produce a tombstone (D2 is scoped
          //   to recordSessionDelete/recordSessionItemDelete); a no-op for
          //   every other kind, and a no-op even for these two when the row
          //   was not actually a tombstone (the ordinary-edit case above).
          //
          // D4: `newRevision == null` also covers the row having vanished
          // entirely (a delete of a NON-in-flight create racing something
          // else) -- also not an error, and resolveCancelledCreate no-ops
          // on a missing row exactly like the ordinary-edit case.
          if (isCancellableCreate) {
            await _mutationStore().resolveCancelledCreate(
              userId: context.userId,
              organizationId: context.organizationId,
              aggregateType: mutation.kind.aggregateType,
              aggregateId: mutation.aggregateId,
              created: true,
              acceptedBaseVersion: syncedMutation.baseVersion,
            );
          }
          continue;
        }
        acceptedRecords.add((mutation, syncedMutation, newRevision));
      } on PlanningMutationSyncException catch (error) {
        // N3: report the raw outcome of THIS send before anything below
        // decides how (or whether) to persist it -- an explicit retry
        // needs to know that ITS remote call failed even in the narrow
        // window where the persisted status ends up gated out by a
        // concurrent edit (see the typedef doc above).
        onMutationFailure?.call(
          mutation.kind.aggregateType,
          mutation.aggregateId,
          error,
        );
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
        // D2/D3: check for a cancellation tombstone FIRST, before the
        // failure-status write below. If this WAS a tombstone, the create
        // failed remotely, so the object never existed on the backend and
        // the tombstone is discarded outright here -- no failure status is
        // written because there is no row left to write it onto.
        var resolvedTombstone = false;
        if (isCancellableCreate) {
          resolvedTombstone = await _mutationStore().resolveCancelledCreate(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: mutation.kind.aggregateType,
            aggregateId: mutation.aggregateId,
            created: false,
          );
        }
        if (!resolvedTombstone) {
          // Finding B (PR #64 review, 2026-08-06 remediation round): this
          // write USED to be unconditional -- deliberately ungated,
          // reasoning that D2 scopes the snapshot-identity contract to the
          // ACCEPTED outcome only. That reasoning stopped once
          // resolveCancelledCreate above started running first: gating on
          // `sendingRevision` (the exact revision this send's `sending`
          // marker captured) cannot reintroduce the tombstone-clobber the
          // original ungating was protecting against, because a tombstone
          // is already fully handled by the branch above -- either resolved
          // (row gone, this write is skipped by `!resolvedTombstone`
          // already) or never a tombstone to begin with. What gating DOES
          // fix: an ordinary local edit/fold landing on this aggregate
          // during the remote round trip bumps localRevision past
          // `sendingRevision` and resets `syncStatus` back to `pending`
          // with the newer content (the same fold ADR-030's D3 already
          // relies on for the accepted-outcome case). An ungated write here
          // would stamp this call's failure status -- `conflict` and every
          // `failed*` status are NOT in the `pending || accepted ||
          // sending` candidate filter above -- straight onto that newer,
          // never-sent content, silently burying it: not deleted (unlike
          // the D1-D3 defect this ADR closes), but never resent either,
          // visible only if the user happens to check the sync UI. Gating
          // on `sendingRevision` makes this write a no-op when the
          // revision has moved, leaving the row exactly as the fold left
          // it -- pending, with the newer content -- which the very next
          // sync already sends. When the row is unchanged since the
          // `sending` write, gating changes nothing: the write applies
          // exactly as it always did. D4: if the row has vanished
          // (collapsed by a concurrent delete of this still-pending,
          // NOT-in-flight create racing something else), the gated write
          // simply does not apply either way -- the return value is
          // deliberately unchecked, same as always: there is no accepted
          // outcome or clear to skip for a failure branch, and the loop
          // continues to the next candidate regardless.
          await _mutationStore().saveSyncAttemptResult(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: mutation.kind.aggregateType,
            aggregateId: mutation.aggregateId,
            syncStatus: syncStatus,
            errorCode: error.code,
            errorMessage: error.message,
            expectedRevision: sendingRevision,
          );
        }
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
          // pending||accepted candidate filter above, so on the ordinary
          // (ungated-in-effect, revision unchanged) path it is not
          // auto-resent and does not loop forever. N4 (PR #64 review,
          // second remediation round): with the write now gated below, a
          // fold landing concurrently makes this write no-op instead,
          // leaving the row `pending` -- still terminal (the row does not
          // loop, since a `pending` row simply gets one more, ordinary
          // resend), just resent once more before the next attempt reaches
          // this same corrupt-reconcile branch again.
          //
          // Finding B (PR #64 review, 2026-08-06 remediation round):
          // revision-gated on `clearRevision`, the same value `clearMutation`
          // below is gated on -- the revision the accept-write itself just
          // landed on (D2's table). There is no tombstone concept to
          // protect here (this branch only runs on already-`accepted`
          // records; `accepted` never becomes a `cancelling` tombstone --
          // see ADR-030's "accepted-but-uncleared window" section), so
          // gating has nothing to reintroduce a race against. What it does
          // fix is the identical shape as the other failure-status write
          // above: a local edit/fold landing on this aggregate between the
          // accept-write and this reconcile attempt resets the row to
          // `pending` with newer, never-sent content. An ungated write
          // would stamp `failedDependency` -- excluded from the candidate
          // filter -- straight onto that content, burying it. Gated, the
          // write simply no-ops when the revision has moved, leaving the
          // row exactly as the fold left it for the next sync to send.
          await _mutationStore().saveSyncAttemptResult(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: original.kind.aggregateType,
            aggregateId: original.aggregateId,
            syncStatus: PlanningMutationSyncStatus.failedDependency,
            errorCode: PlanningMutationSyncErrorCode.unknown,
            errorMessage: error.toString(),
            expectedRevision: clearRevision,
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

    // syncPendingMutations swallows a connectivity failure so that ordinary
    // background syncing -- which finds no network all the time -- stays
    // quiet. An explicit, user-initiated retry needs the opposite: it must
    // tell the caller the attempt never left the device rather than return
    // as if it had run.
    //
    // N3 (PR #64 review, second remediation round): this USED to inspect
    // the record's post-sync errorCode, re-read from the store after
    // syncPendingMutations returned. That reopened exactly the window D2/D3
    // (ADR-030) exist to close: if a local edit landed on this SAME
    // aggregate during the retry's own remote round trip, the failure-
    // status write below gates on the pre-send revision and no-ops (D3 --
    // correct, the row self-heals to `pending` with the newer content) --
    // but that also clears the very `errorCode` this method was reading,
    // so a stale post-sync read would report "no failure" even though this
    // retry's OWN remote call genuinely got a connectivityFailure. The
    // retry would then return as if it had worked -- exactly the silent
    // success S13 removed elsewhere on this same controller.
    //
    // Fixed by consulting the outcome IN-BAND instead of re-reading store
    // state: [PlanningMutationFailureObserver] reports the raw exception
    // `_run` caught for this exact aggregate, at the moment it is caught,
    // before the gated write decides whether (or how) to persist it. This
    // is available regardless of whether that write ends up applying, so
    // it cannot be defeated by the same race a stale read is vulnerable to.
    PlanningMutationSyncException? observedFailure;
    await syncPendingMutations(
      context,
      onMutationFailure: (observedAggregateType, observedAggregateId, error) {
        if (observedAggregateType == aggregateType &&
            observedAggregateId == aggregateId) {
          observedFailure = error;
        }
      },
    );

    final failure = observedFailure;
    if (failure != null &&
        failure.code == PlanningMutationSyncErrorCode.connectivityFailure) {
      throw failure;
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
