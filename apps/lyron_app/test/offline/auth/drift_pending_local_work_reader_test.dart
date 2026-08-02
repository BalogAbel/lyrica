import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/auth/drift_pending_local_work_reader.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart'
    show SongSyncStatus, SongSyncStatusX;

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late PlanningLocalDatabase planningDatabase;
  late SongCatalogDatabase songDatabase;
  late DriftPendingLocalWorkReader reader;

  setUp(() {
    planningDatabase = PlanningLocalDatabase.inMemory();
    songDatabase = SongCatalogDatabase.inMemory();
    reader = DriftPendingLocalWorkReader(
      planningDatabase: planningDatabase,
      songDatabase: songDatabase,
    );
  });

  tearDown(() async {
    await planningDatabase.close();
    await songDatabase.close();
  });

  test(
    'counts every actionable planning status for a user across organizations',
    () async {
      const statuses = <PlanningMutationSyncStatus>[
        PlanningMutationSyncStatus.pending,
        PlanningMutationSyncStatus.accepted,
        PlanningMutationSyncStatus.failedAuthorization,
        PlanningMutationSyncStatus.failedDependency,
        PlanningMutationSyncStatus.failedRemoteDelete,
        PlanningMutationSyncStatus.conflict,
      ];
      for (var index = 0; index < statuses.length; index++) {
        await _insertPlanningMutation(
          planningDatabase,
          userId: 'user-1',
          organizationId: index.isEven ? 'org-1' : 'org-2',
          aggregateId: 'plan-$index',
          status: statuses[index],
          orderKey: index,
        );
      }
      await _insertPlanningMutation(
        planningDatabase,
        userId: 'user-2',
        organizationId: 'org-1',
        aggregateId: 'other-user-plan',
        status: PlanningMutationSyncStatus.pending,
        orderKey: 7,
      );

      final count = await reader.countPlanningPendingWork(userId: 'user-1');

      expect(count, 6);
    },
  );

  test(
    'counts unsynced and conflict songs for a user across organizations',
    () async {
      const statuses = <SongSyncStatus>[
        SongSyncStatus.pendingCreate,
        SongSyncStatus.pendingUpdate,
        SongSyncStatus.pendingDelete,
        SongSyncStatus.conflict,
      ];
      for (var index = 0; index < statuses.length; index++) {
        await _insertSongMutation(
          songDatabase,
          userId: 'user-1',
          organizationId: index.isEven ? 'org-1' : 'org-2',
          songId: 'song-$index',
          status: statuses[index],
        );
      }
      await _insertSongMutation(
        songDatabase,
        userId: 'user-1',
        organizationId: 'org-2',
        songId: 'synced-song',
        status: SongSyncStatus.synced,
      );
      await _insertSongMutation(
        songDatabase,
        userId: 'user-2',
        organizationId: 'org-1',
        songId: 'other-user-song',
        status: SongSyncStatus.pendingCreate,
      );

      final count = await reader.countSongPendingWork(userId: 'user-1');

      expect(count, 4);
    },
  );
}

Future<void> _insertPlanningMutation(
  PlanningLocalDatabase database, {
  required String userId,
  required String organizationId,
  required String aggregateId,
  required PlanningMutationSyncStatus status,
  required int orderKey,
}) {
  return database
      .into(database.cachedPlanningMutations)
      .insert(
        CachedPlanningMutationsCompanion.insert(
          userId: userId,
          organizationId: organizationId,
          aggregateType: 'plan',
          aggregateId: aggregateId,
          mutationKind: PlanningMutationKind.planEdit.value,
          syncStatus: status.value,
          orderKey: orderKey,
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
      );
}

Future<void> _insertSongMutation(
  SongCatalogDatabase database, {
  required String userId,
  required String organizationId,
  required String songId,
  required SongSyncStatus status,
}) {
  return database
      .into(database.cachedCatalogSongMutations)
      .insert(
        CachedCatalogSongMutationsCompanion.insert(
          userId: userId,
          organizationId: organizationId,
          songId: songId,
          slug: songId,
          title: songId,
          source: '{title: $songId}',
          version: 1,
          syncStatus: status.value,
        ),
      );
}
