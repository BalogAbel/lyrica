import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/storage/local_storage_domain_rejection.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint_revision.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

enum SongSyncStatus {
  pendingCreate,
  pendingUpdate,
  pendingDelete,
  synced,
  conflict,

  /// D1 (`docs/specs/2026-08-06-in-flight-create-cancellation.md`): written
  /// durably to a still-local (`pendingCreate`) song's mutation row
  /// immediately BEFORE its remote create attempt, mirroring the `accepted`
  /// marker ADR-019 already writes immediately after a planning mutation's
  /// remote call. Between the write and the remote response, the create is
  /// known to be in flight.
  ///
  /// Scoped to `pendingCreate` sends only -- see
  /// `SongCatalogStore.markSongCreateSending` for why `pendingUpdate`/
  /// `pendingDelete` sends do not need an equivalent marker.
  ///
  /// Crash semantics mirror ADR-019/D1: a record left `sending` by a crash
  /// may or may not have reached the backend, so it is treated as pending
  /// and resent on the next sync pass (`DriftSongMutationStore
  /// .readPendingSongs`), not stranded forever.
  sending,

  /// D2: what a `sending` row becomes when the user deletes it while its
  /// create is still in flight -- a cancellation tombstone, kept instead of
  /// being physically collapsed (`SongLibraryService.deleteSong`'s
  /// `pendingCreate` branch, ADR-028 D10), because the create may already
  /// have reached the backend and the delete intent would otherwise have no
  /// local trace once it does. Resolved by `SongMutationSyncController` once
  /// the in-flight create's outcome is known (D3), via
  /// `SongCatalogStore.resolveCancelledSongCreate`.
  ///
  /// Deliberately hidden from every local-first read
  /// (`DriftSongCatalogStore._readVisibleSongs` and its slug-lookup
  /// siblings) and excluded from `readPendingSongs`: the user deleted this
  /// song, so it must not render as an existing or actionable song while its
  /// fate is undecided.
  cancelling,
}

class LocalSongSlugConflictException implements LocalStorageDomainRejection {
  const LocalSongSlugConflictException();

  @override
  String toString() => 'LocalSongSlugConflictException()';
}

extension SongSyncStatusX on SongSyncStatus {
  String get value => switch (this) {
    SongSyncStatus.pendingCreate => 'pending_create',
    SongSyncStatus.pendingUpdate => 'pending_update',
    SongSyncStatus.pendingDelete => 'pending_delete',
    SongSyncStatus.synced => 'synced',
    SongSyncStatus.conflict => 'conflict',
    SongSyncStatus.sending => 'sending',
    SongSyncStatus.cancelling => 'cancelling',
  };
}

