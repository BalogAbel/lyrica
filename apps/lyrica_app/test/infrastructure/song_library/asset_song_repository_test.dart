import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/infrastructure/song_library/asset_song_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lists the mock song catalog from assets', () async {
    final repository = AssetSongRepository();

    final songs = await repository.listSongs();

    expect(songs, hasLength(3));
    expect(songs.map((song) => song.title), contains('Egy út'));
  });

  test('loads raw source for a mock song by id', () async {
    final repository = AssetSongRepository();

    final source = await repository.getSongSource('egy_ut');

    expect(source.source, contains('{title:Egy út}'));
  });
}
