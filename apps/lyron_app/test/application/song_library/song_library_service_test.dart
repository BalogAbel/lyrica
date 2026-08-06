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

  // docs/specs/2026-08-06-in-flight-create-cancellation.md D4 draws the
  // line between "a row vanished while a sync was concluding a remote
  // attempt for it" (DriftSongMutationStore.saveSyncAttemptResult -- fixed
  // to report false instead of throwing, see song_catalog_store_test.dart)
  // and this: a direct, single-shot user action whose target genuinely
  // does not exist in local storage at all (no pending mutation AND no
  // synced snapshot). There is no sync loop here, so no other queued work
  // is ever at risk of being aborted -- these deliberately stay
  // StateErrors (Error, not a recoverable domain rejection), pinned so a
  // future change does not accidentally widen D4's scope to cover them.
  test('update against a song absent from local storage entirely still throws '
      '(not the D4 vanished-record case -- there is no sync loop here to '
      'protect)', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository, repository);

    await expectLater(
      () => service.updateSong(
        context: const ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        songId: 'ghost-song',
        title: 'Ghost',
        chordproSource: '{title: Ghost}',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('delete against a song absent from local storage entirely still throws '
      '(not the D4 vanished-record case -- there is no sync loop here to '
      'protect)', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository, repository);

    await expectLater(
      () => service.deleteSong(
        context: const ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        songId: 'ghost-song',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('create normalizes chordpro source aliases before storing', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository, repository);

    await service.createSong(
      context: const ActiveCatalogContext(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
      title: 'Test',
      chordproSource: '{t: Test}\n{soc}\n[A]Hello\n{eoc}\n',
    );

    expect(
      repository.lastUpsertedRecord?.chordproSource,
      '{title: Test}\n{start_of_chorus}\n[A]Hello\n{end_of_chorus}\n',
    );
  });

  test('update normalizes chordpro source aliases before storing', () async {
    final repository = _FakeSongRepository();
    repository.songById = const SongMutationRecord(
      id: 'song-1',
      organizationId: 'org-1',
      slug: 'test',
      title: 'Test',
      chordproSource: '{title: Test}',
      version: 1,
      baseVersion: 1,
      syncStatus: SongSyncStatus.synced,
    );
    final service = SongLibraryService(repository, repository);

    await service.updateSong(
      context: const ActiveCatalogContext(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
      songId: 'song-1',
      title: 'Test',
      chordproSource: '{t: Test}\n{soc}\n[A]Hello\n{eoc}\n',
    );

    expect(
      repository.lastUpsertedRecord?.chordproSource,
      '{title: Test}\n{start_of_chorus}\n[A]Hello\n{end_of_chorus}\n',
    );
  });
}

class _FakeSongRepository
    implements SongCatalogReadRepository, SongMutationStore {
  // Stubs for docs/specs/2026-08-06-in-flight-create-cancellation.md
  // (D1/D3): none of these tests exercise the in-flight-create-cancellation
  // sending marker or tombstone path (SongLibraryService.deleteSong's own
  // `sending` -> `cancelling` branch is covered directly against this fake
  // via upsertSong; the full race is covered against the real
  // DriftSongCatalogStore/DriftSongMutationStore in
  // test/offline/adversarial/song_in_flight_create_cancellation_test.dart).
  // Applied unconditionally, ignoring expectedRevision.
  @override
  Future<int?> markCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) async => expectedRevision + 1;

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) async => false;

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
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) async {
    songById = record;
    return true;
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
  Future<bool> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async => true;

  SongMutationRecord? lastUpsertedRecord;

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
    upsertedSlugs.add(record.slug);
    if (rejectFirstUpsertWithSlugConflict) {
      rejectFirstUpsertWithSlugConflict = false;
      throw const LocalSongSlugConflictException();
    }
    songById = record;
  }
}
