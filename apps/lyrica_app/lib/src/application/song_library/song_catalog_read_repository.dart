import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';

abstract interface class SongCatalogReadRepository {
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  });

  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  });
}
