import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';

void main() {
  test('returns song summaries from the repository', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository);

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
    final service = SongLibraryService(repository);

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
}

class _FakeSongRepository implements SongCatalogReadRepository {
  String? requestedSongId;

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
}
