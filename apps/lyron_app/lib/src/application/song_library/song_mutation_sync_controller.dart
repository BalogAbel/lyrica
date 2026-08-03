import 'dart:async';

import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

typedef SongCatalogRefresh = Future<void> Function(SongMutationContext context);

enum SongDiscardResult { discarded, syncInProgress }

enum SongDiscardLeaseOutcome { acquired, syncInProgress }

class SongDiscardLease {
  SongDiscardLease({
    required Future<void> Function(String songId) discardSong,
    required void Function() release,
  }) : _discardSong = discardSong,
       _release = release;

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
}

class SongMutationSyncController {
  SongMutationSyncController({
    required SongMutationStore store,
    required SongMutationRemoteRepository remoteRepository,
    SongCatalogRefresh? refreshCatalog,
  }) : _store = store,
       _remoteRepository = remoteRepository,
       _refreshCatalog = refreshCatalog;

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
      return current.released.future.then((_) => syncPendingSongs(context));
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
      try {
        final syncedRecord = await _remoteRepository.syncSong(
          organizationId: context.organizationId,
          record: record,
        );
        await _applySuccessfulSync(context, syncedRecord, original: record);
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
        await _store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          songId: record.id,
          syncStatus:
              error.code == SongMutationSyncErrorCode.conflict ||
                  error.code == SongMutationSyncErrorCode.remoteDeleted
              ? SongSyncStatus.conflict
              : record.syncStatus,
          errorCode: error.code,
          errorMessage: error.message,
        );
        if (error.code == SongMutationSyncErrorCode.connectivityFailure) {
          break;
        }
      }
    }
  }

  Future<void> keepMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    final record = await _requireSong(
      context,
      songId: songId,
      includeConflicts: true,
    );
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
      await _applySuccessfulSync(context, syncedRecord, original: record);
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
      await _store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
        syncStatus: SongSyncStatus.conflict,
        errorCode: error.code,
        errorMessage: error.message,
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

  Future<void> _applySuccessfulSync(
    SongMutationContext context,
    SongMutationRecord syncedRecord, {
    required SongMutationRecord original,
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
      return;
    }

    await _store.reconcileSyncedSong(
      userId: context.userId,
      organizationId: context.organizationId,
      record: syncedRecord.copyWith(
        syncStatus: SongSyncStatus.synced,
        clearErrorCode: true,
        clearErrorMessage: true,
        clearConflictSourceSyncStatus: true,
      ),
    );
  }
}
