import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

class LocalFirstSongRepository implements SongCatalogReadRepository {
  const LocalFirstSongRepository(this._store);

  final SongCatalogStore _store;

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) {
    return _store.readActiveSummaries(
      userId: userId,
      organizationId: organizationId,
    );
  }

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final source = await _store.readActiveSource(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (source == null) {
      throw SongNotFoundException(songId);
    }

    return source;
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) {
    return _store.readActiveSummaryBySlug(
      userId: userId,
      organizationId: organizationId,
      songSlug: songSlug,
    );
  }
}
