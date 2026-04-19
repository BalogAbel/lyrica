import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('local-first song CRUD flow', () {
    late SongCatalogDatabase songDatabase;
    late DriftSongCatalogStore songStore;
    late PlanningLocalDatabase planningDatabase;
    late DriftPlanningLocalStore planningStore;
    late DriftSongMutationStore mutationStore;
    late LocalFirstSongRepository localRepository;
    late SongLibraryService service;

    const context = ActiveCatalogContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      songDatabase = SongCatalogDatabase.inMemory();
      songStore = DriftSongCatalogStore(songDatabase);
      planningDatabase = PlanningLocalDatabase.inMemory();
      planningStore = DriftPlanningLocalStore(planningDatabase);
      mutationStore = DriftSongMutationStore(
        songCatalogStore: songStore,
        planningLocalStore: planningStore,
      );
      localRepository = LocalFirstSongRepository(songStore);
      service = SongLibraryService(
        localRepository,
        mutationStore,
        () => 'created-song',
      );
    });

    tearDown(() async {
      await planningDatabase.close();
      await songDatabase.close();
    });

    test(
      'offline create syncs and reconciles the canonical server slug',
      () async {
        final syncController = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: _FakeSongMutationRemoteRepository(
            syncHandler: (record) async => record.copyWith(
              slug: 'new-song-2',
              version: 2,
              baseVersion: 2,
              syncStatus: SongSyncStatus.synced,
            ),
          ),
        );

        await service.createSong(
          context: context,
          title: 'New Song',
          chordproSource: '{title: New Song}',
        );

        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'new-song',
          ),
          isNotNull,
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isTrue,
        );

        await syncController.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        final reconciled = await localRepository.getSongSummaryBySlug(
          userId: context.userId,
          organizationId: context.organizationId,
          songSlug: 'new-song-2',
        );
        expect(reconciled, isNotNull);
        expect(reconciled!.id, 'created-song');
        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'new-song',
          ),
          isNull,
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
      },
    );

    test('offline update conflict can be explicitly overwritten', () async {
      await _seedSong(
        songStore,
        summary: const SongSummary(
          id: 'song-1',
          slug: 'amazing-grace',
          title: 'Amazing Grace',
          version: 3,
        ),
        source: const SongSource(
          id: 'song-1',
          source: '{title: Amazing Grace}',
        ),
      );

      final syncController = SongMutationSyncController(
        store: mutationStore,
        remoteRepository: _FakeSongMutationRemoteRepository(
          syncHandler: (record) async => throw const SongMutationSyncException(
            SongMutationSyncErrorCode.conflict,
          ),
          overwriteHandler: (record) async => record.copyWith(
            version: 4,
            baseVersion: 4,
            syncStatus: SongSyncStatus.synced,
          ),
        ),
      );

      await service.updateSong(
        context: context,
        songId: 'song-1',
        title: 'Amazing Grace (Offline)',
        chordproSource: '{title: Amazing Grace (Offline)}',
      );
      await syncController.syncPendingSongs(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
      );

      final conflicted = await mutationStore.readConflictSongs(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(conflicted.single.id, 'song-1');

      await syncController.keepMine(
        const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        songId: 'song-1',
      );

      final songs = await localRepository.listSongs(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(songs, const [
        SongSummary(
          id: 'song-1',
          slug: 'amazing-grace',
          title: 'Amazing Grace (Offline)',
          version: 4,
        ),
      ]);
      expect(
        await mutationStore.hasUnsyncedChanges(userId: context.userId),
        isFalse,
      );
    });

    test(
      'pending delete is hidden immediately and accepted delete clears the song',
      () async {
        await _seedSong(
          songStore,
          summary: const SongSummary(
            id: 'song-1',
            slug: 'delete-me',
            title: 'Delete Me',
            version: 2,
          ),
          source: const SongSource(id: 'song-1', source: '{title: Delete Me}'),
        );

        final syncController = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: _FakeSongMutationRemoteRepository(
            syncHandler: (record) async => record.copyWith(
              version: 3,
              baseVersion: 3,
              syncStatus: SongSyncStatus.synced,
            ),
          ),
        );

        await service.deleteSong(context: context, songId: 'song-1');

        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'delete-me',
          ),
          isNull,
        );

        await syncController.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        expect(
          await localRepository.listSongs(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          isEmpty,
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
      },
    );

    test(
      'local session references block delete and explicit sign-out discards pending mutations',
      () async {
        await _seedSong(
          songStore,
          summary: const SongSummary(
            id: 'song-1',
            slug: 'still-used',
            title: 'Still Used',
            version: 1,
          ),
          source: const SongSource(id: 'song-1', source: '{title: Still Used}'),
        );
        await planningStore.replaceActiveProjection(
          userId: context.userId,
          organizationId: context.organizationId,
          plans: [
            CachedPlanRecord(
              id: 'plan-1',
              slug: 'plan-1',
              name: 'Plan',
              description: null,
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 4, 8),
            ),
          ],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              slug: 'session-1',
              position: 0,
              name: 'Session',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 0,
              songId: 'song-1',
              songTitle: 'Still Used',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 8),
        );

        await expectLater(
          () => service.deleteSong(context: context, songId: 'song-1'),
          throwsA(isA<SongDeleteBlockedException>()),
        );

        await service.createSong(
          context: context,
          title: 'Unsynced Song',
          chordproSource: '{title: Unsynced Song}',
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isTrue,
        );

        final controller = SongCatalogController(
          store: songStore,
          remoteRepository: _NoopSongRepository(),
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: const _StaticForegroundState(isForeground: false),
        );

        await controller.handleExplicitSignOut();

        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
        expect(
          await localRepository.listSongs(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          isEmpty,
        );
      },
    );

    test(
      'remote delete versus local pending update can recreate same id on keep mine',
      () async {
        await _seedSong(
          songStore,
          summary: const SongSummary(
            id: 'song-1',
            slug: 'amazing-grace',
            title: 'Amazing Grace',
            version: 3,
          ),
          source: const SongSource(
            id: 'song-1',
            source: '{title: Amazing Grace}',
          ),
        );

        final syncController = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: _FakeSongMutationRemoteRepository(
            syncHandler: (record) async =>
                throw const SongMutationSyncException(
                  SongMutationSyncErrorCode.remoteDeleted,
                ),
            overwriteHandler: (record) async => record.copyWith(
              slug: 'amazing-grace-2',
              version: 1,
              baseVersion: 1,
              syncStatus: SongSyncStatus.synced,
            ),
          ),
        );

        await service.updateSong(
          context: context,
          songId: 'song-1',
          title: 'Amazing Grace (Offline)',
          chordproSource: '{title: Amazing Grace (Offline)}',
        );
        await syncController.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        final conflicts = await mutationStore.readConflictSongs(
          userId: context.userId,
          organizationId: context.organizationId,
        );
        expect(
          conflicts.single.errorCode,
          SongMutationSyncErrorCode.remoteDeleted,
        );

        await syncController.keepMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'amazing-grace-2',
          ),
          const SongSummary(
            id: 'song-1',
            slug: 'amazing-grace-2',
            title: 'Amazing Grace (Offline)',
            version: 1,
          ),
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
      },
    );

    test(
      'remote delete versus local pending update can discard mine without fetching a canonical row',
      () async {
        await _seedSong(
          songStore,
          summary: const SongSummary(
            id: 'song-1',
            slug: 'amazing-grace',
            title: 'Amazing Grace',
            version: 3,
          ),
          source: const SongSource(
            id: 'song-1',
            source: '{title: Amazing Grace}',
          ),
        );

        final syncController = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: _FakeSongMutationRemoteRepository(
            syncHandler: (record) async =>
                throw const SongMutationSyncException(
                  SongMutationSyncErrorCode.remoteDeleted,
                ),
          ),
        );

        await service.updateSong(
          context: context,
          songId: 'song-1',
          title: 'Amazing Grace (Offline)',
          chordproSource: '{title: Amazing Grace (Offline)}',
        );
        await syncController.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        await syncController.discardMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'amazing-grace',
          ),
          isNull,
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
      },
    );

    test(
      'remote delete versus local pending delete converges as accepted deletion',
      () async {
        await _seedSong(
          songStore,
          summary: const SongSummary(
            id: 'song-1',
            slug: 'delete-me',
            title: 'Delete Me',
            version: 2,
          ),
          source: const SongSource(id: 'song-1', source: '{title: Delete Me}'),
        );

        final syncController = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: _FakeSongMutationRemoteRepository(
            syncHandler: (record) async =>
                throw const SongMutationSyncException(
                  SongMutationSyncErrorCode.remoteDeleted,
                ),
          ),
        );

        await service.deleteSong(context: context, songId: 'song-1');
        await syncController.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'delete-me',
          ),
          isNull,
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
      },
    );

    test(
      'discard mine refreshes catalog before clearing a delete conflict that became remotely deleted',
      () async {
        await _seedSong(
          songStore,
          summary: const SongSummary(
            id: 'song-1',
            slug: 'delete-me',
            title: 'Delete Me',
            version: 2,
          ),
          source: const SongSource(id: 'song-1', source: '{title: Delete Me}'),
        );

        final syncController = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: _FakeSongMutationRemoteRepository(
            syncHandler: (record) async =>
                throw const SongMutationSyncException(
                  SongMutationSyncErrorCode.conflict,
                ),
            fetchHandler: (songId) async =>
                throw const SongMutationSyncException(
                  SongMutationSyncErrorCode.remoteDeleted,
                ),
          ),
          refreshCatalog: (_) async {
            await songStore.replaceActiveSnapshot(
              userId: context.userId,
              organizationId: context.organizationId,
              summaries: const [],
              sources: const [],
              refreshedAt: DateTime.now().toUtc(),
            );
          },
        );

        await service.deleteSong(context: context, songId: 'song-1');
        await syncController.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );

        await syncController.discardMine(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
          songId: 'song-1',
        );

        expect(
          await localRepository.getSongSummaryBySlug(
            userId: context.userId,
            organizationId: context.organizationId,
            songSlug: 'delete-me',
          ),
          isNull,
        );
        expect(
          await mutationStore.hasUnsyncedChanges(userId: context.userId),
          isFalse,
        );
      },
    );
  });
}

