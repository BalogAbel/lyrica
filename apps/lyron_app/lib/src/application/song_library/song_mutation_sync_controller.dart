import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

typedef SongCatalogRefresh = Future<void> Function(SongMutationContext context);

class SongMutationSyncController {
  const SongMutationSyncController({
    required SongMutationStore store,
    required SongMutationRemoteRepository remoteRepository,
    SongCatalogRefresh? refreshCatalog,
  }) : _store = store,
       _remoteRepository = remoteRepository,
       _refreshCatalog = refreshCatalog;

  final SongMutationStore _store;
  final SongMutationRemoteRepository _remoteRepository;
  final SongCatalogRefresh? _refreshCatalog;

  Future<void> syncPendingSongs(SongMutationContext context) async {
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
    if (record.isRemoteDeletedConflict) {
      await _store.deleteSong(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
      return;
    }
    try {
      final serverRecord = await _remoteRepository.fetchSong(
        organizationId: context.organizationId,
        songId: songId,
      );
      await _store.reconcileSyncedSong(
        userId: context.userId,
        organizationId: context.organizationId,
        record: serverRecord.copyWith(
          syncStatus: SongSyncStatus.synced,
          clearErrorCode: true,
          clearErrorMessage: true,
          clearConflictSourceSyncStatus: true,
        ),
      );
    } on SongMutationSyncException catch (error) {
      if (error.code == SongMutationSyncErrorCode.remoteDeleted &&
          record.effectiveSyncStatus == SongSyncStatus.pendingDelete) {
        final refreshCatalog = _refreshCatalog;
        if (refreshCatalog != null) {
          await refreshCatalog(context);
          await _store.clearSongMutation(
            userId: context.userId,
            organizationId: context.organizationId,
            songId: songId,
          );
        } else {
          await _store.deleteSong(
            userId: context.userId,
            organizationId: context.organizationId,
            songId: songId,
          );
        }
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
