import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/song_library_service.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';

void main() {
  test('returns song summaries from the repository', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository);

    final songs = await service.listSongs();

    expect(songs, hasLength(1));
    expect(songs.single.id, 'egy_ut');
    expect(songs.single.title, 'Egy út');
  });

  test('returns raw song source from the repository', () async {
    final repository = _FakeSongRepository();
    final service = SongLibraryService(repository);

    final source = await service.getSongSource('egy_ut');

    expect(source.source, contains('{title:Egy út}'));
  });
}

class _FakeSongRepository implements SongRepository {
  @override
  Future<List<SongSummary>> listSongs() async {
    return const [
      SongSummary(id: 'egy_ut', title: 'Egy út'),
    ];
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    return const SongSource(
      id: 'egy_ut',
      source: '{title:Egy út}\n',
    );
  }
}
