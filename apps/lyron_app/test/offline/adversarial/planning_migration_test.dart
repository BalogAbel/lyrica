import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_relaunch.dart';
import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test(
    'a pending planning mutation survives a database reopen across the v5 schema (LF-T7)',
    () async {
      final file = await createRelaunchDbFile('planning-migration');

      var db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
      var localStore = DriftPlanningLocalStore(db);
      var store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      await store.recordPlanCreate(
        context: const PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: PlanningPlanCreateMutationDraft(
          planId: 'plan-local-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Local draft',
          scheduledFor: DateTime.utc(2026, 4, 12, 9),
        ),
      );

      await db.close();

      db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
      localStore = DriftPlanningLocalStore(db);
      store = DriftPlanningMutationStore(database: db, localStore: localStore);

      final pending = await store.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      expect(pending.single.syncStatus, PlanningMutationSyncStatus.pending);
      expect(pending.single.aggregateId, 'plan-local-1');
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.slug, 'weekend-service');
      expect(pending.single.name, 'Weekend Service');
      expect(pending.single.description, 'Local draft');
      expect(pending.single.scheduledFor, DateTime.utc(2026, 4, 12, 9));

      await db.close();
    },
  );
}
