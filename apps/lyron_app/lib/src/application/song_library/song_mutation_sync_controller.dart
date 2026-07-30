import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

typedef SongCatalogRefresh = Future<void> Function(SongMutationContext context);

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

  // Single-flight keyed by sync context. This controller is an app-scoped
  // singleton, so a global in-flight future would let a sync for one
  // user/organization coalesce a concurrent sync for a *different* one,
  // skipping the second context's pending songs. Key by user + organization
  // so coalescing only ever merges triggers for the same context.
  final Map<String, Future<void>> _inFlight = {};

  Future<void> syncPendingSongs(SongMutationContext context) {
    final key = '${context.userId}_${context.organizationId}';
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    // Block body: Map.remove returns the removed future, and a whenComplete
    // callback that returns a future would wait on it (here, the very future
    // being completed) and deadlock. Discard the return value.
    final run = _runSync(context).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = run;
    return run;
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

  Future<void> discardMine(
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
