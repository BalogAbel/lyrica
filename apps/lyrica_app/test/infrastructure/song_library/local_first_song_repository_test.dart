import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';

void main() {
  group('LocalFirstSongRepository', () {
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;
    late LocalFirstSongRepository repository;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
      repository = LocalFirstSongRepository(store);
    });

    tearDown(() async {
      await database.close();
    });

    test('lists songs from the active cached snapshot', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      expect(
        await repository.listSongs(userId: 'user-1', organizationId: 'org-1'),
        const [SongSummary(id: 'song-1', title: 'Alpha')],
      );
    });

    test('reads raw song source from the active cached snapshot', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      final source = await repository.getSongSource(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );

      expect(source.id, 'song-1');
      expect(source.source, '{title: Alpha}');
    });

    test('throws when a song is not in the active snapshot', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      await expectLater(
        () => repository.getSongSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-2',
        ),
        throwsA(isA<SongNotFoundException>()),
      );
    });

    test(
      'drops the previous organization snapshot when a new one becomes current',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 12),
        );
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-2',
          summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
          sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 13),
        );

        expect(
          await repository.listSongs(userId: 'user-1', organizationId: 'org-1'),
          isEmpty,
        );
        expect(
          await repository.listSongs(userId: 'user-1', organizationId: 'org-2'),
          const [SongSummary(id: 'song-2', title: 'Beta')],
        );
      },
    );
  });
}
