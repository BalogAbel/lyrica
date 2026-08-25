import 'dart:async';

import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

typedef SongCatalogRefresh = Future<void> Function(SongMutationContext context);

enum SongDiscardResult { discarded, syncInProgress }

enum SongDiscardLeaseOutcome { acquired, syncInProgress }

class SongDiscardLease {
  SongDiscardLease({required this._discardSong, required this._release});

  final Future<void> Function(String songId) _discardSong;
  final void Function() _release;

  Future<void> discardMine({required String songId}) => _discardSong(songId);

  void release() => _release();
}

class SongDiscardLeaseAcquisition {
  const SongDiscardLeaseAcquisition.acquired(this.lease)
    : outcome = SongDiscardLeaseOutcome.acquired;

  const SongDiscardLeaseAcquisition.syncInProgress()
    : outcome = SongDiscardLeaseOutcome.syncInProgress,
      lease = null;

  final SongDiscardLeaseOutcome outcome;
  final SongDiscardLease? lease;
}

final class _SongContextKey {
  const _SongContextKey({required this.userId, required this.organizationId});

  final String userId;
  final String organizationId;

  @override
  bool operator ==(Object other) =>
      other is _SongContextKey &&
      other.userId == userId &&
      other.organizationId == organizationId;

  @override
  int get hashCode => Object.hash(userId, organizationId);
}

sealed class _SongContextOperation {}

final class _SongSyncOperation extends _SongContextOperation {
  late final Future<void> future;
}

final class _SongDiscardOperation extends _SongContextOperation {
  final Completer<void> released = Completer<void>();
  Future<void>? queuedSync;
}

class SongMutationSyncController {
  SongMutationSyncController({
    required this._store,
    required this._remoteRepository,
    this._refreshCatalog,
  });

  final SongMutationStore _store;
  final SongMutationRemoteRepository _remoteRepository;
  final SongCatalogRefresh? _refreshCatalog;

  // A sync snapshots every pending song in its user/organization context, so
  // sync and discard ownership must be context-wide rather than row-wide. The
  // operation object is also the owner identity used by successor-safe cleanup.
  final Map<_SongContextKey, _SongContextOperation> _operations = {};

  Future<void> syncPendingSongs(SongMutationContext context) {
    final key = _contextKey(context);
    final current = _operations[key];
    if (current is _SongSyncOperation) return current.future;
    if (current is _SongDiscardOperation) {
      return current.queuedSync ??= current.released.future.then(
        (_) => syncPendingSongs(context),
      );
    }

    final owner = _SongSyncOperation();
    _operations[key] = owner;
    owner.future = _runOwnedSync(context, key: key, owner: owner);
    return owner.future;
  }

  Future<void> _runOwnedSync(
    SongMutationContext context, {
    required _SongContextKey key,
    required _SongSyncOperation owner,
  }) async {
    try {
      await _runSync(context);
    } finally {
      if (identical(_operations[key], owner)) {
        _operations.remove(key);
      }
    }
  }

