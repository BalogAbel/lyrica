import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/infrastructure/song_library/local_first_song_repository.dart';

typedef SongLibraryDiagnosticLogger = void Function(ParseDiagnostic diagnostic);

final localFirstSongRepositoryProvider = Provider<LocalFirstSongRepository>((
  ref,
) {
  return LocalFirstSongRepository(ref.watch(songCatalogStoreProvider));
});

final songLibraryRepositoryProvider = Provider<SongCatalogReadRepository>((
  ref,
) {
  return ref.watch(localFirstSongRepositoryProvider);
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

final songLibraryListProvider = FutureProvider.autoDispose<List<SongSummary>>((
  ref,
) {
  final snapshotState = ref.watch(catalogSnapshotStateProvider);
  final context = snapshotState.context;
  if (context == null) {
    return const [];
  }

  return ref.watch(songLibraryServiceProvider).listSongs(context: context);
});

final songLibrarySongBySlugProvider = FutureProvider.autoDispose
    .family<SongSummary?, String>((ref, songSlug) async {
      final context = ref.watch(activeCatalogContextProvider);
      if (context == null) {
        return null;
      }

      return ref
          .watch(songLibraryServiceProvider)
          .getSongSummaryBySlug(context: context, songSlug: songSlug);
    });

final songLibrarySongByIdProvider = FutureProvider.autoDispose
    .family<SongSummary?, String>((ref, songId) async {
      final songs = await ref.watch(songLibraryListProvider.future);
      for (final song in songs) {
        if (song.id == songId) {
          return song;
        }
      }

      return null;
    });

final songLibraryReaderProvider = FutureProvider.autoDispose
    .family<SongReaderResult, String>((ref, songId) async {
      final context = ref.watch(activeCatalogContextProvider);
      if (context == null) {
        throw SongNotFoundException(songId);
      }

      final service = ref.watch(songLibraryServiceProvider);
      final parser = ref.watch(songLibraryParserProvider);
      final logDiagnostic = ref.watch(songLibraryDiagnosticLoggerProvider);

      final source = await service.getSongSource(
        context: context,
        songId: songId,
      );
      final song = parser.parse(source.source);
      for (final diagnostic in song.diagnostics) {
        logDiagnostic(diagnostic);
      }

      return SongReaderResult(song: song);
    });
