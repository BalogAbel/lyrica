import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/song_library_service.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';

typedef SongLibraryDiagnosticLogger = void Function(ParseDiagnostic diagnostic);

final songLibraryRepositoryProvider = Provider<SongRepository>((ref) {
  return ref.watch(supabaseSongRepositoryProvider);
});

final supabaseSongRepositoryProvider = Provider<SupabaseSongRepository>((ref) {
  return SupabaseSongRepository(ref.watch(supabaseClientProvider));
});

final songLibraryParserProvider = Provider<ChordproParser>((ref) {
  return ChordproParser();
});

final songLibraryDiagnosticLoggerProvider =
    Provider<SongLibraryDiagnosticLogger>((ref) {
      return (diagnostic) {
        final line = diagnostic.line.lineNumber;
        final column = diagnostic.line.columnNumber;
        final location = column == null ? 'line $line' : 'line $line:$column';
        final context = diagnostic.context == null
            ? ''
            : ' | context: ${diagnostic.context}';

        debugPrint(
          '[ChordPro ${diagnostic.severity.name}] ${diagnostic.message} at '
          '$location$context',
        );
      };
    });

final songLibraryTransposerProvider = Provider<ChordTransposer>((ref) {
  return const ChordTransposer();
});

final songLibraryServiceProvider = Provider<SongLibraryService>((ref) {
  return SongLibraryService(ref.watch(songLibraryRepositoryProvider));
});

final songLibraryListProvider = FutureProvider<List<SongSummary>>((ref) {
  return ref.watch(songLibraryServiceProvider).listSongs();
});

final songLibraryReaderProvider =
    FutureProvider.family<SongReaderResult, String>((ref, songId) async {
      final service = ref.watch(songLibraryServiceProvider);
      final parser = ref.watch(songLibraryParserProvider);
      final logDiagnostic = ref.watch(songLibraryDiagnosticLoggerProvider);

      final source = await service.getSongSource(songId);
      final song = parser.parse(source.source);
      for (final diagnostic in song.diagnostics) {
        logDiagnostic(diagnostic);
      }

      return SongReaderResult(song: song);
    });