SongSyncStatus _songSyncStatusFromValue(String value) {
  return switch (value) {
    'pending_create' => SongSyncStatus.pendingCreate,
    'pending_update' => SongSyncStatus.pendingUpdate,
    'pending_delete' => SongSyncStatus.pendingDelete,
    'synced' => SongSyncStatus.synced,
    'conflict' => SongSyncStatus.conflict,
    'sending' => SongSyncStatus.sending,
    'cancelling' => SongSyncStatus.cancelling,
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

  Future<SongSummary?> readActiveSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
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

  Future<bool> hasVisibleSongSlug({
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

  /// Concludes a successful sync: reconciles the cached snapshot with
  /// [summary]/[source] and drops the song's mutation row.
  ///
  /// D2 (docs/specs/2026-08-05-sync-snapshot-identity.md): when
  /// [expectedRevision] is supplied, the whole reconcile applies only if the
  /// mutation row's CURRENT `localRevision` still matches it -- gated inside
  /// the same transaction's DELETE statement, never a preceding `SELECT`
  /// compared in Dart (that would reopen the race this closes). Returns
  /// `true` if it applied, `false` if the revision had already moved (D3:
  /// not an error -- the row is left exactly as the concurrent local write
  /// left it, still pending with the newer content). Omitting
  /// [expectedRevision] always applies unconditionally.
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
    int? expectedRevision,
  });

  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  });

  /// D1 (docs/specs/2026-08-06-in-flight-create-cancellation.md): durably
  /// marks a still-local (`pendingCreate`) song's mutation row `sending`
  /// immediately before its remote create attempt -- the song/catalog
  /// mirror of the marker `PlanningMutationSyncController._run` writes
  /// before every send. Gated on [expectedRevision] via the same UPDATE
  /// statement's own WHERE clause (the D2 pattern `reconcileSyncedSong`
  /// already established above) -- never a preceding SELECT compared in
  /// Dart, which would reopen the race this closes.
  ///
  /// Deliberately scoped to `pendingCreate` rows only, unlike planning's
  /// marker (written before every mutation kind's send): a delete of an
  /// already-synced song (`pendingUpdate`/`pendingDelete`) racing its own
  /// in-flight send is already race-safe via `reconcileSyncedSong`'s
  /// existing `localRevision` gate above (D2,
  /// docs/specs/2026-08-05-sync-snapshot-identity.md) -- an unconditional
  /// overwrite plus that gate is enough, because those kinds never
  /// physically collapse the row the way ADR-028 D10 admits for a still-
  /// local create. Only a `pendingCreate` send can be raced by a physical
  /// collapse (`SongLibraryService.deleteSong`'s `pendingCreate` branch),
  /// so only that case needs a durable in-flight marker to race against.
  ///
  /// Returns the row's new `localRevision` if it applied, or `null` if the
  /// row no longer exists (D4,
  /// docs/specs/2026-08-06-in-flight-create-cancellation.md) or its
  /// revision had already moved (D3: not an error -- a local edit or
  /// delete landed on this song since the caller's snapshot).
  Future<int?> markSongCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  });

  /// D3 (docs/specs/2026-08-06-in-flight-create-cancellation.md): resolves
  /// the outcome of an in-flight `pendingCreate` song whose row may have
  /// become a D2 cancellation tombstone (`SongSyncStatus.cancelling`) while
  /// its remote create was in flight.
  ///
  /// Only acts if the row currently exists AND is a tombstone; any other
  /// state (no row, or a row whose status is something other than
  /// `cancelling`) means this call has nothing to do -- either the row was
  /// never cancelled (an ordinary local edit landed instead, already
  /// resolved by the caller's own D3 stale-revision handling on
  /// `reconcileSyncedSong`) or a previous call already resolved it -- and
  /// this is then a no-op that returns `false`. The check and the write
  /// happen inside a single storage transaction so a concurrent write
  /// cannot land in between.
  ///
  /// When [created] is `true` the create reached the backend, so the
  /// tombstone becomes a real `pendingDelete`: `baseVersion` is rebased on
  /// [acceptedVersion] (the version the backend just assigned the created
  /// row) so the delete RPC's OCC check targets content that actually
  /// exists remotely. The next sync sends it. The already-accepted remote
  /// create is never undone -- the delete is a subsequent operation, which
  /// is what the user actually asked for.
  ///
  /// When [created] is `false` the create never reached the backend, so the
  /// song never existed remotely: the tombstone is discarded outright, with
  /// no further backend call -- exactly the physical collapse a plain,
  /// not-in-flight delete would have performed (ADR-028 D10).
  ///
  /// Returns `true` if a tombstone was found and resolved, `false`
  /// otherwise.
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  });

  Future<void> deleteCatalogsForUser({required String userId});

  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  });
}

class DriftSongCatalogStore implements SongCatalogStore {
  const DriftSongCatalogStore(
    this._database, {
    LocalStorageFootprintChanged? onStorageFootprintChanged,
    LocalStorageWriteRecovery? writeRecovery,
  }) : _onStorageFootprintChanged = onStorageFootprintChanged,
       _writeRecovery = writeRecovery;

  final SongCatalogDatabase _database;
  final LocalStorageFootprintChanged? _onStorageFootprintChanged;

