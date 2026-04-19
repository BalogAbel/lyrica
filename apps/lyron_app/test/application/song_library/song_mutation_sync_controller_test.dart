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

    test(
      'classifies update-sourced remote delete as conflict with durable metadata',
      () async {
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
            SongMutationSyncErrorCode.remoteDeleted,
          ),
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        await controller.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        expect(store.lastSavedStatus, SongSyncStatus.conflict);
        expect(store.lastSavedErrorCode, SongMutationSyncErrorCode.remoteDeleted);
        expect(
          store.lastUpsertedRecord?.conflictSourceSyncStatus,
          SongSyncStatus.pendingUpdate,
        );
      },
    );

    test('accepts delete-sourced remote delete as converged deletion', () async {
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
          SongMutationSyncErrorCode.remoteDeleted,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      await controller.syncPendingSongs(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
      );

      expect(store.deletedSongId, 'song-1');
      expect(store.lastSavedStatus, isNull);
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

    test(
      'discard mine accepts remote deletion for update-sourced remote-delete conflicts',
      () async {
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
              errorCode: SongMutationSyncErrorCode.remoteDeleted,
              conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
            ),
          ],
        );
        final repository = _FakeSongMutationRemoteRepository();
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        await controller.discardMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(store.deletedSongId, 'song-1');
        expect(repository.fetchCalls, 0);
      },
    );

    test(
      'keep mine accepts deletion when remote-delete conflict came from pending delete',
      () async {
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
              errorCode: SongMutationSyncErrorCode.remoteDeleted,
              conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
            ),
          ],
        );
        final repository = _FakeSongMutationRemoteRepository();
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        await controller.keepMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(store.deletedSongId, 'song-1');
        expect(repository.overwriteCalls, 0);
      },
    );

    test(
      'keep mine accepts deletion when delete conflict later becomes remote deleted during overwrite',
      () async {
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
              errorCode: SongMutationSyncErrorCode.conflict,
              conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
            ),
          ],
        );
        final repository = _FakeSongMutationRemoteRepository(
          overwriteHandler: (record) async =>
              throw const SongMutationSyncException(
                SongMutationSyncErrorCode.remoteDeleted,
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

        expect(store.deletedSongId, 'song-1');
      },
    );

    test(
      'discard mine accepts deletion when delete conflict later becomes remote deleted during fetch',
      () async {
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
              errorCode: SongMutationSyncErrorCode.conflict,
              conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
            ),
          ],
        );
        final repository = _FakeSongMutationRemoteRepository(
          fetchHandler: (songId) async => throw const SongMutationSyncException(
            SongMutationSyncErrorCode.remoteDeleted,
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

        expect(store.deletedSongId, 'song-1');
      },
    );

    test(
      'keep mine persists the failure on the conflict row before rethrowing',
      () async {
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
          overwriteHandler: (record) async =>
              throw const SongMutationSyncException(
                SongMutationSyncErrorCode.dependencyBlocked,
              ),
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        await expectLater(
          () => controller.keepMine(
            const SongMutationContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            songId: 'song-1',
          ),
          throwsA(isA<SongMutationSyncException>()),
        );

        expect(store.lastSavedStatus, SongSyncStatus.conflict);
        expect(
          store.lastSavedErrorCode,
          SongMutationSyncErrorCode.dependencyBlocked,
        );
        expect(
          store.lastUpsertedRecord?.conflictSourceSyncStatus,
          SongSyncStatus.pendingDelete,
        );
      },
    );

    test(
      'discard mine persists the failure on the conflict row before rethrowing',
      () async {
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
              conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
            ),
          ],
        );
        final repository = _FakeSongMutationRemoteRepository(
          fetchHandler: (songId) async => throw const SongMutationSyncException(
            SongMutationSyncErrorCode.authorizationDenied,
          ),
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        await expectLater(
          () => controller.discardMine(
            const SongMutationContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            songId: 'song-1',
          ),
          throwsA(isA<SongMutationSyncException>()),
        );

        expect(store.lastSavedStatus, SongSyncStatus.conflict);
        expect(
          store.lastSavedErrorCode,
          SongMutationSyncErrorCode.authorizationDenied,
        );
        expect(
          store.lastUpsertedRecord?.conflictSourceSyncStatus,
          SongSyncStatus.pendingUpdate,
        );
      },
    );

    test('stops syncing later records after a connectivity failure', () async {
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
          SongMutationRecord(
            id: 'song-2',
            organizationId: 'org-1',
            slug: 'beta',
            title: 'Beta',
            chordproSource: '{title: Beta}',
            version: 1,
            baseVersion: null,
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        syncHandler: (record) async {
          if (record.id == 'song-1') {
            throw const SongMutationSyncException(
              SongMutationSyncErrorCode.connectivityFailure,
            );
          }
          return record.copyWith(syncStatus: SongSyncStatus.synced);
        },
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      await controller.syncPendingSongs(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
      );

      expect(repository.syncedSongIds, ['song-1']);
      expect(
        store.lastSavedErrorCode,
        SongMutationSyncErrorCode.connectivityFailure,
      );
    });
  });
}

class _FakeSongMutationStore implements SongMutationStore {
  _FakeSongMutationStore({
    List<SongMutationRecord> pendingSongs = const [],
    List<SongMutationRecord> conflictSongs = const [],
  }) : _records = {
         for (final record in [...pendingSongs, ...conflictSongs])
           record.id: record,
       };

  final Map<String, SongMutationRecord> _records;

  SongMutationSyncErrorCode? lastSavedErrorCode;
  SongSyncStatus? lastSavedStatus;
  SongMutationRecord? lastUpsertedRecord;
  String? deletedSongId;

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => _records[songId];

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => _records.values
      .where((record) => record.syncStatus == SongSyncStatus.conflict)
      .toList(growable: false);

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => _records.values
      .where(
        (record) => switch (record.syncStatus) {
          SongSyncStatus.pendingCreate ||
          SongSyncStatus.pendingUpdate ||
          SongSyncStatus.pendingDelete => true,
          SongSyncStatus.conflict || SongSyncStatus.synced => false,
        },
      )
      .toList(growable: false);

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
            ? (existing.conflictSourceSyncStatus ?? existing.syncStatus)
            : null,
        clearConflictSourceSyncStatus: syncStatus != SongSyncStatus.conflict,
      );
      _records[songId] = lastUpsertedRecord!;
    }
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
    _records[record.id] = record;
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    deletedSongId = songId;
    _records.remove(songId);
  }

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
    _records[record.id] = record;
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
  int fetchCalls = 0;
  SongSyncStatus? lastOverwriteRpcType;
  final List<String> syncedSongIds = [];

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) {
    fetchCalls += 1;
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
    syncedSongIds.add(record.id);
    final handler = _syncHandler;
    if (handler == null) {
      throw UnimplementedError();
    }
    return handler(record);
  }
}
