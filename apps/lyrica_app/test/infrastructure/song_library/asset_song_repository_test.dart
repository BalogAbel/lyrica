import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/infrastructure/song_library/asset_song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lists the mock song catalog from assets', () async {
    final repository = AssetSongRepository();

    final songs = await repository.listSongs();

    expect(
      songs,
      const [
        SongSummary(id: 'a_forrasnal', title: 'A forrásnál'),
        SongSummary(
          id: 'a_mi_istenunk',
          title: 'A mi Istenünk (Leborulok előtted)',
        ),
        SongSummary(id: 'egy_ut', title: 'Egy út'),
      ],
    );
  });

  test('loads raw source for each listed song by id', () async {
    final repository = AssetSongRepository();
    final songs = await repository.listSongs();

    for (final song in songs) {
      final source = await repository.getSongSource(song.id);

      expect(source.id, song.id);
      expect(source.source, isNotEmpty);
    }
  });

  test('throws a domain error for unknown song ids', () async {
    final repository = AssetSongRepository();

    expect(
      () => repository.getSongSource('missing'),
      throwsA(isA<SongNotFoundException>()),
    );
  });
}
