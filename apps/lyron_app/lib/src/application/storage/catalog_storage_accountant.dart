import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart'
    show kLocalStorageRowOverheadBytes;
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// Measures the song catalog database's footprint from row content, on the
/// same content-derived basis as [PlanningStorageAccountant].
class CatalogStorageAccountant {
  const CatalogStorageAccountant(this._database);

  final SongCatalogDatabase _database;

  /// Total catalog footprint, including pending song mutations. Pending song
  /// mutations count towards pressure even though they are never evictable.
  Future<int> measureCatalogBytes() async {
    final row = await _database
        .customSelect(
          'SELECT ('
          '(SELECT COALESCE(SUM(length(song_id) + length(slug) + '
          'length(title) + $kLocalStorageRowOverheadBytes), 0) '
          'FROM cached_catalog_summaries) + '
          '(SELECT COALESCE(SUM(length(song_id) + length(source) + '
          '$kLocalStorageRowOverheadBytes), 0) '
          'FROM cached_catalog_sources) + '
          '(SELECT COALESCE(SUM(length(song_id) + length(slug) + '
          'length(title) + length(source) + '
          "length(COALESCE(sync_error_context, '')) + "
          '$kLocalStorageRowOverheadBytes), 0) '
          'FROM cached_catalog_song_mutations)'
          ') AS byte_estimate',
          readsFrom: {
            _database.cachedCatalogSummaries,
            _database.cachedCatalogSources,
            _database.cachedCatalogSongMutations,
          },
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }

  /// Bytes currently eligible for eviction: cached sources whose song has no
  /// pending mutation.
  Future<int> measureDroppableBytes() async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(SUM(length(song_id) + length(source) + '
          '$kLocalStorageRowOverheadBytes), 0) AS byte_estimate '
          'FROM cached_catalog_sources AS s '
          'WHERE NOT EXISTS ('
          'SELECT 1 FROM cached_catalog_song_mutations AS m '
          'WHERE m.user_id = s.user_id '
          'AND m.organization_id = s.organization_id '
          'AND m.song_id = s.song_id)',
          readsFrom: {
            _database.cachedCatalogSources,
            _database.cachedCatalogSongMutations,
          },
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }
}
