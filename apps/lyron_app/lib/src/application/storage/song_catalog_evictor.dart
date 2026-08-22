import 'dart:async';

import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint_revision.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// D6 (docs/specs/2026-08-19-local-data-durability-contract.md): the hard
/// ceiling that triggers [SongCatalogEvictor.evictToBudget] from
/// `DriftSongCatalogStore.replaceActiveSnapshot`, set with the product owner
/// 2026-08-19 on the understanding that real catalogs are orders of
/// magnitude smaller -- the budget exists to make the mechanism inert in
/// practice while keeping a defined ceiling.
///
/// Deliberately separate from [LocalStorageBudget]'s `totalWarnBytes` /
/// `totalCriticalBytes`: those are display-only thresholds for the sync
/// overview's pressure classification and never trigger eviction on their
/// own (ADR-028 D6/D7). Conflating the two would mean either raising the
/// tiny warn/critical thresholds until they no longer serve their display
/// purpose, or silently making the display thresholds start evicting data,
/// neither of which is this catalog-specific hard-eviction ceiling's job.
const int kCatalogStorageBudgetBytes = 2 * 1024 * 1024 * 1024;

/// The only eviction the app performs.
///
/// Deletes cached song **sources** for songs that carry no pending song
/// mutation. Sources are the largest cached payload and are re-fetchable, so
/// they are the one thing that can be given up under storage pressure.
///
/// Never touched: pending song mutations and pending planning mutations
/// (unsynced intent), cached summaries (they back the browsable list), the
/// planning projection (offline it is the only readable view) and the
/// last-known identity store (ADR-020).
///
/// This is local storage policy, never an authorization decision.
class SongCatalogEvictor {
  const SongCatalogEvictor({
    required this._database,
    required this._accountant,
    this._onStorageFootprintChanged,
    this._eventsRecorder,
  });

  final SongCatalogDatabase _database;
  final CatalogStorageAccountant _accountant;
  final LocalStorageFootprintChanged? _onStorageFootprintChanged;

  /// D7 (docs/specs/2026-08-19-local-data-durability-contract.md): "every
  /// purge and every eviction writes a `local_data_events` record." Wired
  /// here rather than in each caller (`LocalStorageWriteRecovery`'s
  /// reactive path and `DriftSongCatalogStore`'s proactive one) so every
  /// eviction this app performs, from either trigger, is audited exactly
  /// once through the one class that actually deletes the rows.
  /// Best-effort -- a failure writing the audit record must never affect
  /// the eviction that already committed, mirroring
  /// [_onStorageFootprintChanged]. `null` in tests that construct this
  /// class directly; production wiring always supplies it.
  final LocalDataEventsRecorder? _eventsRecorder;

  /// Best-effort: writes the D7 eviction audit record without letting a
  /// failure here affect the eviction that already committed above it (it
  /// runs via [unawaited] from every call site, so this method's own
  /// `Future` is never even awaited by its caller).
  Future<void> _recordEvictionBestEffort({
    String? userId,
    required int rowsAffected,
  }) async {
    final recorder = _eventsRecorder;
    if (recorder == null) {
      return;
    }
    try {
      await recorder.recordEviction(
        target: 'songCatalog',
        userId: userId,
        rowsAffected: rowsAffected,
      );
    } catch (_) {
      // Best-effort only: the eviction itself already committed and must
      // not be affected by an audit-write failure.
    }
  }

