import 'package:drift/drift.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// When songs and plans last refreshed successfully for one
/// (userId, organizationId). SG7 (docs/specs/2026-10-05-offline-first
/// -startup-gate.md). Device wall-clock values: for display only, never
/// compared or ordered (ADR-030).
class SyncFreshness {
  const SyncFreshness({
    required this.songsRefreshedAt,
    required this.plansRefreshedAt,
  });

  const SyncFreshness.unknown()
    : songsRefreshedAt = null,
      plansRefreshedAt = null;

  final DateTime? songsRefreshedAt;
  final DateTime? plansRefreshedAt;

  @override
  bool operator ==(Object other) =>
      other is SyncFreshness &&
      other.songsRefreshedAt == songsRefreshedAt &&
      other.plansRefreshedAt == plansRefreshedAt;

  @override
  int get hashCode => Object.hash(songsRefreshedAt, plansRefreshedAt);
}

/// Reads the persisted refresh times straight from the two databases, like
/// the storage accountants do. A separate class rather than new store
/// methods: SongCatalogStore and PlanningLocalStore have many hand-written
/// test fakes.
class SyncFreshnessReader {
  const SyncFreshnessReader({
    required this._songCatalogDatabase,
    required this._planningLocalDatabase,
  });

  final SongCatalogDatabase _songCatalogDatabase;
  final PlanningLocalDatabase _planningLocalDatabase;

  Future<SyncFreshness> read({
    required String userId,
    required String organizationId,
  }) async {
    final snapshot =
        await (_songCatalogDatabase.select(
              _songCatalogDatabase.cachedCatalogSnapshots,
            )..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .getSingleOrNull();
    final owner =
        await (_planningLocalDatabase.select(
              _planningLocalDatabase.planningProjectionOwners,
            )..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .getSingleOrNull();
    return SyncFreshness(
      songsRefreshedAt: snapshot?.refreshedAt,
      plansRefreshedAt: owner?.refreshedAt,
    );
  }
}