  Future<void> _runSync(SongMutationContext context) async {
    final pendingSongs = await _store.readPendingSongs(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    for (final record in pendingSongs) {
      // D1 (docs/specs/2026-08-06-in-flight-create-cancellation.md): a
      // record is a create -- either freshly `pendingCreate`, or `sending`
      // because a prior run crashed after writing the marker below but
      // before hearing back (readPendingSongs resends a `sending` row) --
      // iff its status is one of these two. `pendingUpdate`/`pendingDelete`
      // never carry this marker; see SongCatalogStore.markSongCreateSending
      // for why only creates need one.
      final isCreate =
          record.syncStatus == SongSyncStatus.pendingCreate ||
          record.syncStatus == SongSyncStatus.sending;

      var expectedRevision = record.localRevision;
      if (isCreate) {
        // D1: durably mark this row `sending` BEFORE the remote call, so a
        // concurrent delete (SongLibraryService.deleteSong) can tell this
        // create is genuinely in flight and keep a cancellation tombstone
        // (D2) instead of physically collapsing the row. Gated on the
        // snapshot revision the same way every other conditional write in
        // this controller is: a `null` result means a local edit or delete
        // landed on this song (or the row vanished, D4) before this send
        // even started, so there is nothing to send.
        final sendingRevision = await _store.markCreateSending(
          userId: context.userId,
          organizationId: context.organizationId,
          songId: record.id,
          expectedRevision: record.localRevision,
        );
        if (sendingRevision == null) {
          continue;
        }
        expectedRevision = sendingRevision;
      }

      try {
        final syncedRecord = await _remoteRepository.syncSong(
          organizationId: context.organizationId,
          record: record,
        );
        final applied = await _applySuccessfulSync(
          context,
          syncedRecord,
          original: record,
          expectedRevision: expectedRevision,
        );
        if (!applied && isCreate) {
          // D3: the row is no longer the exact content that was just sent.
          // Two distinct causes land here, both safe because this call
          // never acts unless the row is actually a tombstone:
          // - An ordinary local edit landed on this song during the remote
          //   round trip -- not a tombstone, so resolveCancelledSongCreate
          //   finds the row isn't `cancelling` and no-ops. The edit already
          //   reset the row to pending with the newer content, so the next
          //   sync picks it up.
          // - D2: the row IS a cancellation tombstone -- the user deleted
          //   this still-`sending` create while this exact remote call was
          //   in flight. The create that WAS the row just succeeded, so the
          //   tombstone must become a real pending delete (D3) rather than
          //   being left invisible forever (`cancelling` is excluded from
          //   every local-first read and from readPendingSongs).
          await _store.resolveCancelledSongCreate(
            userId: context.userId,
            organizationId: context.organizationId,
            songId: record.id,
            created: true,
            acceptedVersion: syncedRecord.version,
          );
        }
      } on SongMutationSyncException catch (error) {
        final effectiveSyncStatus = record.effectiveSyncStatus;
        if (error.code == SongMutationSyncErrorCode.remoteDeleted &&
            effectiveSyncStatus == SongSyncStatus.pendingDelete) {
          await _store.deleteSong(
            userId: context.userId,
            organizationId: context.organizationId,
            songId: record.id,
          );
          continue;
        }

        // D2/D3: check for a cancellation tombstone FIRST, before the
        // failure-status write below. If this WAS a tombstone, the create
        // failed remotely, so the song never existed on the backend and the
        // tombstone is discarded outright here -- no failure status is
        // written because there is no row left to write it onto.
        var resolvedTombstone = false;
        if (isCreate) {
          resolvedTombstone = await _store.resolveCancelledSongCreate(
            userId: context.userId,
            organizationId: context.organizationId,
            songId: record.id,
            created: false,
          );
        }
        if (!resolvedTombstone) {
          // Finding B (PR #64 review, 2026-08-06 remediation round): this
          // write USED to be unconditional -- deliberately ungated, on the
          // reasoning that D2/D2(song/catalog) of
          // docs/specs/2026-08-05-sync-snapshot-identity.md scope the
          // snapshot-identity contract to the ACCEPTED outcome only. That
          // reasoning stopped once resolveCancelledSongCreate above started
          // running first: gating on [expectedRevision] (the exact revision
          // this send's `sending` marker captured, or the pre-send snapshot
          // for a non-create) cannot reintroduce the tombstone-clobber the
          // original ungating was protecting against -- a tombstone is
          // already fully handled by the branch above, either resolved (row
          // gone, this write already skipped by `!resolvedTombstone`) or
          // never a tombstone to begin with. What gating DOES fix: an
          // ordinary local edit landing on this song during the remote
          // round trip bumps localRevision past [expectedRevision]. An
          // ungated write here would stamp `conflict` (the one status this
          // branch can write that `readPendingSongs`' candidate filter
          // excludes) straight onto that newer, never-sent content,
          // silently burying it -- not deleted, but never resent either,
          // visible only if the user checks the sync UI. Gated, the write
          // is a no-op when the revision has moved, leaving the row exactly
          // as the edit left it for the next sync to send. D4
          // (docs/specs/2026-08-06-in-flight-create-cancellation.md): a
          // `null` return also covers the row having vanished entirely (a
          // concurrent delete of a still-pending, not-in-flight create or
          // update/delete racing something else) -- deliberately
          // unchecked, same as always: there is nothing to write the
          // failure status onto either way, and this loop iteration was
          // already done regardless. When this WAS a create, the fallback
          // status is `pendingCreate` rather than `record.syncStatus`
          // (which may be `sending`, a marker with no live call to justify
          // it once this catch block is reached).
          await _store.saveSyncAttemptResult(
            userId: context.userId,
            organizationId: context.organizationId,
            songId: record.id,
            // spec D5.6 / ADR-035: a permanent authorization rejection
            // (authorizationDenied) is folded into the same `conflict`
            // status as an ordinary version conflict or a remote delete --
            // NOT left on `pendingCreate`/`pendingUpdate`/`pendingDelete`.
            // `conflict` is excluded from readPendingSongs' candidate
            // filter, which is what makes this terminal: nothing resends
            // the row again. Reusing the existing status also means the
            // existing conflictSourceSyncStatus bookkeeping (below, at the
            // storage boundary) and the existing unified-sync-overview
            // conflict-severity surfacing apply unchanged -- no new status
            // or surface needed.
            syncStatus:
                error.code == SongMutationSyncErrorCode.conflict ||
                    error.code == SongMutationSyncErrorCode.remoteDeleted ||
                    error.code == SongMutationSyncErrorCode.authorizationDenied
                ? SongSyncStatus.conflict
                : (isCreate ? SongSyncStatus.pendingCreate : record.syncStatus),
            errorCode: error.code,
            errorMessage: error.message,
            expectedRevision: expectedRevision,
          );
        }
        if (error.code == SongMutationSyncErrorCode.connectivityFailure) {
          // Fifth PR #64 review round: this `break` abandons every remaining
          // candidate, the same shape that needed a failure observer on the
          // planning side (ADR-030's fourth-round follow-up). It needs no
          // equivalent here, and the reason is a property of the callers,
          // not of this loop -- recorded so a future reader does not have to
          // re-derive it, or assume the omission was an oversight.
          //
          // Nothing observes a per-record outcome of this pass.
          // `syncPendingSongs` has exactly one caller,
          // `UnifiedManualSyncController.syncSongMutations` -- a bulk "sync
          // now" trigger that claims nothing about any individual song.
          // There is no song counterpart to
          // `PlanningMutationSyncController.retryMutation`: the unified
          // sync UI's per-record retry action is planning-only, and
          // `keepMine`, the one user-initiated song operation with a remote
          // call, runs that call itself and rethrows rather than going
          // through this loop. So no caller can be handed a silent success
          // by an abandoned candidate here.
          //
          // If a per-song retry is ever added, it must go through an
          // observer like planning's rather than re-reading the row's
          // status afterwards, and this `break` must report its abandoned
          // candidates -- both for the reasons ADR-030 records.
          break;
        }
      }
    }
  }

  /// Overwrites the remote record with the local one for a conflicted song.
  ///
  /// Unlike [syncPendingSongs] and the discard lease, `keepMine` does not
  /// register itself in `_operations` and is not blocked by, or a blocker
  /// for, an owned sync or discard on the same context: it can interleave
  /// with either. This is pre-existing and intentionally out of scope for
  /// the discard-ownership remediation (song sync and discard are
  /// mutually exclusive per context; `keepMine` is not part of that
  /// exclusion). See ADR-013 and architecture.md, which describe this
  /// exclusion explicitly rather than claiming context-wide ownership
  /// covers every song write.
  Future<void> keepMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    final record = await _requireSong(
      context,
      songId: songId,
      includeConflicts: true,
    );
    // YELLOW 9 (final whole-branch review, spec D5.6): authorizationDenied
    // is folded into the same `conflict` status as an ordinary version
    // conflict (see the comment on the saveSyncAttemptResult call in
    // _runSync above), which is the one bucket whose UI action is
    // keepMine -- re-sending via overwriteSong. That makes the row
    // terminal for the bulk sync pass but not for this user-facing retry.
    // Refuse here the same way PlanningMutationSyncController.retryMutation
    // refuses: throw the exception the row already carries rather than
    // making a wasted round trip guaranteed to fail the same way again.
    if (record.syncStatus == SongSyncStatus.conflict &&
        record.errorCode == SongMutationSyncErrorCode.authorizationDenied) {
      throw SongMutationSyncException(
        SongMutationSyncErrorCode.authorizationDenied,
        message: record.errorMessage,
      );
    }
    if (record.isRemoteDeletedConflict &&
        record.effectiveSyncStatus == SongSyncStatus.pendingDelete) {
      await _store.deleteSong(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
      return;
    }
    try {
      final syncedRecord = await _remoteRepository.overwriteSong(
        organizationId: context.organizationId,
        record: record,
      );
      // keepMine never touches the D1 `sending` marker (it does not call
      // markCreateSending), so the pre-send snapshot's own localRevision is
      // still the correct gate here -- unaffected by the create-cancellation
      // work above.
      //
      // Fifth PR #64 review round: the `bool` is deliberately not consulted,
      // where `_runSync` above pairs the same call with `if (!applied &&
      // isCreate) resolveCancelledSongCreate(...)`. That follow-up exists
      // solely to resolve a D2 cancellation tombstone, and no tombstone can
      // form under keepMine: a tombstone is only ever written by
      // `SongLibraryService.deleteSong`'s `sending` branch, keepMine never
      // marks the row `sending`, and deleteSong refuses a `conflict` row
      // outright. `false` here could therefore only mean an ordinary local
      // write raced this overwrite, which needs no follow-up at all -- that
      // row is already `pending` with the newer content for the next sync.
      // Calling resolveCancelledSongCreate here would be dead code, not
      // symmetry.
      await _applySuccessfulSync(
        context,
        syncedRecord,
        original: record,
        expectedRevision: record.localRevision,
      );
    } on SongMutationSyncException catch (error) {
      if (error.code == SongMutationSyncErrorCode.remoteDeleted &&
          record.effectiveSyncStatus == SongSyncStatus.pendingDelete) {
        await _store.deleteSong(
          userId: context.userId,
          organizationId: context.organizationId,
          songId: songId,
        );
        return;
      }
      // D4: a `false` return (row vanished) is not inspected here either --
      // keepMine operates on a single song, not a batch, so there is no
      // "next record" to protect; the original SongMutationSyncException is
      // rethrown to the caller regardless of whether the status write
      // found anything to update.
      //
      // Fourth PR #64 review round: gated on the same pre-send
      // `record.localRevision` the success path above already uses. The
      // asymmetry (success gated, failure not) was an omission, not a
      // decision -- it is the identical shape Finding B closed on every
      // other failure-status write: `conflict` is excluded from
      // `readPendingSongs`, so an ungated write landing on newer,
      // never-sent content buries it where nothing resends it.
      //
      // No application path can produce that concurrent write today: this
      // method's only caller is the conflict row's "keep mine" action, so
      // the row is `conflict`, and `SongLibraryService.updateSong`/
      // `deleteSong` both refuse a `conflict` row outright. So this is
      // consistency and defense in depth, not a live defect -- but the
      // invariant it would otherwise rest on lives two layers up in a
      // different file, and this method's own doc above records that it
      // deliberately sits outside the context lease and can interleave with
      // other song writes. Gating costs nothing when the revision has not
      // moved: the write applies exactly as it always did.
      await _store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
        syncStatus: SongSyncStatus.conflict,
        errorCode: error.code,
        errorMessage: error.message,
        expectedRevision: record.localRevision,
      );
      rethrow;
    }
  }

