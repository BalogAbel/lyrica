import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';

/// The whole song catalog of one organization: every summary and its source,
/// read in one pass, so they describe the same versions.
final class SongCatalogPayload {
  const SongCatalogPayload({required this.summaries, required this.sources});

  final List<SongSummary> summaries;
  final List<SongSource> sources;
}

abstract interface class SongCatalogRemoteRepository {
  /// Reads every song of [organizationId] (summaries and sources) as one
  /// keyset-paged stream. Throws on any failure; never returns a partial
  /// catalog. [shouldContinue] is checked between pages; when it returns false
  /// the read throws `PagedReadAbortedException`.
  Future<SongCatalogPayload> fetchCatalog({
    required String organizationId,
    bool Function()? shouldContinue,
  });
}
