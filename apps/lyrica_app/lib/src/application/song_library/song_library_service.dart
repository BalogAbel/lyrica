import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyrica_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';

class SongLibraryService {
  const SongLibraryService(this._repository);

  final SongCatalogReadRepository _repository;

  Future<List<SongSummary>> listSongs({required ActiveCatalogContext context}) {
    return _repository.listSongs(
      userId: context.userId,
      organizationId: context.organizationId,
    );
  }

  Future<SongSource> getSongSource({
    required ActiveCatalogContext context,
    required String songId,
  }) {
    return _repository.getSongSource(
      userId: context.userId,
      organizationId: context.organizationId,
      songId: songId,
    );
  }
}
