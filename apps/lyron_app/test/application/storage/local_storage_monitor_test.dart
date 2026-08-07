import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/storage/local_storage_monitor.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('LocalStorageMonitor', () {
    late PlanningLocalDatabase database;
    late SongCatalogDatabase catalogDatabase;
    late DriftPlanningMutationStore mutationStore;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      catalogDatabase = SongCatalogDatabase.inMemory();
      mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: DriftPlanningLocalStore(database),
      );
    });

    tearDown(() async {
      await database.close();
      await catalogDatabase.close();
    });

    LocalStorageMonitor monitorWith(LocalStorageBudget budget) {
      return LocalStorageMonitor(
        planningAccountant: PlanningStorageAccountant(database),
        catalogAccountant: CatalogStorageAccountant(catalogDatabase),
        budget: budget,
      );
    }

    test('reports an empty footprint and ok pressure with no data', () async {
      final monitor = monitorWith(const LocalStorageBudget());

      final footprint = await monitor.measure(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(footprint.totalBytes, 0);
      expect(monitor.pressureOf(footprint), LocalStoragePressure.ok);
    });

    test('reports mutation bytes, count and warning pressure', () async {
      await mutationStore.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      final monitor = monitorWith(
        const LocalStorageBudget(
          mutationWarnBytes: 1,
          mutationRefuseBytes: 1000000,
        ),
      );

      final footprint = await monitor.measure(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(footprint.mutationCount, 1);
      expect(footprint.mutationBytes, greaterThan(0));
      expect(monitor.pressureOf(footprint), LocalStoragePressure.warning);
    });
  });
}
