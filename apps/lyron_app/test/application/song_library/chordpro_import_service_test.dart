import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

const _context = ActiveCatalogContext(userId: 'u1', organizationId: 'org1');

void main() {
  late _FakeRepo repo;
  late ChordProImportService service;

  setUp(() {
    repo = _FakeRepo();
    service = ChordProImportService(
      songLibraryService: SongLibraryService(repo, repo),
      catalogReadRepository: repo,
      normalizer: ChordproNormalizer(),
      parser: ChordproParser(),
    );
  });

  group('analyse', () {
    test('valid file with title directive → ImportSuccess', () async {
      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(
            filename: 'amazing_grace.cho',
            source: '{title: Amazing Grace}\n[G]Amazing grace',
          ),
        ],
      );

      expect(result.successes, hasLength(1));
      expect(result.successes.single.title, 'Amazing Grace');
      expect(result.duplicates, isEmpty);
      expect(result.errors, isEmpty);
    });

    test(
      'file without title directive → uses filename stem as title',
      () async {
        final result = await service.analyse(
          context: _context,
          files: const [
            ImportFileInput(filename: 'my_song.cho', source: '[G]Hello world'),
          ],
        );

        expect(result.successes, hasLength(1));
        expect(result.successes.single.title, 'my_song');
      },
    );

    test(
      'title matches existing song (case-insensitive) → ImportDuplicate',
      () async {
        repo.songs = [const SongSummary(id: 'song-1', title: 'Amazing Grace')];

        final result = await service.analyse(
          context: _context,
          files: const [
            ImportFileInput(
              filename: 'ag.cho',
              source: '{title: amazing grace}\n[G]Amazing grace',
            ),
          ],
        );

        expect(result.duplicates, hasLength(1));
        expect(result.duplicates.single.existingSongId, 'song-1');
        expect(result.duplicates.single.incomingTitle, 'amazing grace');
        expect(result.successes, isEmpty);
      },
    );

    test('empty file → ImportError', () async {
      final result = await service.analyse(
        context: _context,
        files: const [ImportFileInput(filename: 'empty.cho', source: '')],
      );

      expect(result.errors, hasLength(1));
      expect(result.errors.single.filename, 'empty.cho');
    });

    test('bulk: 1 success + 1 duplicate + 1 error → correct counts', () async {
      repo.songs = [const SongSummary(id: 'x', title: 'Existing Song')];

      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(
            filename: 'new.cho',
            source: '{title: New Song}\n[C]Hello',
          ),
          ImportFileInput(
            filename: 'existing.cho',
            source: '{title: Existing Song}\n[G]World',
          ),
          ImportFileInput(filename: 'empty.cho', source: ''),
        ],
      );

      expect(result.successes, hasLength(1));
      expect(result.duplicates, hasLength(1));
      expect(result.errors, hasLength(1));
    });
  });

  group('commitImport', () {
    test('overwrite resolution → calls updateSong', () async {
      repo.songs = [const SongSummary(id: 'song-1', title: 'Amazing Grace')];

      const duplicate = ImportDuplicate(
        filename: 'ag.cho',
        incomingSource: '{title: Amazing Grace}\n[G]New version',
        incomingTitle: 'Amazing Grace',
        existingSongId: 'song-1',
        existingTitle: 'Amazing Grace',
      );

      await service.commitImport(
        context: _context,
        successes: const [],
        resolvedDuplicates: [
          const ResolvedDuplicate(
            duplicate: duplicate,
            resolution: DuplicateResolution.overwrite,
          ),
        ],
      );

      expect(repo.updatedSongIds, contains('song-1'));
    });

    test('skip resolution → does NOT call updateSong', () async {
      repo.songs = [const SongSummary(id: 'song-1', title: 'Amazing Grace')];

      const duplicate = ImportDuplicate(
        filename: 'ag.cho',
        incomingSource: '{title: Amazing Grace}\n[G]New version',
        incomingTitle: 'Amazing Grace',
        existingSongId: 'song-1',
        existingTitle: 'Amazing Grace',
      );

      await service.commitImport(
        context: _context,
        successes: const [],
        resolvedDuplicates: [
          const ResolvedDuplicate(
            duplicate: duplicate,
            resolution: DuplicateResolution.skip,
          ),
        ],
      );

      expect(repo.updatedSongIds, isEmpty);
    });

    test('success → calls createSong', () async {
      await service.commitImport(
        context: _context,
        successes: const [
          ImportSuccess(
            title: 'New Song',
            source: '{title: New Song}\n[C]Hi',
            filename: 'new.cho',
          ),
        ],
        resolvedDuplicates: const [],
      );

      expect(repo.createdTitles, contains('New Song'));
    });
  });
}

class _FakeRepo implements SongCatalogReadRepository, SongMutationStore {
  List<SongSummary> songs = [];
  final List<String> createdTitles = [];
  final List<String> updatedSongIds = [];

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async => songs;

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => const SongSource(id: 'x', source: '');

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => songs.where((s) => s.id == songId).firstOrNull;

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async => null;

  final List<String> allocatedSlugs = [];
  bool rejectFirstUpsertWithSlugConflict = false;
  final _upserted = <SongMutationRecord>[];

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async {
    if (allocatedSlugs.isNotEmpty) {
      return allocatedSlugs.removeAt(0);
    }
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    if (rejectFirstUpsertWithSlugConflict) {
      rejectFirstUpsertWithSlugConflict = false;
      throw const LocalSongSlugConflictException();
    }
    _upserted.add(record);
    if (record.syncStatus == SongSyncStatus.pendingCreate) {
      createdTitles.add(record.title);
    } else if (record.syncStatus == SongSyncStatus.pendingUpdate) {
      updatedSongIds.add(record.id);
    }
  }

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final song = songs.where((s) => s.id == songId).firstOrNull;
    if (song == null) return null;
    return SongMutationRecord(
      id: songId,
      organizationId: organizationId,
      slug: songId,
      title: song.title,
      chordproSource: '',
      version: 1,
      baseVersion: null,
      syncStatus: SongSyncStatus.synced,
    );
  }

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => [];

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => [];

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
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) async => true;

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;
}