  /// Guards every local write that can increase stored bytes: a snapshot
  /// replacement or song-mutation save that fails at the storage layer gets
  /// one eviction-and-retry before surfacing a typed
  /// [LocalStorageWriteFailure] (LF-T4, D1). `null` in tests that construct
  /// this store directly -- production wiring always supplies it, mirroring
  /// how [_onStorageFootprintChanged] is injected.
  final LocalStorageWriteRecovery? _writeRecovery;

  Future<T> _guarded<T>(Future<T> Function() write) {
    final recovery = _writeRecovery;
    return recovery == null ? write() : recovery.guard(write);
  }

  @override
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  }) => _guarded(
    () => _replaceActiveSnapshot(
      userId: userId,
      organizationId: organizationId,
      summaries: summaries,
      sources: sources,
      refreshedAt: refreshedAt,
    ),
  );

  Future<void> _replaceActiveSnapshot({
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
    _onStorageFootprintChanged?.call();
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
    final visibleMutation = await _readVisibleMutationBySlug(
      userId: userId,
      organizationId: organizationId,
      songSlug: songSlug,
    );
    if (visibleMutation != null) {
      return _summaryFromVisibleMutation(visibleMutation);
    }

    final snapshotRow =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.slug.equals(songSlug),
            ))
            .getSingleOrNull();
    if (snapshotRow == null) {
      return null;
    }

    if (await _isSnapshotSongHidden(
      userId: userId,
      organizationId: organizationId,
      songId: snapshotRow.songId,
    )) {
      return null;
    }

    return SongSummary(
      id: snapshotRow.songId,
      title: snapshotRow.title,
      slug: snapshotRow.slug,
      version: snapshotRow.version,
    );
  }

  @override
  Future<SongSummary?> readActiveSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final visibleMutation = await _readVisibleMutationBySongId(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (visibleMutation != null) {
      return _summaryFromVisibleMutation(visibleMutation);
    }

    if (await _isSnapshotSongHidden(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    )) {
      return null;
    }

    final row =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(songId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }

    return SongSummary(
      id: row.songId,
      title: row.title,
      slug: row.slug,
      version: row.version,
    );
  }

  @override
  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final visibleMutation = await _readVisibleMutationBySongId(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (visibleMutation != null) {
      return SongSource(
        id: visibleMutation.songId,
        source: visibleMutation.source,
      );
    }

    if (await _isSnapshotSongHidden(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    )) {
      return null;
    }

    final sourceRow =
        await (_database.select(_database.cachedCatalogSources)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(songId),
            ))
            .getSingleOrNull();
    if (sourceRow == null) {
      return null;
    }

    return SongSource(id: sourceRow.songId, source: sourceRow.source);
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
  Future<void> saveSongMutation(SongCatalogMutationDraft mutation) =>
      _guarded(() => _saveSongMutation(mutation));

  Future<void> _saveSongMutation(SongCatalogMutationDraft mutation) async {
    final conflictingRow = await readSongMutationBySlug(
      userId: mutation.userId,
      organizationId: mutation.organizationId,
      songSlug: mutation.slug,
    );
    if (conflictingRow != null && conflictingRow.songId != mutation.songId) {
      throw const LocalSongSlugConflictException();
    }

    final existing = await readSongMutationBySongId(
      userId: mutation.userId,
      organizationId: mutation.organizationId,
      songId: mutation.songId,
    );
    if (existing != null && _matchesSongMutation(existing, mutation)) {
      return;
    }

    // D1 (docs/specs/2026-08-05-sync-snapshot-identity.md): every local
    // write to this row bumps localRevision, including a fold onto an
    // already-pending row (e.g. a second edit before the first ever
    // synced) -- this is the store's one write path for the mutation
    // table's content, shared by every caller of saveSongMutation. Reading
    // `existing` here (already done above, for the no-op short-circuit)
    // and computing the increment in Dart is safe: this is not a
    // conditional write racing a network round trip (unlike
    // reconcileSyncedSong, D2), it is the store's own single, ordinary
    // write for this song.
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
            localRevision: Value(
              existing == null ? 1 : existing.localRevision + 1,
            ),
          ),
        );
    _onStorageFootprintChanged?.call();
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
  Future<bool> hasVisibleSongSlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    final matchingMutation =
        await (_database.select(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.slug.equals(songSlug) &
                  table.syncStatus
                      .equals(SongSyncStatus.pendingDelete.value)
                      .not() &
                  // D2: a `cancelling` tombstone is being removed just like
                  // a `pendingDelete` row -- it must not reserve its slug
                  // either.
                  table.syncStatus
                      .equals(SongSyncStatus.cancelling.value)
                      .not(),
            ))
            .getSingleOrNull();
    if (matchingMutation != null) {
      return true;
    }

    final matchingSummary =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.slug.equals(songSlug),
            ))
            .getSingleOrNull();
    if (matchingSummary == null) {
      return false;
    }

    final deletingMutation =
        await (_database.select(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(matchingSummary.songId) &
                  table.syncStatus.equals(SongSyncStatus.pendingDelete.value),
            ))
            .getSingleOrNull();
    return deletingMutation == null;
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

    while (await _hasReservedSongSlug(
      userId: userId,
      organizationId: organizationId,
      songSlug: candidate,
    )) {
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
    final deletedRows = await _database.transaction(() async {
      var deletedRows = 0;
      deletedRows +=
          await (_database.delete(_database.cachedCatalogSongMutations)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.songId.equals(songId),
              ))
              .go();
      deletedRows +=
          await (_database.delete(_database.cachedCatalogSummaries)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.songId.equals(songId),
              ))
              .go();
      deletedRows +=
          await (_database.delete(_database.cachedCatalogSources)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.songId.equals(songId),
              ))
              .go();
      return deletedRows;
    });
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
    int? expectedRevision,
  }) => _guarded(
    () => _reconcileSyncedSong(
      userId: userId,
      organizationId: organizationId,
      summary: summary,
      source: source,
      expectedRevision: expectedRevision,
    ),
  );

  // Guarded like the other writes above: reconciling a synced song can
  // insert a brand-new summary/source row pair for a song that had no cached
  // representation before (first sync), which is exactly the growth case D1
  // exists to protect, even though it also deletes the now-resolved mutation
  // row in the same transaction.
  Future<bool> _reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
    int? expectedRevision,
  }) async {
    final result = await _database.transaction(() async {
      // D2 (docs/specs/2026-08-05-sync-snapshot-identity.md): the mutation
      // row's own DELETE, gated on `localRevision` in its WHERE clause, is
      // the sole arbiter of whether this reconcile applies at all -- not a
      // preceding SELECT compared in Dart, which would reopen the exact
      // window this closes. When `expectedRevision` is stale, the whole
      // reconcile (including the snapshot upsert below) is skipped: the
      // backend response being reconciled describes content a newer local
      // edit has already superseded, so nothing here should land.
      var deleteQuery = _database.delete(_database.cachedCatalogSongMutations)
        ..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.songId.equals(summary.id),
        );
      if (expectedRevision != null) {
        deleteQuery = _database.delete(_database.cachedCatalogSongMutations)
          ..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.songId.equals(summary.id) &
                table.localRevision.equals(expectedRevision),
          );
      }
      final deletedMutationRows = await deleteQuery.go();

      if (expectedRevision != null && deletedMutationRows == 0) {
        // D3: a local edit landed on this song during the remote round
        // trip. Not an error -- leave the row exactly as that edit left it
        // (still pending, with the newer content); the next sync sends it.
        return (applied: false, changed: false);
      }

      var changed = deletedMutationRows > 0;
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
        changed = true;
      }
      final snapshotVersion = activeSnapshot?.snapshotVersion ?? 1;

      changed =
          await _upsertSummaryRow(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: snapshotVersion,
            summary: summary,
          ) ||
          changed;
      changed =
          await _upsertSourceRow(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: snapshotVersion,
            source: source,
          ) ||
          changed;
      return (applied: true, changed: changed);
    });
    if (result.changed) {
      _onStorageFootprintChanged?.call();
    }
    return result.applied;
  }

  @override
  Future<int?> markSongCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) => _guarded(
    () => _markSongCreateSending(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
      expectedRevision: expectedRevision,
    ),
  );

  Future<int?> _markSongCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) async {
    // D1/D2 (docs/specs/2026-08-06-in-flight-create-cancellation.md): the
    // gating condition lives entirely in the WHERE clause of this single
    // UPDATE, not as a read-then-decide in Dart -- the same discipline
    // reconcileSyncedSong's D2 gate above already established. There is no
    // preceding SELECT to go stale between the check and the write.
    final newRevision = expectedRevision + 1;
    final rowsUpdated =
        await (_database.update(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(songId) &
                  table.localRevision.equals(expectedRevision),
            ))
            .write(
              CachedCatalogSongMutationsCompanion(
                syncStatus: Value(SongSyncStatus.sending.value),
                localRevision: Value(newRevision),
              ),
            );
    if (rowsUpdated == 0) {
      // D3/D4: either the row's revision had already moved (a local edit or
      // delete landed on this song since the caller's snapshot) or the row
      // is gone entirely. Both collapse to the same "did not apply" outcome
      // -- not an error either way.
      return null;
    }
    _onStorageFootprintChanged?.call();
    return newRevision;
  }

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) => _database.transaction(
    () => _resolveCancelledSongCreate(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
      created: created,
      acceptedVersion: acceptedVersion,
    ),
  );

  Future<bool> _resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) async {
    final row = await readSongMutationBySongId(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (row == null ||
        _songSyncStatusFromValue(row.syncStatus) != SongSyncStatus.cancelling) {
      // Not a tombstone -- either an ordinary local edit/delete landed on
      // this song instead (already handled by the caller's own D3
      // stale-revision skip on reconcileSyncedSong) or a previous call
      // already resolved it. Nothing to do.
      return false;
    }

    if (!created) {
      // D3: the create never reached the backend, so the song never
      // existed remotely -- discard the tombstone outright, with no
      // further backend call. Exactly the physical collapse a plain,
      // not-in-flight delete would have performed (ADR-028 D10).
      await (_database.delete(_database.cachedCatalogSongMutations)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.songId.equals(songId),
          ))
          .go();
      _onStorageFootprintChanged?.call();
      return true;
    }

    // D3: the create succeeded, so the song exists on the server -- the
    // tombstone becomes a real pendingDelete and the next sync sends it.
    // The already-accepted remote create is never undone; this is a
    // subsequent operation. baseVersion is rebased on the version the
    // backend just assigned the created row, so the delete RPC's OCC check
    // targets content that actually exists.
    await _database
        .into(_database.cachedCatalogSongMutations)
        .insertOnConflictUpdate(
          CachedCatalogSongMutationsCompanion.insert(
            userId: userId,
            organizationId: organizationId,
            songId: songId,
            slug: row.slug,
            title: row.title,
            source: row.source,
            version: row.version,
            syncStatus: SongSyncStatus.pendingDelete.value,
            baseVersion: Value(acceptedVersion ?? row.baseVersion),
            syncErrorContext: const Value(null),
            localRevision: Value(row.localRevision + 1),
          ),
        );
    _onStorageFootprintChanged?.call();
    return true;
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final deletedRows =
        await (_database.delete(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(songId),
            ))
            .go();
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  }) async {
    final deletedRows = await _database.transaction(() async {
      var deletedRows = await _deleteCatalogRows(
        userId: userId,
        organizationId: organizationId,
      );
      deletedRows +=
          await (_database.delete(_database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .go();
      return deletedRows;
    });
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> deleteCatalogsForUser({required String userId}) async {
    final deletedRows = await _database.transaction(() async {
      var deletedRows = 0;
      deletedRows += await (_database.delete(
        _database.cachedCatalogSongMutations,
      )..where((table) => table.userId.equals(userId))).go();
      deletedRows += await (_database.delete(
        _database.cachedCatalogSummaries,
      )..where((table) => table.userId.equals(userId))).go();
      deletedRows += await (_database.delete(
        _database.cachedCatalogSources,
      )..where((table) => table.userId.equals(userId))).go();
      deletedRows += await (_database.delete(
        _database.cachedCatalogSnapshots,
      )..where((table) => table.userId.equals(userId))).go();
      return deletedRows;
    });
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  bool _matchesSongMutation(
    CachedCatalogSongMutation existing,
    SongCatalogMutationDraft mutation,
  ) {
    return existing.userId == mutation.userId &&
        existing.organizationId == mutation.organizationId &&
        existing.songId == mutation.songId &&
        existing.slug == mutation.slug &&
        existing.title == mutation.title &&
        existing.source == mutation.source &&
        existing.version == mutation.version &&
        existing.syncStatus == mutation.syncStatus.value &&
        existing.baseVersion == mutation.baseVersion &&
        existing.syncErrorContext == mutation.syncErrorContext;
  }

  Future<bool> _upsertSummaryRow({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required SongSummary summary,
  }) async {
    final existing =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(summary.id),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.snapshotVersion == snapshotVersion &&
        existing.slug == summary.slug &&
        existing.title == summary.title &&
        existing.version == summary.version) {
      return false;
    }
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
    return true;
  }

  Future<bool> _upsertSourceRow({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required SongSource source,
  }) async {
    final existing =
        await (_database.select(_database.cachedCatalogSources)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(source.id),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.snapshotVersion == snapshotVersion &&
        existing.source == source.source) {
      return false;
    }
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
    return true;
  }

  Future<Map<String, _VisibleSongRow>> _readVisibleSongs({
    required String userId,
    required String organizationId,
  }) async {
    final visibleRows = <String, _VisibleSongRow>{};
    final slugOwners = <String, String>{};

    final snapshotRows =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .get();

    for (final row in snapshotRows) {
      _upsertVisibleRow(
        visibleRows,
        slugOwners,
        _VisibleSongRow(
          songId: row.songId,
          title: row.title,
          slug: row.slug,
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
      // D2: a `cancelling` tombstone is the user's delete intent for a song
      // that never (yet) existed remotely -- it must vanish from every
      // local-first read immediately, the same as a `pendingDelete` row,
      // before its create's outcome is even known (D3).
      if (status == SongSyncStatus.pendingDelete ||
          status == SongSyncStatus.cancelling) {
        _removeVisibleRowsBySlug(
          visibleRows,
          slugOwners: slugOwners,
          slug: row.slug,
          exceptSongId: row.songId,
        );
        visibleRows.remove(row.songId);
        final currentOwner = slugOwners[row.slug];
        if (currentOwner == row.songId) {
          slugOwners.remove(row.slug);
        }
        continue;
      }
      if (status == SongSyncStatus.synced) {
        continue;
      }
      _upsertVisibleRow(
        visibleRows,
        slugOwners,
        _VisibleSongRow(
          songId: row.songId,
          title: row.title,
          slug: row.slug,
          version: row.version,
        ),
      );
    }

    return visibleRows;
  }

  Future<bool> _hasReservedSongSlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    final matchingMutation = await readSongMutationBySlug(
      userId: userId,
      organizationId: organizationId,
      songSlug: songSlug,
    );
    if (matchingMutation != null) {
      return true;
    }

    return _hasVisibleSnapshotSongSlug(
      userId: userId,
      organizationId: organizationId,
      songSlug: songSlug,
    );
  }

  Future<bool> _hasVisibleSnapshotSongSlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    final matchingSummary =
        await (_database.select(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.slug.equals(songSlug),
            ))
            .getSingleOrNull();
    if (matchingSummary == null) {
      return false;
    }

    final deletingMutation =
        await (_database.select(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.songId.equals(matchingSummary.songId) &
                  table.syncStatus.equals(SongSyncStatus.pendingDelete.value),
            ))
            .getSingleOrNull();
    return deletingMutation == null;
  }

  SongSummary _summaryFromVisibleMutation(CachedCatalogSongMutation row) {
    return SongSummary(
      id: row.songId,
      title: row.title,
      slug: row.slug,
      version: row.version,
    );
  }

  Future<CachedCatalogSongMutation?> _readVisibleMutationBySongId({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return (_database.select(_database.cachedCatalogSongMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.songId.equals(songId) &
              table.syncStatus
                  .equals(SongSyncStatus.pendingDelete.value)
                  .not() &
              table.syncStatus.equals(SongSyncStatus.synced.value).not() &
              // D2: a `cancelling` tombstone must not be visible either.
              table.syncStatus.equals(SongSyncStatus.cancelling.value).not(),
        ))
        .getSingleOrNull();
  }

  Future<CachedCatalogSongMutation?> _readVisibleMutationBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) {
    return (_database.select(_database.cachedCatalogSongMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.slug.equals(songSlug) &
              table.syncStatus
                  .equals(SongSyncStatus.pendingDelete.value)
                  .not() &
              table.syncStatus.equals(SongSyncStatus.synced.value).not() &
              // D2: a `cancelling` tombstone must not be visible either.
              table.syncStatus.equals(SongSyncStatus.cancelling.value).not(),
        ))
        .getSingleOrNull();
  }

  Future<bool> _isSnapshotSongHidden({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final mutationRow = await readSongMutationBySongId(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (mutationRow == null) {
      return false;
    }

    return _songSyncStatusFromValue(mutationRow.syncStatus) !=
        SongSyncStatus.synced;
  }

  void _upsertVisibleRow(
    Map<String, _VisibleSongRow> visibleRows,
    Map<String, String> slugOwners,
    _VisibleSongRow row,
  ) {
    _removeVisibleRowsBySlug(
      visibleRows,
      slugOwners: slugOwners,
      slug: row.slug,
      exceptSongId: row.songId,
    );
    final previousRow = visibleRows[row.songId];
    if (previousRow != null && previousRow.slug != row.slug) {
      final currentOwner = slugOwners[previousRow.slug];
      if (currentOwner == row.songId) {
        slugOwners.remove(previousRow.slug);
      }
    }
    visibleRows[row.songId] = row;
    slugOwners[row.slug] = row.songId;
  }

  void _removeVisibleRowsBySlug(
    Map<String, _VisibleSongRow> visibleRows, {
    required Map<String, String> slugOwners,
    required String slug,
    String? exceptSongId,
  }) {
    final conflictingSongId = slugOwners[slug];
    if (conflictingSongId == null || conflictingSongId == exceptSongId) {
      return;
    }
    visibleRows.remove(conflictingSongId);
    slugOwners.remove(slug);
  }

  Future<int> _deleteCatalogRows({
    required String userId,
    required String organizationId,
  }) async {
    var deletedRows = 0;
    deletedRows +=
        await (_database.delete(_database.cachedCatalogSummaries)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    deletedRows +=
        await (_database.delete(_database.cachedCatalogSources)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    deletedRows +=
        await (_database.delete(_database.cachedCatalogSongMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    return deletedRows;
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
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'å': 'a',
      'ā': 'a',
      'ă': 'a',
      'ą': 'a',
      'ç': 'c',
      'ć': 'c',
      'č': 'c',
      'ď': 'd',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ē': 'e',
      'ė': 'e',
      'ę': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ī': 'i',
      'į': 'i',
      'ł': 'l',
      'ñ': 'n',
      'ń': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ő': 'o',
      'ø': 'o',
      'ō': 'o',
      'ř': 'r',
      'ś': 's',
      'š': 's',
      'ß': 'ss',
      'ť': 't',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ű': 'u',
      'ū': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'ž': 'z',
      'ź': 'z',
      'ż': 'z',
    };

    final unaccented = value
        .trim()
        .toLowerCase()
        .split('')
        .map((char) => replacements[char] ?? char)
        .join();
    final normalized = unaccented
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
    required this.version,
  });

  final String songId;
  final String title;
  final String slug;
  final int version;
}
