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
        expect(
          store.lastSavedErrorCode,
          SongMutationSyncErrorCode.remoteDeleted,
        );
        expect(
          store.lastUpsertedRecord?.conflictSourceSyncStatus,
          SongSyncStatus.pendingUpdate,
        );
      },
    );

    test(
      'accepts delete-sourced remote delete as converged deletion',
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
      },
    );

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

    test(
      'discard mine clears the mutation for an ordinary conflict row '
      'without touching the network, and the cached snapshot restores it',
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
            ),
          ],
          // The last known server copy, distinct from the local edit above,
          // so the assertions below can tell "restored" apart from "gone".
          snapshots: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 2,
              baseVersion: 2,
              syncStatus: SongSyncStatus.synced,
            ),
          ],
        );
        // No fetchHandler configured: discardMine must never call fetchSong
        // (LF-7), so leaving it unimplemented proves the point if it is.
        final repository = _FakeSongMutationRemoteRepository();
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        await controller.discardMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(store.clearedSongMutationId, 'song-1');
        expect(repository.fetchCalls, 0);

        final restored = await store.readById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(restored, isNotNull);
        expect(restored!.syncStatus, SongSyncStatus.synced);
        expect(restored.slug, 'alpha');
        expect(restored.title, 'Alpha');
        expect(restored.version, 2);
      },
    );

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
        var refreshCalls = 0;
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
          refreshCatalog: (_) async {
            refreshCalls += 1;
          },
        );

        await controller.discardMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(refreshCalls, 1);
        expect(store.clearedSongMutationId, 'song-1');
        expect(store.deletedSongId, isNull);
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

    test(
      'discardMine for pendingCreate deletes local entry when fetchSong returns remoteDeleted',
      () async {
        final store = _FakeSongMutationStore(
          pendingSongs: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 1,
              baseVersion: null,
              syncStatus: SongSyncStatus.pendingCreate,
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
        expect(store.lastSavedStatus, isNull);
      },
    );

    // LF-7: discardMine must never require the network. These pin the
    // fetch-first bug where an offline discard both fails AND corrupts the
    // record it was asked to throw away.
    test('discard mine on an offline pending update completes without throwing '
        'and restores the cached snapshot', () async {
      final store = _FakeSongMutationStore(
        pendingSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha-local',
            title: 'Alpha local',
            chordproSource: '{title: Alpha local}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingUpdate,
          ),
        ],
        // The last known server copy, distinct from the local edit above,
        // so the assertion below can tell "restored" apart from "gone".
        snapshots: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 2,
            baseVersion: 2,
            syncStatus: SongSyncStatus.synced,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        fetchHandler: (songId) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.connectivityFailure,
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

      // The mutation row is gone, but the song itself is not: it falls back
      // to the cached snapshot, reading back as the server's last known
      // (synced) copy rather than the discarded local edit.
      final remaining = await store.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(remaining, isNotNull);
      expect(remaining!.syncStatus, SongSyncStatus.synced);
      expect(remaining.slug, 'alpha');
      expect(remaining.title, 'Alpha');
      expect(remaining.version, 2);
    });

    test('discard mine on an offline pending update never marks the record as '
        'conflict', () async {
      final store = _FakeSongMutationStore(
        pendingSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha-local',
            title: 'Alpha local',
            chordproSource: '{title: Alpha local}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingUpdate,
          ),
        ],
        snapshots: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 2,
            baseVersion: 2,
            syncStatus: SongSyncStatus.synced,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        fetchHandler: (songId) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
      );

      try {
        await controller.discardMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );
      } on SongMutationSyncException {
        // This test only cares what happened to the persisted record, not
        // whether the call also threw -- that is covered separately above.
      }

      // saveSyncAttemptResult is the only path that can write
      // SongSyncStatus.conflict. Discarding must never take it.
      expect(store.lastSavedStatus, isNot(SongSyncStatus.conflict));
      final remaining = await store.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      // Restored from the snapshot as synced, not left as (or promoted to)
      // conflict.
      expect(remaining?.syncStatus, SongSyncStatus.synced);
    });

    test(
      'discard mine on an offline pending create deletes the song locally',
      () async {
        final store = _FakeSongMutationStore(
          pendingSongs: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 1,
              baseVersion: null,
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          ],
        );
        final repository = _FakeSongMutationRemoteRepository(
          fetchHandler: (songId) async => throw const SongMutationSyncException(
            SongMutationSyncErrorCode.connectivityFailure,
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
        final remaining = await store.readById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(remaining, isNull);
      },
    );

    test('discard mine survives a best-effort refresh that throws while '
        'offline', () async {
      final store = _FakeSongMutationStore(
        pendingSongs: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha-local',
            title: 'Alpha local',
            chordproSource: '{title: Alpha local}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingUpdate,
          ),
        ],
        snapshots: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 2,
            baseVersion: 2,
            syncStatus: SongSyncStatus.synced,
          ),
        ],
      );
      final repository = _FakeSongMutationRemoteRepository(
        fetchHandler: (songId) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = SongMutationSyncController(
        store: store,
        remoteRepository: repository,
        refreshCatalog: (_) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.connectivityFailure,
        ),
      );

      await controller.discardMine(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        songId: 'song-1',
      );

      // The local discard stands (mutation gone, restored to the cached
      // snapshot) even though the best-effort refresh failed.
      final remaining = await store.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(remaining, isNotNull);
      expect(remaining!.syncStatus, SongSyncStatus.synced);
    });
  });
}

