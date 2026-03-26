import 'package:drift/drift.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';

abstract interface class SongCatalogStore {
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  });

  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  });

  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<String?> readLatestCachedOrganizationId({required String userId});

  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  });
}

class DriftSongCatalogStore implements SongCatalogStore {
  const DriftSongCatalogStore(this._database);

  final SongCatalogDatabase _database;

  @override
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  }) async {
    _validateSnapshot(summaries: summaries, sources: sources);

    await _database.transaction(() async {
      final currentSnapshot =
          await (_database.select(_database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .getSingleOrNull();

      final nextSnapshotVersion = (currentSnapshot?.snapshotVersion ?? 0) + 1;

      await _deleteUserCatalogs(userId: userId);

      await _database
          .into(_database.cachedCatalogSnapshots)
          .insertOnConflictUpdate(
            CachedCatalogSnapshotsCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: nextSnapshotVersion,
              refreshedAt: refreshedAt,
            ),
          );

      await _database.batch((batch) {
        batch.insertAll(
          _database.cachedCatalogSummaries,
          summaries
              .map(
                (summary) => CachedCatalogSummariesCompanion.insert(
                  userId: userId,
                  organizationId: organizationId,
                  snapshotVersion: nextSnapshotVersion,
                  songId: summary.id,
                  title: summary.title,
                ),
              )
              .toList(growable: false),
        );
        batch.insertAll(
          _database.cachedCatalogSources,
          sources
              .map(
                (source) => CachedCatalogSourcesCompanion.insert(
                  userId: userId,
                  organizationId: organizationId,
                  snapshotVersion: nextSnapshotVersion,
                  songId: source.id,
                  source: source.source,
                ),
              )
              .toList(growable: false),
        );
      });
    });
  }

  @override
  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  }) async {
    final snapshot = await _readSnapshot(
      userId: userId,
      organizationId: organizationId,
    );
    if (snapshot == null) {
      return const [];
    }

    final rows =
        await (_database.select(_database.cachedCatalogSummaries)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(snapshot.snapshotVersion),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.title)]))
            .get();

    return rows
        .map((row) => SongSummary(id: row.songId, title: row.title))
        .toList(growable: false);
  }

  @override
  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final snapshot = await _readSnapshot(
      userId: userId,
      organizationId: organizationId,
    );
    if (snapshot == null) {
      return null;
    }

    final row =
        await (_database.select(_database.cachedCatalogSources)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(snapshot.snapshotVersion) &
                  table.songId.equals(songId),
            ))
            .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return SongSource(id: row.songId, source: row.source);
  }

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async {
    final row =
        await (_database.select(_database.cachedCatalogSnapshots)
              ..where((table) => table.userId.equals(userId))
              ..orderBy([(table) => OrderingTerm.desc(table.refreshedAt)])
              ..limit(1))
            .getSingleOrNull();

    return row?.organizationId;
  }

  @override
  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  }) async {
    await _database.transaction(() async {
      await _deleteCatalogRows(userId: userId, organizationId: organizationId);
      await (_database.delete(_database.cachedCatalogSnapshots)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
    });
  }

  Future<CachedCatalogSnapshot?> _readSnapshot({
    required String userId,
    required String organizationId,
  }) {
    return (_database.select(_database.cachedCatalogSnapshots)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId),
        ))
        .getSingleOrNull();
  }

  Future<void> _deleteCatalogRows({
    required String userId,
    required String organizationId,
  }) async {
    await (_database.delete(_database.cachedCatalogSummaries)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId),
        ))
        .go();
    await (_database.delete(_database.cachedCatalogSources)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId),
        ))
        .go();
  }

  Future<void> _deleteUserCatalogs({required String userId}) async {
    await (_database.delete(
      _database.cachedCatalogSummaries,
    )..where((table) => table.userId.equals(userId))).go();
    await (_database.delete(
      _database.cachedCatalogSources,
    )..where((table) => table.userId.equals(userId))).go();
    await (_database.delete(
      _database.cachedCatalogSnapshots,
    )..where((table) => table.userId.equals(userId))).go();
  }

  void _validateSnapshot({
    required List<SongSummary> summaries,
    required List<SongSource> sources,
  }) {
    final summaryIds = summaries.map((summary) => summary.id).toSet();
    final sourceIds = sources.map((source) => source.id).toSet();
    if (summaryIds.length != summaries.length ||
        sourceIds.length != sources.length ||
        summaryIds.length != sourceIds.length ||
        !summaryIds.containsAll(sourceIds)) {
      throw ArgumentError(
        'Summaries and sources must describe the same unique song IDs.',
      );
    }
  }
}
