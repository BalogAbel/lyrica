import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

class DriftPendingLocalWorkReader {
  const DriftPendingLocalWorkReader({
    required PlanningLocalDatabase planningDatabase,
    required SongCatalogDatabase songDatabase,
  }) : _planningDatabase = planningDatabase,
       _songDatabase = songDatabase;

  final PlanningLocalDatabase _planningDatabase;
  final SongCatalogDatabase _songDatabase;

  Future<int> countPlanningPendingWork({required String userId}) async {
    final table = _planningDatabase.cachedPlanningMutations;
    final countExpression = table.aggregateId.count();
    final actionableStatuses = PlanningMutationSyncStatus.values
        .map((status) => status.value)
        .toList(growable: false);
    final query = _planningDatabase.selectOnly(table)
      ..addColumns([countExpression])
      ..where(
        table.userId.equals(userId) & table.syncStatus.isIn(actionableStatuses),
      );
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
