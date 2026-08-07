import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

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

  test(
    'an existing pre-migration (v5) database gains localRevision on upgrade '
    'and keeps its pending row intact (D1, sync-snapshot-identity)',
    () async {
      final file = await createRelaunchDbFile('planning-migration-v5-v6');
      PlanningLocalDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      // Build a genuine pre-migration v5 database by hand, via raw sqlite3
      // (not through PlanningLocalDatabase, which would create the CURRENT
      // -- post-migration -- schema directly via onCreate and never
      // exercise onUpgrade at all). This is the exact CREATE TABLE text
      // Drift generated for schemaVersion 5 before localRevision existed,
      // captured from `sqlite_master` against that version of the code.
      final rawDb = sqlite3.sqlite3.open(file.path);
      rawDb.execute('''
        CREATE TABLE "planning_projection_owners" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "refreshed_at" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id")
        );
        CREATE TABLE "cached_planning_plans" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "plan_id" TEXT NOT NULL,
          "slug" TEXT NOT NULL,
          "name" TEXT NOT NULL,
          "description" TEXT NULL,
          "scheduled_for" INTEGER NULL,
          "updated_at" INTEGER NOT NULL,
          "version" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "plan_id")
        );
        CREATE TABLE "cached_planning_sessions" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "session_id" TEXT NOT NULL,
          "plan_id" TEXT NOT NULL,
          "slug" TEXT NOT NULL,
          "position" INTEGER NOT NULL,
          "name" TEXT NOT NULL,
          "version" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "session_id")
        );
        CREATE TABLE "cached_planning_session_items" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "session_item_id" TEXT NOT NULL,
          "plan_id" TEXT NOT NULL,
          "session_id" TEXT NOT NULL,
          "position" INTEGER NOT NULL,
          "song_id" TEXT NOT NULL,
          "song_title" TEXT NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "session_item_id")
        );
        CREATE TABLE "cached_planning_mutations" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "aggregate_type" TEXT NOT NULL,
          "aggregate_id" TEXT NOT NULL,
          "mutation_kind" TEXT NOT NULL,
          "sync_status" TEXT NOT NULL,
          "plan_id" TEXT NULL,
          "session_id" TEXT NULL,
          "slug" TEXT NULL,
          "name" TEXT NULL,
          "description" TEXT NULL,
          "scheduled_for" INTEGER NULL,
          "position" INTEGER NULL,
          "song_id" TEXT NULL,
          "song_title" TEXT NULL,
          "ordered_sibling_ids" TEXT NULL,
          "base_version" INTEGER NULL,
          "origin_snapshot_json" TEXT NULL,
          "error_code" TEXT NULL,
          "error_message" TEXT NULL,
          "order_key" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "aggregate_type", "aggregate_id")
        );
      ''');
      rawDb.execute('''
        INSERT INTO cached_planning_mutations (
          user_id, organization_id, aggregate_type, aggregate_id,
          mutation_kind, sync_status, slug, name, description,
          order_key, updated_at
        ) VALUES (
          'user-1', 'org-1', 'plan', 'plan-pre-migration',
          'plan_create', 'pending', 'pre-migration-plan', 'Pre-Migration Plan',
          'Created before localRevision existed', 1, 0
        );
      ''');
      // Drift tracks the schema version via PRAGMA user_version -- this is
      // what makes onUpgrade(m, from: 5, to: 6) fire below, instead of
      // onCreate (which would build the CURRENT schema directly and never
      // touch the migration code at all).
      rawDb.execute('PRAGMA user_version = 5;');
      rawDb.close();

      final db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
      openDb = db;
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      final pending = await store.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      final record = pending.single;
      expect(record.aggregateId, 'plan-pre-migration');
      expect(record.kind, PlanningMutationKind.planCreate);
      expect(record.syncStatus, PlanningMutationSyncStatus.pending);
      expect(record.slug, 'pre-migration-plan');
      expect(record.name, 'Pre-Migration Plan');
      expect(record.description, 'Created before localRevision existed');
      expect(
        record.localRevision,
        1,
        reason:
            'a pre-migration row has no sync attempt in flight to '
            'distinguish from -- 1 is a sane starting revision, matching '
            'what a freshly-inserted row gets',
      );

      // The migrated column is real and usable, not just present: a
      // subsequent local write must be able to bump it, exactly as it
      // would for a row that was always on the current schema.
      await store.recordPlanEdit(
        context: const PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-pre-migration',
          name: 'Edited After Migration',
        ),
      );
      final afterEdit = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-pre-migration',
      );
      expect(afterEdit!.localRevision, 2);

      await db.close();
      openDb = null;
    },
  );
}
