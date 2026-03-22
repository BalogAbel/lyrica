import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';

abstract interface class SongRepository {
  Future<List<SongSummary>> listSongs();

  Future<SongSource> getSongSource(String id);
}
