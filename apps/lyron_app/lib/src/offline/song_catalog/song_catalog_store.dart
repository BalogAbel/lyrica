import 'package:drift/drift.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

enum SongSyncStatus {
  pendingCreate,
  pendingUpdate,
  pendingDelete,
  synced,
  conflict,
}

extension SongSyncStatusX on SongSyncStatus {
  String get value => switch (this) {
    SongSyncStatus.pendingCreate => 'pending_create',
    SongSyncStatus.pendingUpdate => 'pending_update',
    SongSyncStatus.pendingDelete => 'pending_delete',
    SongSyncStatus.synced => 'synced',
    SongSyncStatus.conflict => 'conflict',
  };
}

SongSyncStatus _songSyncStatusFromValue(String value) {
  return switch (value) {
    'pending_create' => SongSyncStatus.pendingCreate,
    'pending_update' => SongSyncStatus.pendingUpdate,
    'pending_delete' => SongSyncStatus.pendingDelete,
    'synced' => SongSyncStatus.synced,
    'conflict' => SongSyncStatus.conflict,
    _ => throw ArgumentError.value(value, 'value', 'Unknown song sync status'),
  };
}

class SongCatalogMutationDraft {
  const SongCatalogMutationDraft({
    required this.userId,
    required this.organizationId,
    required this.songId,
    required this.slug,
    required this.title,
    required this.source,
    int? version,
    required this.syncStatus,
    this.baseVersion,
    this.syncErrorContext,
  }) : version = version ?? 1;

