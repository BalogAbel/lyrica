import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

void main() {
  group('SongMutationSyncController', () {
    test('marks authorization failures as non-retryable sync errors', () async {
      final store = _FakeSongMutationStore(
        pendingSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingUpdate,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        syncHandler: (record) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.authorizationDenied,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      await controller.syncPendingSongs(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
      );

      expect(
        store.lastSavedErrorCode,
        SongMutationSyncErrorCode.authorizationDenied,
      );
      expect(store.lastSavedStatus, SongSyncStatus.pendingUpdate);
      expect(repository.overwriteCalls, 0);
    });

    test('reclassifies stale ordinary writes as conflict', () async {
      final store = _FakeSongMutationStore(
        pendingSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingDelete,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        syncHandler: (record) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.conflict,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      await controller.syncPendingSongs(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
      );

      expect(store.lastSavedErrorCode, SongMutationSyncErrorCode.conflict);
      expect(store.lastSavedStatus, SongSyncStatus.conflict);
      expect(
        store.lastUpsertedRecord?.conflictSourceSyncStatus,
        SongSyncStatus.pendingDelete,
      );
    });

    test('uses the dedicated overwrite path for keep mine', () async {
      final store = _FakeSongMutationStore(
        conflictSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.conflict,
            conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        overwriteHandler: (record) async => record.copyWith(
          version: 4,
          baseVersion: 4,
          syncStatus: SongSyncStatus.synced,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      await controller.keepMine(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        songId: 'song-1',
      );

      expect(repository.overwriteCalls, 1);
      expect(repository.lastOverwriteRpcType, SongSyncStatus.pendingDelete);
      expect(store.deletedSongId, 'song-1');
    });

    test('discard mine restores the latest server row', () async {
      final store = _FakeSongMutationStore(
        conflictSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha-local',
            title: 'Alpha local',
            chordproSource: '{title: Alpha local}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.conflict,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        fetchHandler: (songId) async => const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 8,
          baseVersion: 8,
          syncStatus: SongSyncStatus.synced,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      await controller.discardMine(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        songId: 'song-1',
      );

      expect(store.lastUpsertedRecord?.slug, 'alpha');
      expect(store.lastUpsertedRecord?.syncStatus, SongSyncStatus.synced);
    });
  });
}

class _FakeSongMutationStore implements SongMutationStore {
  _FakeSongMutationStore({
    List<SongMutationRecord> pendingSongs = const [],
    List<SongMutationRecord> conflictSongs = const [],
  }) : _pendingSongs = pendingSongs,
       _conflictSongs = conflictSongs;

  final List<SongMutationRecord> _pendingSongs;
  final List<SongMutationRecord> _conflictSongs;

  SongMutationSyncErrorCode? lastSavedErrorCode;
  SongSyncStatus? lastSavedStatus;
  SongMutationRecord? lastUpsertedRecord;
  String? deletedSongId;

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final records = <SongMutationRecord>[..._pendingSongs, ..._conflictSongs];
    final upsertedRecord = lastUpsertedRecord;
    if (upsertedRecord != null) {
      records.add(upsertedRecord);
    }
    return records.where((record) => record.id == songId).firstOrNull;
  }

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async {
    return _conflictSongs;
  }

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async {
    return _pendingSongs;
  }

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {
    lastSavedStatus = syncStatus;
    lastSavedErrorCode = errorCode;
    final existing = await readById(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (existing != null) {
      lastUpsertedRecord = existing.copyWith(
        syncStatus: syncStatus,
        errorCode: errorCode,
        errorMessage: errorMessage,
        conflictSourceSyncStatus: syncStatus == SongSyncStatus.conflict
            ? existing.syncStatus
            : null,
        clearConflictSourceSyncStatus: syncStatus != SongSyncStatus.conflict,
      );
    }
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    deletedSongId = songId;
  }

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async => 'unused';
}

class _FakeSongMutationRemoteRepository
    implements SongMutationRemoteRepository {
  _FakeSongMutationRemoteRepository({
    Future<SongMutationRecord> Function(SongMutationRecord record)? syncHandler,
    Future<SongMutationRecord> Function(SongMutationRecord record)?
    overwriteHandler,
    Future<SongMutationRecord> Function(String songId)? fetchHandler,
  }) : _syncHandler = syncHandler,
       _overwriteHandler = overwriteHandler,
       _fetchHandler = fetchHandler;

  final Future<SongMutationRecord> Function(SongMutationRecord record)?
  _syncHandler;
  final Future<SongMutationRecord> Function(SongMutationRecord record)?
  _overwriteHandler;
  final Future<SongMutationRecord> Function(String songId)? _fetchHandler;

  int overwriteCalls = 0;
  SongSyncStatus? lastOverwriteRpcType;

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) {
    final handler = _fetchHandler;
    if (handler == null) {
      throw UnimplementedError();
    }
    return handler(songId);
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    overwriteCalls += 1;
    lastOverwriteRpcType = record.conflictSourceSyncStatus ?? record.syncStatus;
    final handler = _overwriteHandler;
    if (handler == null) {
      throw UnimplementedError();
    }
    return handler(record);
  }

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    final handler = _syncHandler;
    if (handler == null) {
      throw UnimplementedError();
    }
    return handler(record);
  }
}
