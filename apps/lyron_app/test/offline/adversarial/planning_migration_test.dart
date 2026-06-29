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
      // Track the currently-open database so a mid-test failure still closes
      // the live connection (and frees the sqlite file) before the temp dir is
      // removed, instead of relying on the explicit close() calls below.
      PlanningLocalDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      var db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
      openDb = db;
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
      openDb = null;

      db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
      openDb = db;
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
      openDb = null;
    },
  );
}
