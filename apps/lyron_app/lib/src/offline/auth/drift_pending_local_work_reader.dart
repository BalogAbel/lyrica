import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

class DriftPendingLocalWorkReader {
  const DriftPendingLocalWorkReader({
    required PlanningLocalDatabase planningDatabase,
    required SongCatalogDatabase songDatabase,
  }) : _planningDatabase = planningDatabase,
       _songDatabase = songDatabase;

  final PlanningLocalDatabase _planningDatabase;
  final SongCatalogDatabase _songDatabase;

  Future<int> countPlanningPendingWork({required String userId}) async {
    _planningDatabase;
    return 0;
  }

  Future<int> countSongPendingWork({required String userId}) async {
    _songDatabase;
    return 0;
  }
}