  final String userId;
  final String organizationId;
  final String songId;
  final String slug;
  final String title;
  final String source;
  final int version;
  final SongSyncStatus syncStatus;
  final int? baseVersion;
  final String? syncErrorContext;
}

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

  Future<SongSummary?> readActiveSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  });

  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<String?> readLatestCachedOrganizationId({required String userId});

  Future<void> saveSongMutation(SongCatalogMutationDraft mutation);

  Future<bool> hasUnsyncedSongMutations({required String userId});

  Future<List<CachedCatalogSongMutation>> readSongMutations({
    required String userId,
    required String organizationId,
    List<SongSyncStatus>? syncStatuses,
  });

  Future<CachedCatalogSongMutation?> readSongMutationBySongId({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<CachedCatalogSongMutation?> readSongMutationBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  });

  Future<String> allocateAvailableSongSlug({
    required String userId,
    required String organizationId,
    required String title,
  });

  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
  });

  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<void> deleteCatalogsForUser({required String userId});

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

      await _deleteUserSnapshots(userId: userId);

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
                  slug: summary.slug,
                  title: summary.title,
                  version: summary.version,
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
    final visibleRows = await _readVisibleSongs(
      userId: userId,
      organizationId: organizationId,
    );

    final summaries = visibleRows.values
        .map(
          (row) => SongSummary(
            id: row.songId,
            title: row.title,
            slug: row.slug,
            version: row.version,
          ),
        )
        .toList(growable: false);
    summaries.sort((left, right) => left.title.compareTo(right.title));
    return summaries;
  }

  @override
  Future<SongSummary?> readActiveSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    final visibleRows = await _readVisibleSongs(
      userId: userId,
      organizationId: organizationId,
    );

    for (final row in visibleRows.values) {
      if (row.slug == songSlug) {
        return SongSummary(
          id: row.songId,
          title: row.title,
          slug: row.slug,
          version: row.version,
        );
      }
    }

    return null;
  }

  @override
  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final visibleRows = await _readVisibleSongs(
      userId: userId,
      organizationId: organizationId,
    );
    final row = visibleRows[songId];
    if (row?.source == null) {
      return null;
    }

    return SongSource(id: row!.songId, source: row.source!);
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
  Future<void> saveSongMutation(SongCatalogMutationDraft mutation) async {
    final conflictingRow = await readSongMutationBySlug(
      userId: mutation.userId,
      organizationId: mutation.organizationId,
      songSlug: mutation.slug,
    );
    if (conflictingRow != null && conflictingRow.songId != mutation.songId) {
      throw StateError(
        'Local song slug is already reserved by another mutation: ${mutation.slug}',
      );
    }

    await _database
        .into(_database.cachedCatalogSongMutations)
        .insertOnConflictUpdate(
          CachedCatalogSongMutationsCompanion.insert(
            userId: mutation.userId,
            organizationId: mutation.organizationId,
            songId: mutation.songId,
            slug: mutation.slug,
            title: mutation.title,
            source: mutation.source,
            version: mutation.version,
            syncStatus: mutation.syncStatus.value,
            baseVersion: Value(mutation.baseVersion),
            syncErrorContext: Value(mutation.syncErrorContext),
          ),
        );
  }

  @override
  Future<bool> hasUnsyncedSongMutations({required String userId}) async {
    final countExpression = _database.cachedCatalogSongMutations.songId.count();
    final query = _database.selectOnly(_database.cachedCatalogSongMutations)
      ..addColumns([countExpression])
      ..where(
        _database.cachedCatalogSongMutations.userId.equals(userId) &
            _database.cachedCatalogSongMutations.syncStatus
                .equals(SongSyncStatus.synced.value)
                .not(),
      );
    final row = await query.getSingle();
    return (row.read(countExpression) ?? 0) > 0;
  }

  @override
  Future<List<CachedCatalogSongMutation>> readSongMutations({
    required String userId,
    required String organizationId,
    List<SongSyncStatus>? syncStatuses,
  }) async {
    final query = _database.select(_database.cachedCatalogSongMutations)
      ..where(
        (table) =>
            table.userId.equals(userId) &
            table.organizationId.equals(organizationId),
      )
      ..orderBy([
        (table) => OrderingTerm.asc(table.title),
        (table) => OrderingTerm.asc(table.songId),
      ]);

    if (syncStatuses != null) {
      if (syncStatuses.isEmpty) {
        return const [];
      }

      query.where(
        (table) => table.syncStatus.isIn(
          syncStatuses.map((status) => status.value).toList(growable: false),
        ),
      );
    }

    return query.get();
  }

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySongId({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return (_database.select(_database.cachedCatalogSongMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.songId.equals(songId),
        ))
        .getSingleOrNull();
  }

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) {
    return (_database.select(_database.cachedCatalogSongMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.slug.equals(songSlug),
        ))
        .getSingleOrNull();
  }

  @override
  Future<String> allocateAvailableSongSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async {
    final baseSlug = _slugify(title);
    var candidate = baseSlug;
    var suffix = 2;

    while (await readActiveSummaryBySlug(
              userId: userId,
              organizationId: organizationId,
              songSlug: candidate,
            ) !=
            null ||
        await readSongMutationBySlug(
              userId: userId,
              organizationId: organizationId,
              songSlug: candidate,
            ) !=
            null) {
      candidate = '$baseSlug-$suffix';
      suffix += 1;
    }

    return candidate;
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(_database.cachedCatalogSongMutations)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.songId.equals(songId),
          ))
          .go();
      await (_database.delete(_database.cachedCatalogSummaries)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.songId.equals(songId),
          ))
          .go();
      await (_database.delete(_database.cachedCatalogSources)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.songId.equals(songId),
          ))
          .go();
    });
  }

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
  }) async {
    await _database.transaction(() async {
      final activeSnapshot =
          await (_database.select(_database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .getSingleOrNull();
      if (activeSnapshot == null) {
        await _database
            .into(_database.cachedCatalogSnapshots)
            .insertOnConflictUpdate(
              CachedCatalogSnapshotsCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: 1,
                refreshedAt: DateTime.now().toUtc(),
              ),
            );
      }
      final snapshotVersion = activeSnapshot?.snapshotVersion ?? 1;

      await (_database.delete(_database.cachedCatalogSongMutations)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.songId.equals(summary.id),
          ))
          .go();
      await _database
          .into(_database.cachedCatalogSummaries)
          .insertOnConflictUpdate(
            CachedCatalogSummariesCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: snapshotVersion,
              songId: summary.id,
              slug: summary.slug,
              title: summary.title,
              version: summary.version,
            ),
          );
      await _database
          .into(_database.cachedCatalogSources)
          .insertOnConflictUpdate(
            CachedCatalogSourcesCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: snapshotVersion,
              songId: source.id,
              source: source.source,
            ),
          );
    });
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    await (_database.delete(_database.cachedCatalogSongMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.songId.equals(songId),
        ))
        .go();
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

  @override
  Future<void> deleteCatalogsForUser({required String userId}) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.cachedCatalogSongMutations,
      )..where((table) => table.userId.equals(userId))).go();
      await (_database.delete(
        _database.cachedCatalogSummaries,
      )..where((table) => table.userId.equals(userId))).go();
      await (_database.delete(
        _database.cachedCatalogSources,
      )..where((table) => table.userId.equals(userId))).go();
      await (_database.delete(
        _database.cachedCatalogSnapshots,
      )..where((table) => table.userId.equals(userId))).go();
    });
  }

  Future<Map<String, _VisibleSongRow>> _readVisibleSongs({
    required String userId,
    required String organizationId,
  }) async {
    final visibleRows = <String, _VisibleSongRow>{};

    final snapshotRows =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .get();
    final snapshotSources =
        await (_database.select(_database.cachedCatalogSources)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .get();
    final snapshotSourceBySongId = {
      for (final row in snapshotSources) row.songId: row.source,
    };

    for (final row in snapshotRows) {
      _upsertVisibleRow(
        visibleRows,
        _VisibleSongRow(
          songId: row.songId,
          title: row.title,
          slug: row.slug,
          source: snapshotSourceBySongId[row.songId],
          version: row.version,
        ),
      );
    }

    final mutationRows =
        await (_database.select(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .get();

    for (final row in mutationRows) {
      final status = _songSyncStatusFromValue(row.syncStatus);
      if (status == SongSyncStatus.pendingDelete) {
        _removeVisibleRowsBySlug(
          visibleRows,
          slug: row.slug,
          exceptSongId: row.songId,
        );
        visibleRows.remove(row.songId);
        continue;
      }
      if (status == SongSyncStatus.synced) {
        continue;
      }
      _upsertVisibleRow(
        visibleRows,
        _VisibleSongRow(
          songId: row.songId,
          title: row.title,
          slug: row.slug,
          source: row.source,
          version: row.version,
        ),
      );
    }

    return visibleRows;
  }

  void _upsertVisibleRow(
    Map<String, _VisibleSongRow> visibleRows,
    _VisibleSongRow row,
  ) {
    _removeVisibleRowsBySlug(
      visibleRows,
      slug: row.slug,
      exceptSongId: row.songId,
    );
    visibleRows[row.songId] = row;
  }

  void _removeVisibleRowsBySlug(
    Map<String, _VisibleSongRow> visibleRows, {
    required String slug,
    String? exceptSongId,
  }) {
    final conflictingSongIds = visibleRows.entries
        .where((entry) => entry.value.slug == slug && entry.key != exceptSongId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final songId in conflictingSongIds) {
      visibleRows.remove(songId);
    }
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
    await (_database.delete(_database.cachedCatalogSongMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId),
        ))
        .go();
  }

  Future<void> _deleteUserSnapshots({required String userId}) async {
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

  String _slugify(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return normalized.isEmpty ? 'song' : normalized;
  }
}

class _VisibleSongRow {
  const _VisibleSongRow({
    required this.songId,
    required this.title,
    required this.slug,
    required this.source,
    required this.version,
  });

  final String songId;
  final String title;
  final String slug;
  final String? source;
  final int version;
}