Future<void> _seedSong(
  DriftSongCatalogStore store, {
  required SongSummary summary,
  required SongSource source,
}) {
  return store.replaceActiveSnapshot(
    userId: 'user-1',
    organizationId: 'org-1',
    summaries: [summary],
    sources: [source],
    refreshedAt: DateTime.utc(2026, 4, 8),
  );
}

class _FakeSongMutationRemoteRepository
    implements SongMutationRemoteRepository {
  _FakeSongMutationRemoteRepository({
    required this.syncHandler,
    this.overwriteHandler,
    this.fetchHandler,
  });

  final Future<SongMutationRecord> Function(SongMutationRecord record)
  syncHandler;
  final Future<SongMutationRecord> Function(SongMutationRecord record)?
  overwriteHandler;
  final Future<SongMutationRecord> Function(String songId)? fetchHandler;

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) async {
    final handler = fetchHandler;
    if (handler == null) {
      throw StateError('fetchSong handler was not configured.');
    }
    return handler(songId);
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    final handler = overwriteHandler;
    if (handler == null) {
      throw StateError('overwriteSong handler was not configured.');
    }
    return handler(record);
  }

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    return syncHandler(record);
  }
}

class _NoopSongRepository implements SongRepository {
  @override
  Future<SongSource> getSongSource(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<SongSummary>> listSongs() async {
    return const [];
  }
}

class _StaticForegroundState implements AppForegroundState {
  const _StaticForegroundState({required this.isForeground});

  @override
  final bool isForeground;

  @override
  Stream<bool> watchForeground() => const Stream<bool>.empty();
}
