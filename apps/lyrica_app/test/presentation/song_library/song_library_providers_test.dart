import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves the song library provider graph end to end', () async {
    final authController = AppAuthController(_SignedInAuthRepository());
    final repository = SupabaseSongRepository.testing(
      listSongsRows: () async => [
        {'id': 'song-1', 'title': 'Egy út'},
      ],
      getSongRow: (id) async => {
        'id': id,
        'chordpro_source': '{title:Egy út}\n',
      },
    );
    await authController.restoreSession();
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWithValue(authController),
        appAuthListenableProvider.overrideWithValue(authController),
        supabaseSongRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(authController.dispose);

    expect(container.read(songLibraryRepositoryProvider), same(repository));
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
      songLibraryReaderProvider('song-1').future,
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

  test(
    'keeps the authenticated slice on the Supabase repository boundary',
    () async {
      final authController = AppAuthController(_SignedOutAuthRepository());
      final repository = SupabaseSongRepository.testing(
        listSongsRows: () async => const [],
        getSongRow: (id) async => null,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          appAuthListenableProvider.overrideWithValue(authController),
          supabaseSongRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(authController.dispose);

      expect(container.read(songLibraryRepositoryProvider), same(repository));
    },
  );
}

class _StubSongRepository implements SongRepository {
  int getSongSourceCalls = 0;

  @override
  Future<List<SongSummary>> listSongs() async => const [];

  @override
  Future<SongSource> getSongSource(String songId) async {
    getSongSourceCalls += 1;
    return const SongSource(id: 'stub', source: 'source');
  }
}

class _StubChordproParser extends ChordproParser {
  _StubChordproParser(this._result);

  final ParsedSong _result;

  @override
  ParsedSong parse(String source) => _result;
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async {
    return const AppAuthSession(userId: 'user-1', email: 'demo@lyrica.local');
  }

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}

class _SignedOutAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}
