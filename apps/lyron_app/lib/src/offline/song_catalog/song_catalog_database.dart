import 'package:drift/drift.dart';

import 'song_catalog_database_connection.dart';
import 'song_catalog_tables.dart';

part 'song_catalog_database.g.dart';

@DriftDatabase(
  tables: [
    CachedCatalogSnapshots,
    CachedCatalogSummaries,
    CachedCatalogSources,
    CachedCatalogSongMutations,
  ],
)
class SongCatalogDatabase extends _$SongCatalogDatabase {
  SongCatalogDatabase._(super.connection);

  factory SongCatalogDatabase.connect(QueryExecutor executor) {
    return SongCatalogDatabase._(executor);
  }

  factory SongCatalogDatabase.local() {
    return SongCatalogDatabase._(openSongCatalogConnection());
  }

  factory SongCatalogDatabase.inMemory() {
    return SongCatalogDatabase._(openInMemorySongCatalogConnection());
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    // schemaVersion 2 was the initial shipped schema; no historical column
    // delta exists. This explicit onUpgrade is the forward-safe seam for
    // future bumps and documents the migration contract (LF-T7).
    onUpgrade: (m, from, to) async {
      // No historical upgrades yet. Future column additions go here.
    },
  );

  @override
  int get schemaVersion => 2;
}
