import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_remote_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/shared/keyset_paging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SongCatalogPageFetcher =
    Future<List<Map<String, dynamic>>> Function({
      required String organizationId,
      required String? after,
      required int limit,
    });

class SupabaseSongRepository implements SongCatalogRemoteRepository {
  SupabaseSongRepository(
    SupabaseClient client, {
    @visibleForTesting int catalogPageSize = 100,
  }) : this.testing(
         catalogPageSize: catalogPageSize,
         fetchCatalogPage:
             ({
               required String organizationId,
               required String? after,
               required int limit,
             }) async {
               var query = client
                   .from('songs')
                   .select('id, slug, title, version, chordpro_source')
                   .eq('organization_id', organizationId);
               if (after != null) {
                 query = query.gt('id', after);
               }
               final rows = await query
                   .order('id', ascending: true)
                   .limit(limit);
               return List<Map<String, dynamic>>.from(rows);
             },
       );

  @visibleForTesting
  const SupabaseSongRepository.testing({
    required this._fetchCatalogPage,
    this._catalogPageSize = 100,
  });

  final SongCatalogPageFetcher _fetchCatalogPage;
  final int _catalogPageSize;

  @override
  Future<SongCatalogPayload> fetchCatalog({
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {
    final rows = await readAllKeysetPages<Map<String, dynamic>, String>(
      fetchPage: ({required after, required limit}) => _fetchCatalogPage(
        organizationId: organizationId,
        after: after,
        limit: limit,
      ),
      keyOf: (row) => row['id'] as String,
      compareKeys: compareUuidKeys,
      pageSize: _catalogPageSize,
      shouldContinue: shouldContinue,
      stream: 'songs',
    );

    final entries =
        [
          for (final row in rows)
            (
              summary: SongSummary(
                id: row['id'] as String,
                slug: row['slug'] as String? ?? row['id'] as String,
                title: row['title'] as String,
                version: (row['version'] as num?)?.toInt() ?? 1,
              ),
              source: _catalogSource(row),
            ),
        ]..sort((a, b) {
          final byTitle = a.summary.title.compareTo(b.summary.title);
          return byTitle != 0 ? byTitle : a.summary.id.compareTo(b.summary.id);
        });

    return SongCatalogPayload(
      summaries: [for (final entry in entries) entry.summary],
      sources: [for (final entry in entries) entry.source],
    );
  }

  SongSource _catalogSource(Map<String, dynamic> row) {
    final source = row['chordpro_source'];
    if (source is! String) {
      throw StateError('Catalog row has no chordpro_source string');
    }
    return SongSource(id: row['id'] as String, source: source);
  }
}
