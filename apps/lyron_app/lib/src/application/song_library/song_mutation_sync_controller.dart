import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

class SongMutationSyncController {
  const SongMutationSyncController({
    required SongMutationStore store,
    required SongMutationRemoteRepository remoteRepository,
  }) : _store = store,
       _remoteRepository = remoteRepository;

  final SongMutationStore _store;
  final SongMutationRemoteRepository _remoteRepository;

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
        await _store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          songId: record.id,
          syncStatus: error.code == SongMutationSyncErrorCode.conflict
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
    final syncedRecord = await _remoteRepository.overwriteSong(
      organizationId: context.organizationId,
      record: record,
    );
    await _applySuccessfulSync(context, syncedRecord, original: record);
  }

  Future<void> discardMine(
    SongMutationContext context, {
    required String songId,
  }) async {
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
