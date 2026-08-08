import 'package:drift/drift.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

class DriftPendingLocalWorkReader {
  const DriftPendingLocalWorkReader({
    required this._planningDatabase,
    required this._songDatabase,
  });

  final PlanningLocalDatabase _planningDatabase;
  final SongCatalogDatabase _songDatabase;

  /// Counts every planning mutation row for [userId], regardless of its
  /// `sync_status` value.
  ///
  /// This must match `deletePlanningDataForUser`'s delete predicate exactly:
  /// that delete has no status predicate at all, so a row carrying a status
  /// string that is not a current
  /// [PlanningMutationSyncStatus] member (a migration artefact, corruption,
  /// or a future status) is still destroyed by the wipe. Filtering the count
  /// by known statuses would let such a row be destroyed uncounted, which
  /// would under-report what a confirmation dialog claims a wipe will take.
  Future<int> countPlanningPendingWork({required String userId}) async {
    final table = _planningDatabase.cachedPlanningMutations;
    final countExpression = table.aggregateId.count();
    final query = _planningDatabase.selectOnly(table)
      ..addColumns([countExpression])
      ..where(table.userId.equals(userId));
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  Future<int> countSongPendingWork({required String userId}) async {
    final table = _songDatabase.cachedCatalogSongMutations;
    final countExpression = table.songId.count();
    final query = _songDatabase.selectOnly(table)
      ..addColumns([countExpression])
      ..where(
        table.userId.equals(userId) &
            table.syncStatus.equals(SongSyncStatus.synced.value).not(),
      );
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }
}
