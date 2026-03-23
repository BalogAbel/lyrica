import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

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

  test('logs parser diagnostics when loading a song reader result', () async {
    final loggedDiagnostics = <ParseDiagnostic>[];
    final container = ProviderContainer(
      overrides: [
        songLibraryRepositoryProvider.overrideWithValue(_StubSongRepository()),
        songLibraryParserProvider.overrideWithValue(
          _StubChordproParser(
            ParsedSong(
              title: 'Logged Song',
              sections: const [],
              diagnostics: [
                ParseDiagnostic(
                  severity: ParseDiagnosticSeverity.warning,
                  message: 'Unsupported directive',
                  line: const ParseDiagnosticLineMetadata(
                    lineNumber: 4,
                    columnNumber: 1,
                  ),
                  context: '{unknown:test}',
                ),
              ],
            ),
          ),
        ),
        songLibraryDiagnosticLoggerProvider.overrideWithValue(
          (diagnostic) => loggedDiagnostics.add(diagnostic),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      songLibraryReaderProvider('stub').future,
    );

    expect(result.song.title, 'Logged Song');
    expect(loggedDiagnostics, hasLength(1));
    expect(loggedDiagnostics.single.message, 'Unsupported directive');
    expect(loggedDiagnostics.single.context, '{unknown:test}');
  });
}

class _StubSongRepository implements SongRepository {
  @override
  Future<List<SongSummary>> listSongs() async => const [];

  @override
  Future<SongSource> getSongSource(String songId) async {
    return const SongSource(id: 'stub', source: 'source');
  }
}

class _StubChordproParser extends ChordproParser {
  _StubChordproParser(this._result);

  final ParsedSong _result;

  @override
  ParsedSong parse(String source) => _result;
}
