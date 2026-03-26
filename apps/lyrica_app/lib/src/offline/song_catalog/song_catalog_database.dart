import 'package:drift/drift.dart';

import 'song_catalog_database_connection.dart';
import 'song_catalog_tables.dart';

part 'song_catalog_database.g.dart';

@DriftDatabase(
  tables: [
    CachedCatalogSnapshots,
    CachedCatalogSummaries,
    CachedCatalogSources,
  ],
)
class SongCatalogDatabase extends _$SongCatalogDatabase {
  SongCatalogDatabase._(super.connection);

  factory SongCatalogDatabase.local() {
    return SongCatalogDatabase._(openSongCatalogConnection());
  }

  factory SongCatalogDatabase.inMemory() {
    return SongCatalogDatabase._(openInMemorySongCatalogConnection());
  }

  @override
  int get schemaVersion => 1;
}
