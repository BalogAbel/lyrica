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
    // delta exists before this. This explicit onUpgrade is the forward-safe
    // seam for future bumps and documents the migration contract (LF-T7).
    onUpgrade: (m, from, to) async {
      if (from < 3) {
        // D1 (docs/specs/2026-08-05-sync-snapshot-identity.md): every
        // pre-migration row predates the concept of a local revision, so it
        // has no sync attempt in flight to distinguish from -- 1 is a sane
        // starting value, matching what a freshly-inserted row gets.
        await m.addColumn(
          cachedCatalogSongMutations,
          cachedCatalogSongMutations.localRevision,
        );
      }
      if (from < 4) {
        // D4 (docs/specs/2026-08-19-local-data-durability-contract.md,
        // ADR-035 Task 3.1): every pre-migration snapshot row predates the
        // pending-empty-confirmation marker, so it has no empty resolution
        // in flight to distinguish from -- nullable, defaulting to null on
        // upgrade, is the correct starting state (the same as a freshly
        // inserted row).
        await m.addColumn(
          cachedCatalogSnapshots,
          cachedCatalogSnapshots.pendingEmptyConfirmationAt,
        );
      }
      if (from < 5) {
        // D6 (docs/specs/2026-08-19-local-data-durability-contract.md,
        // ADR-035 Task 3.4): every pre-migration snapshot row predates the
        // concept of proactive-budget source eviction, so it has no
        // eviction in flight to distinguish from -- nullable, defaulting to
        // null on upgrade, is the correct starting state (the same as a
        // freshly inserted row).
        await m.addColumn(
          cachedCatalogSnapshots,
          cachedCatalogSnapshots.sourcesEvictedAt,
        );
      }
    },
  );

  @override
  int get schemaVersion => 5;
}