  Future<SongDiscardLeaseAcquisition> acquireDiscardLease(
    SongMutationContext context,
  ) {
    final key = _contextKey(context);
    if (_operations.containsKey(key)) {
      return Future.value(const SongDiscardLeaseAcquisition.syncInProgress());
    }

    final owner = _SongDiscardOperation();
    _operations[key] = owner;
    var released = false;
    return Future.value(
      SongDiscardLeaseAcquisition.acquired(
        SongDiscardLease(
          discardSong: (songId) => _discardMineOwned(context, songId: songId),
          release: () {
            if (released) return;
            released = true;
            if (identical(_operations[key], owner)) {
              _operations.remove(key);
            }
            owner.released.complete();
          },
        ),
      ),
    );
  }

  _SongContextKey _contextKey(SongMutationContext context) => _SongContextKey(
    userId: context.userId,
    organizationId: context.organizationId,
  );

  Future<SongDiscardResult> discardMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    final acquisition = await acquireDiscardLease(context);
    if (acquisition.outcome == SongDiscardLeaseOutcome.syncInProgress) {
      return SongDiscardResult.syncInProgress;
    }
    final lease = acquisition.lease!;
    try {
      await lease.discardMine(songId: songId);
      return SongDiscardResult.discarded;
    } finally {
      lease.release();
    }
  }

  Future<void> _discardMineOwned(
    SongMutationContext context, {
    required String songId,
  }) async {
    final record = await _requireSong(
      context,
      songId: songId,
      includeConflicts: true,
    );

    // Discarding is dropping local intent, so it must never need the network
    // (LF-7). The song's pending edit lives in its own table, which means the
    // cached snapshot still holds the last known server copy: dropping the
    // mutation row IS the restore. Fetching the server record only buys
    // freshness, and freshness is the refresh path's job.
    if (record.isRemoteDeletedConflict ||
        record.effectiveSyncStatus == SongSyncStatus.pendingCreate) {
      // Never existed remotely (or is already gone there): remove it locally.
      await _store.deleteSong(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
    } else {
      await _store.clearSongMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
    }

    // Best effort only: pick up the freshest server copy when there is a
    // connection. The discard has already happened and is never undone by a
    // failure here -- and a discard must never leave a conflict status
    // behind, because being conflicted is a sync outcome, not something the
    // user asked for by throwing their edit away.
    final refreshCatalog = _refreshCatalog;
    if (refreshCatalog == null) {
      return;
    }
    try {
      await refreshCatalog(context);
    } on SongMutationSyncException {
      // Offline or the backend refused: the local discard still stands.
      // The concrete refresh wired in production
      // (SongCatalogController.refreshCatalog, via song_library_providers.dart)
      // folds every failure into CatalogSnapshotState and never throws, so
      // this catch guards the SongCatalogRefresh interface contract rather
      // than anything actually observed today.
    }
  }

  Future<SongMutationRecord> _requireSong(
    SongMutationContext context, {
    required String songId,
    bool includeConflicts = false,
  }) async {
    final song = await _store.readById(
      userId: context.userId,
      organizationId: context.organizationId,
      songId: songId,
    );
    if (song == null) {
      throw StateError('Song mutation record not found: $songId');
    }

    if (!includeConflicts && song.syncStatus == SongSyncStatus.conflict) {
      throw StateError('Conflict record requires explicit conflict handling.');
    }

    return song;
  }

  Future<bool> _applySuccessfulSync(
    SongMutationContext context,
    SongMutationRecord syncedRecord, {
    required SongMutationRecord original,
    required int expectedRevision,
  }) async {
    final effectiveOriginalSyncStatus =
        original.conflictSourceSyncStatus ?? original.syncStatus;
    if (effectiveOriginalSyncStatus == SongSyncStatus.pendingDelete &&
        syncedRecord.syncStatus == SongSyncStatus.synced) {
      await _store.deleteSong(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: original.id,
      );
      return true;
    }

    // D2/D3 (docs/specs/2026-08-05-sync-snapshot-identity.md): [expectedRevision]
    // is the exact content this response concludes -- the pre-send snapshot's
    // own localRevision for an ordinary pendingUpdate/pendingDelete sync or
    // keepMine's pre-send read, or (docs/specs/2026-08-06-in-flight-create-
    // cancellation.md D1) the `sending` write's own reported revision for a
    // create, which is itself a local write and so has already advanced
    // localRevision past the pre-send snapshot value. Passing it lets the
    // store atomically detect a local edit -- or, for a create, a D2
    // cancellation tombstone -- that landed on this song during the remote
    // wait. A `false` return means exactly that happened -- not an error:
    // for an ordinary edit, nothing further to do here (the edit already
    // reset the row to pending with the newer content, so the next sync
    // sends it); for a create, the caller resolves the tombstone (D3).
    return _store.reconcileSyncedSong(
      userId: context.userId,
      organizationId: context.organizationId,
      record: syncedRecord.copyWith(
        syncStatus: SongSyncStatus.synced,
        clearErrorCode: true,
        clearErrorMessage: true,
        clearConflictSourceSyncStatus: true,
      ),
      expectedRevision: expectedRevision,
    );
  }
}
