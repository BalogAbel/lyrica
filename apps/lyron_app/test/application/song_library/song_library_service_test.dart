import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';

void main() {
  test('returns song summaries from the repository', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository, repository);

    final songs = await service.listSongs(
      context: const ActiveCatalogContext(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
    );

    expect(songs, hasLength(1));
    expect(songs.single.id, 'egy_ut');
    expect(songs.single.title, 'Egy út');
  });

  test('returns raw song source from the repository', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository, repository);

    final source = await service.getSongSource(
      context: const ActiveCatalogContext(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
      songId: 'egy_ut',
    );

    expect(repository.requestedSongId, 'egy_ut');
    expect(source.source, contains('{title:Egy út}'));
  });

  test('create queues a pending_create mutation with a generated slug', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository, repository);

    final created = await service.createSong(
      context: const ActiveCatalogContext(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
      title: 'Amazing Grace',
      chordproSource: '{title: Amazing Grace}',
    );

    expect(created.syncStatus, SongSyncStatus.pendingCreate);
    expect(created.slug, 'amazing-grace');
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(created.id),
      isTrue,
    );
  });

  test('create retries when the local slug collides before sync', () async {
    final repository = _FakeSongRepository()
      ..allocatedSlugs.addAll(const ['amazing-grace', 'amazing-grace-2'])
      ..rejectFirstUpsertWithSlugConflict = true;
    final service = SongLibraryService(repository, repository);

    final created = await service.createSong(
      context: const ActiveCatalogContext(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
      title: 'Amazing Grace',
      chordproSource: '{title: Amazing Grace}',
    );

    expect(created.slug, 'amazing-grace-2');
    expect(repository.upsertedSlugs, ['amazing-grace', 'amazing-grace-2']);
  });

  test(
    'update queues a pending_update mutation with the current base version',
    () async {
      final repository = _FakeSongRepository();
      repository.songById = const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'amazing-grace',
        title: 'Amazing Grace',
        chordproSource: '{title: Amazing Grace}',
        version: 7,
        baseVersion: 7,
        syncStatus: SongSyncStatus.synced,
      );
      final service = SongLibraryService(repository, repository);

      final updated = await service.updateSong(
        context: const ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        songId: 'song-1',
        title: 'Amazing Grace (Alt)',
        chordproSource: '{title: Amazing Grace (Alt)}',
      );

      expect(updated.syncStatus, SongSyncStatus.pendingUpdate);
      expect(updated.baseVersion, 7);
      expect(updated.slug, 'amazing-grace');
    },
  );

  test(
    'delete is blocked locally when a session item still references the song',
    () async {
      final repository = _FakeSongRepository();
      repository.songById = const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'amazing-grace',
        title: 'Amazing Grace',
        chordproSource: '{title: Amazing Grace}',
        version: 7,
        baseVersion: 7,
        syncStatus: SongSyncStatus.synced,
      );
      repository.referencingSessionItems = 1;
      final service = SongLibraryService(repository, repository);

      await expectLater(
        () => service.deleteSong(
          context: const ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          songId: 'song-1',
        ),
        throwsA(isA<SongDeleteBlockedException>()),
      );
    },
  );

  test(
    'delete cancels a never-synced local create without leaving a pending delete',
    () async {
      final repository = _FakeSongRepository();
      repository.songById = const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'amazing-grace',
        title: 'Amazing Grace',
        chordproSource: '{title: Amazing Grace}',
        version: 1,
        baseVersion: null,
        syncStatus: SongSyncStatus.pendingCreate,
      );
      final service = SongLibraryService(repository, repository);

      await service.deleteSong(
        context: const ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        songId: 'song-1',
      );

      expect(repository.deletedSongId, 'song-1');
      expect(repository.songById, isNull);
    },
  );

  test(
    'update rejects conflict rows until the user resolves the conflict',
    () async {
      final repository = _FakeSongRepository();
      repository.songById = const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'amazing-grace',
        title: 'Amazing Grace',
        chordproSource: '{title: Amazing Grace}',
        version: 7,
        baseVersion: 6,
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.conflict,
        conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
      );
      final service = SongLibraryService(repository, repository);

      await expectLater(
        () => service.updateSong(
          context: const ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          songId: 'song-1',
          title: 'Amazing Grace (Edited)',
          chordproSource: '{title: Amazing Grace (Edited)}',
        ),
        throwsA(isA<SongConflictResolutionRequiredException>()),
      );
    },
  );

  test(
    'delete rejects conflict rows until the user resolves the conflict',
    () async {
      final repository = _FakeSongRepository();
      repository.songById = const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'amazing-grace',
        title: 'Amazing Grace',
        chordproSource: '{title: Amazing Grace}',
        version: 7,
        baseVersion: 6,
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.conflict,
        conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
      );
      final service = SongLibraryService(repository, repository);

      await expectLater(
        () => service.deleteSong(
          context: const ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          songId: 'song-1',
        ),
        throwsA(isA<SongConflictResolutionRequiredException>()),
      );
    },
  );
}

class _FakeSongRepository
    implements SongCatalogReadRepository, SongMutationStore {
  String? requestedSongId;
  SongMutationRecord? songById;
  int referencingSessionItems = 0;
  String? deletedSongId;
  final List<String> allocatedSlugs = [];
  final List<String> upsertedSlugs = [];
  bool rejectFirstUpsertWithSlugConflict = false;

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async {
    return const [SongSummary(id: 'egy_ut', title: 'Egy út')];
  }

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    requestedSongId = songId;
    return const SongSource(id: 'egy_ut', source: '{title:Egy út}\n');
  }

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    return const SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út');
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    return const SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út');
  }

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async {
    if (allocatedSlugs.isNotEmpty) {
      return allocatedSlugs.removeAt(0);
    }
    return 'amazing-grace';
  }

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => referencingSessionItems;

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    deletedSongId = songId;
    if (songById?.id == songId) {
      songById = null;
    }
  }

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    songById = record;
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
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => songById;

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    upsertedSlugs.add(record.slug);
    if (rejectFirstUpsertWithSlugConflict) {
      rejectFirstUpsertWithSlugConflict = false;
      throw const LocalSongSlugConflictException();
    }
    songById = record;
  }
}
