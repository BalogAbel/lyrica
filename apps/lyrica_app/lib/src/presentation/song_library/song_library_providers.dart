import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/song_library/song_library_service.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/asset_song_repository.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

final songLibraryRepositoryProvider = Provider<SongRepository>((ref) {
  return AssetSongRepository();
});

final songLibraryParserProvider = Provider<ChordproParser>((ref) {
  return ChordproParser();
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

  final source = await service.getSongSource(songId);
  final song = parser.parse(source.source);

  return SongReaderResult(song: song);
});