  /// Returns the estimated bytes freed.
  ///
  /// `measureDroppableBytes()` and the `DELETE` below are two separate,
  /// un-transacted statements, so a write landing between them can make the
  /// returned figure diverge from what was actually deleted -- it is a
  /// best-effort estimate for diagnostics only (it currently only ever ends
  /// up inside [LocalStorageWriteFailure.toString]). This does NOT affect
  /// correctness of the deletion itself: the `DELETE`'s own `NOT EXISTS`
  /// re-evaluates at delete time, so protected rows (songs with a pending
  /// mutation) are never removed regardless of what ran in between. If this
  /// figure is ever used for something user-facing rather than diagnostics,
  /// both statements would need to run inside one transaction first.
  Future<int> evictDroppable() async {
    final droppableBytes = await _accountant.measureDroppableBytes();
    if (droppableBytes == 0) {
      return 0;
    }
    final deletedRows = await _database.customUpdate(
      'DELETE FROM cached_catalog_sources AS s '
      'WHERE NOT EXISTS ('
      'SELECT 1 FROM cached_catalog_song_mutations AS m '
      'WHERE m.user_id = s.user_id '
      'AND m.organization_id = s.organization_id '
      'AND m.song_id = s.song_id)',
      updates: {_database.cachedCatalogSources},
    );
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
      unawaited(_recordEvictionBestEffort(rowsAffected: deletedRows));
    }
    return droppableBytes;
  }

  /// Proactive, ordered eviction for D6's measured-footprint trigger. Unlike
  /// [evictDroppable] (which evicts everything droppable immediately, for
  /// the emergency "a write just failed and must succeed on retry" path),
  /// this evicts only until [targetBytes] worth of droppable content has
  /// been freed, in an order that protects the caller's active context:
  /// every other `(userId, organizationId)` pair with droppable content is
  /// evicted first (oldest `refreshedAt` first among them), and the active
  /// pair is touched last -- only if freeing every other pair's droppable
  /// content still isn't enough (ADR-035 Task 3.4's cheap ordering proxy).
  ///
  /// Each evicted pair's [CachedCatalogSnapshots] row is marked
  /// `sourcesEvictedAt` (D6 Recoverability) so a future diagnostics view can
  /// show which snapshots need a real refresh to restore their sources; the
  /// marker is cleared automatically the next time that pair's snapshot is
  /// replaced (see `SongCatalogStore._replaceActiveSnapshot`).
  ///
  /// Each candidate pair's delete-and-mark is wrapped in its own
  /// transaction (so a crash mid-pair cannot delete sources without
  /// recording the marker, or vice versa), but the whole multi-pair walk is
  /// NOT one single transaction: each pair commits independently, so a
  /// partial run still leaves earlier-processed pairs correctly evicted and
  /// marked rather than all-or-nothing across pairs.
  ///
  /// Returns the total bytes actually freed.
  Future<int> evictToBudget({
    required int targetBytes,
    required String activeUserId,
    required String activeOrganizationId,
  }) async {
    final candidateRows = await _database
        .customSelect(
          'SELECT DISTINCT s.user_id AS user_id, '
          's.organization_id AS organization_id, '
          'sn.refreshed_at AS refreshed_at '
          'FROM cached_catalog_sources AS s '
          // INNER JOIN, not LEFT: a pair with droppable sources but no
          // matching cached_catalog_snapshots row (finding 3, ADR-028 Task
          // 3.4 amendment) has nowhere to record sourcesEvictedAt, so it
          // must never be a candidate at all -- evicting it would silently
          // destroy its sources without the recoverability marker D6
          // requires. A LEFT JOIN previously admitted it with
          // refreshed_at == null, which sorts before every real timestamp
          // below and evicted it FIRST.
          'INNER JOIN cached_catalog_snapshots AS sn '
          'ON sn.user_id = s.user_id AND sn.organization_id = s.organization_id '
          'WHERE NOT EXISTS ('
          'SELECT 1 FROM cached_catalog_song_mutations AS m '
          'WHERE m.user_id = s.user_id '
          'AND m.organization_id = s.organization_id '
          'AND m.song_id = s.song_id)',
          readsFrom: {
            _database.cachedCatalogSources,
            _database.cachedCatalogSnapshots,
            _database.cachedCatalogSongMutations,
          },
        )
        .get();

    final candidates =
        candidateRows
            .map(
              (row) => (
                userId: row.read<String>('user_id'),
                organizationId: row.read<String>('organization_id'),
                refreshedAt: row.read<DateTime?>('refreshed_at'),
              ),
            )
            .toList()
          ..sort((a, b) {
            final aIsActive =
                a.userId == activeUserId &&
                a.organizationId == activeOrganizationId;
            final bIsActive =
                b.userId == activeUserId &&
                b.organizationId == activeOrganizationId;
            if (aIsActive != bIsActive) {
              // The active pair always sorts last, regardless of recency.
              return aIsActive ? 1 : -1;
            }
            final aTime =
                a.refreshedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime =
                b.refreshedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return aTime.compareTo(bTime);
          });

    var totalFreed = 0;
    for (final candidate in candidates) {
      if (totalFreed >= targetBytes) {
        break;
      }
      final pairBytes = await _accountant.measureDroppableBytesFor(
        userId: candidate.userId,
        organizationId: candidate.organizationId,
      );
      if (pairBytes == 0) {
        continue;
      }
      var pairDeletedRows = 0;
      await _database.transaction(() async {
        pairDeletedRows = await _database.customUpdate(
          'DELETE FROM cached_catalog_sources AS s '
          'WHERE s.user_id = ? AND s.organization_id = ? '
          'AND NOT EXISTS ('
          'SELECT 1 FROM cached_catalog_song_mutations AS m '
          'WHERE m.user_id = s.user_id '
          'AND m.organization_id = s.organization_id '
          'AND m.song_id = s.song_id)',
          variables: [
            Variable(candidate.userId),
            Variable(candidate.organizationId),
          ],
          updates: {_database.cachedCatalogSources},
        );
        await (_database.update(_database.cachedCatalogSnapshots)..where(
              (table) =>
                  table.userId.equals(candidate.userId) &
                  table.organizationId.equals(candidate.organizationId),
            ))
            .write(
              CachedCatalogSnapshotsCompanion(
                sourcesEvictedAt: Value(DateTime.now().toUtc()),
              ),
            );
      });
      totalFreed += pairBytes;
      if (pairDeletedRows > 0) {
        unawaited(
          _recordEvictionBestEffort(
            userId: candidate.userId,
            rowsAffected: pairDeletedRows,
          ),
        );
      }
    }

    if (totalFreed > 0) {
      _onStorageFootprintChanged?.call();
    }
    return totalFreed;
  }
}
