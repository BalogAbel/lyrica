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

  const planningCases =
      <
        ({
          String label,
          PlanningMutationSyncStatus status,
          String organizationId,
        })
      >[
        (
          label: 'pending',
          status: PlanningMutationSyncStatus.pending,
          organizationId: 'org-1',
        ),
        (
          label: 'accepted',
          status: PlanningMutationSyncStatus.accepted,
          organizationId: 'org-2',
        ),
        (
          label: 'failed authorization',
          status: PlanningMutationSyncStatus.failedAuthorization,
          organizationId: 'org-1',
        ),
        (
          label: 'failed dependency',
          status: PlanningMutationSyncStatus.failedDependency,
          organizationId: 'org-2',
        ),
        (
          label: 'failed remote delete',
          status: PlanningMutationSyncStatus.failedRemoteDelete,
          organizationId: 'org-1',
        ),
        (
          label: 'conflict',
          status: PlanningMutationSyncStatus.conflict,
          organizationId: 'org-2',
        ),
      ];

  for (final testCase in planningCases) {
    test(
      'counts ${testCase.label} planning work in ${testCase.organizationId}',
      () async {
        await _insertPlanningMutation(
          planningDatabase,
          userId: 'user-1',
          organizationId: testCase.organizationId,
          aggregateId: 'target-plan',
          status: testCase.status,
          orderKey: 1,
        );

        final count = await reader.countPlanningPendingWork(userId: 'user-1');

        expect(count, 1);
      },
    );
  }

  test('sums all six qualifying planning rows across organizations', () async {
    for (var index = 0; index < planningCases.length; index++) {
      final testCase = planningCases[index];
      await _insertPlanningMutation(
        planningDatabase,
        userId: 'user-1',
        organizationId: testCase.organizationId,
        aggregateId: 'target-plan-$index',
        status: testCase.status,
        orderKey: index + 1,
      );
    }

    final count = await reader.countPlanningPendingWork(userId: 'user-1');

    expect(count, 6);
  });

  test(
    'adding another user planning row leaves the user count unchanged',
    () async {
      await _insertPlanningMutation(
        planningDatabase,
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateId: 'target-plan',
        status: PlanningMutationSyncStatus.pending,
        orderKey: 1,
      );
      final beforeExcludedRow = await reader.countPlanningPendingWork(
        userId: 'user-1',
      );
      await _insertPlanningMutation(
        planningDatabase,
        userId: 'user-2',
        organizationId: 'org-1',
        aggregateId: 'other-user-plan',
        status: PlanningMutationSyncStatus.pending,
        orderKey: 2,
      );

      final afterExcludedRow = await reader.countPlanningPendingWork(
        userId: 'user-1',
      );

      expect(afterExcludedRow, beforeExcludedRow);
      expect(beforeExcludedRow, 1);
    },
  );

  test('counts a planning row carrying a sync_status value that is not a '
      'current enum member', () async {
    // Migration artefact / corruption / future status: the delete path
    // (deletePlanningDataForUser) removes this row with no status
    // predicate at all, so the count must include it too.
    await _insertPlanningMutationRawStatus(
      planningDatabase,
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateId: 'target-plan',
      rawStatus: 'legacy_migrated_status',
      orderKey: 1,
    );

    final count = await reader.countPlanningPendingWork(userId: 'user-1');

    expect(count, 1);
  });

  const songCases =
      <({String label, SongSyncStatus status, String organizationId})>[
        (
          label: 'pending create',
          status: SongSyncStatus.pendingCreate,
          organizationId: 'org-1',
        ),
        (
          label: 'pending update',
          status: SongSyncStatus.pendingUpdate,
          organizationId: 'org-2',
        ),
        (
          label: 'pending delete',
          status: SongSyncStatus.pendingDelete,
          organizationId: 'org-1',
        ),
        (
          label: 'conflict',
          status: SongSyncStatus.conflict,
          organizationId: 'org-2',
        ),
      ];

  for (final testCase in songCases) {
    test(
      'counts ${testCase.label} song work in ${testCase.organizationId}',
      () async {
        await _insertSongMutation(
          songDatabase,
          userId: 'user-1',
          organizationId: testCase.organizationId,
          songId: 'target-song',
          status: testCase.status,
        );

        final count = await reader.countSongPendingWork(userId: 'user-1');

        expect(count, 1);
      },
    );
  }

  test('sums all four qualifying song rows across organizations', () async {
    for (var index = 0; index < songCases.length; index++) {
      final testCase = songCases[index];
      await _insertSongMutation(
        songDatabase,
        userId: 'user-1',
        organizationId: testCase.organizationId,
        songId: 'target-song-$index',
        status: testCase.status,
      );
    }

    final count = await reader.countSongPendingWork(userId: 'user-1');

    expect(count, 4);
  });

  test('adding a synced song leaves the user work count unchanged', () async {
    await _insertSongMutation(
      songDatabase,
      userId: 'user-1',
      organizationId: 'org-1',
      songId: 'target-song',
      status: SongSyncStatus.pendingCreate,
    );
    final beforeExcludedRow = await reader.countSongPendingWork(
      userId: 'user-1',
    );
    await _insertSongMutation(
      songDatabase,
      userId: 'user-1',
      organizationId: 'org-2',
      songId: 'synced-song',
      status: SongSyncStatus.synced,
    );

    final afterExcludedRow = await reader.countSongPendingWork(
      userId: 'user-1',
    );

    expect(afterExcludedRow, beforeExcludedRow);
    expect(beforeExcludedRow, 1);
  });

  test('counts a song row carrying a sync_status value that is not a current '
      'enum member', () async {
    // deleteCatalogsForUser also has no status predicate: a corrupt or
    // future status string must still be counted, same as planning.
    await _insertSongMutationRawStatus(
      songDatabase,
      userId: 'user-1',
      organizationId: 'org-1',
      songId: 'target-song',
      rawStatus: 'legacy_migrated_status',
    );

    final count = await reader.countSongPendingWork(userId: 'user-1');

    expect(count, 1);
  });

  test(
    'adding another user song leaves the user work count unchanged',
    () async {
      await _insertSongMutation(
        songDatabase,
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'target-song',
        status: SongSyncStatus.pendingCreate,
      );
      final beforeExcludedRow = await reader.countSongPendingWork(
        userId: 'user-1',
      );
      await _insertSongMutation(
        songDatabase,
        userId: 'user-2',
        organizationId: 'org-1',
        songId: 'other-user-song',
        status: SongSyncStatus.pendingCreate,
      );

      final afterExcludedRow = await reader.countSongPendingWork(
        userId: 'user-1',
      );

      expect(afterExcludedRow, beforeExcludedRow);
      expect(beforeExcludedRow, 1);
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

Future<void> _insertPlanningMutationRawStatus(
  PlanningLocalDatabase database, {
  required String userId,
  required String organizationId,
  required String aggregateId,
  required String rawStatus,
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
          syncStatus: rawStatus,
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
  return _insertSongMutationRawStatus(
    database,
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    rawStatus: status.value,
  );
}

Future<void> _insertSongMutationRawStatus(
  SongCatalogDatabase database, {
  required String userId,
  required String organizationId,
  required String songId,
  required String rawStatus,
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
          syncStatus: rawStatus,
        ),
      );
}
