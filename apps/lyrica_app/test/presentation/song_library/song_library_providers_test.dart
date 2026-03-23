import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chord_transposer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves the song library provider graph end to end', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(songLibraryRepositoryProvider), isNotNull);
    expect(container.read(songLibraryParserProvider), isNotNull);
    expect(
      container.read(songLibraryTransposerProvider),
      isA<ChordTransposer>(),
    );
    expect(container.read(songLibraryServiceProvider), isNotNull);

    final songs = await container.read(songLibraryListProvider.future);
    expect(songs, isNotEmpty);
    expect(songs.first, isA<SongSummary>());

    final readerResult = await container.read(
      songLibraryReaderProvider('egy_ut').future,
    );

    expect(readerResult, isA<SongReaderResult>());
    expect(readerResult.song.title, 'Egy út');
  });
}