class _FakeSongMutationStore implements SongMutationStore {
  _FakeSongMutationStore({
    List<SongMutationRecord> pendingSongs = const [],
    List<SongMutationRecord> conflictSongs = const [],
    List<SongMutationRecord> snapshots = const [],
  }) : _mutations = {
         for (final record in [...pendingSongs, ...conflictSongs])
           record.id: record,
       },
       _snapshots = {for (final record in snapshots) record.id: record};

  // Mirrors CachedCatalogSongMutations: pending/conflict rows only.
  final Map<String, SongMutationRecord> _mutations;

  // Mirrors CachedCatalogSummaries/CachedCatalogSources: the last known
  // server copy for the song. Production's clearSongMutation never touches
  // these tables, so a discarded pendingUpdate/conflict record falls back to
  // whatever is here -- that fallback IS the restore D1 relies on. A
  // pendingCreate has no entry here because it never synced.
  final Map<String, SongMutationRecord> _snapshots;

  SongMutationSyncErrorCode? lastSavedErrorCode;
  SongSyncStatus? lastSavedStatus;
  SongMutationRecord? lastUpsertedRecord;
  String? deletedSongId;
  String? clearedSongMutationId;

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => _mutations[songId] ?? _snapshots[songId];

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => _mutations.values
      .where((record) => record.syncStatus == SongSyncStatus.conflict)
      .toList(growable: false);

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => _mutations.values
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
      _mutations[songId] = lastUpsertedRecord!;
    }
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
    _mutations[record.id] = record;
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    deletedSongId = songId;
    // Mirrors production DriftSongCatalogStore.deleteSong: removes the
    // mutation row AND the cached summary/source snapshot. Nothing is left
    // to restore from -- there is nothing left of the song at all.
    _mutations.remove(songId);
    _snapshots.remove(songId);
  }

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) async {
    lastUpsertedRecord = record;
    // Mirrors production: a successful sync clears the mutation row and
    // (re)writes the cached snapshot with the server's copy. The D2 revision
    // gate itself is proven against the real DriftSongCatalogStore in
    // song_sync_snapshot_identity_test.dart (a fake could too easily "pass"
    // by encoding the desired behaviour directly), so this fake applies
    // unconditionally regardless of expectedRevision.
    _mutations.remove(record.id);
    _snapshots[record.id] = record;
    return true;
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    clearedSongMutationId = songId;
    // Mirrors production DriftSongCatalogStore.clearSongMutation: only the
    // mutation row is removed. The cached snapshot (if any) is left alone,
    // so readById below falls back to it -- that fallback IS the restore.
    _mutations.remove(songId);
  }

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
