import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningMutationStore', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'reports a committed mutation after commit and not for a throw or true no-op',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'planning-mutation-footprint-revision-test',
        );
        addTearDown(() async {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        final dbFile = File(p.join(directory.path, 'planning.sqlite'));
        final trackedDatabase = PlanningLocalDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        addTearDown(trackedDatabase.close);
        final observer = sqlite3.open(dbFile.path);
        addTearDown(observer.close);
        final committedRowCounts = <int>[];
        final trackedStore = DriftPlanningMutationStore(
          database: trackedDatabase,
          localStore: DriftPlanningLocalStore(trackedDatabase),
          onStorageFootprintChanged: () {
            final row = observer
                .select(
                  'SELECT count(*) AS row_count FROM cached_planning_mutations',
                )
                .single;
            committedRowCounts.add(row['row_count'] as int);
          },
        );
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await trackedStore.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        );
        expect(committedRowCounts, [1]);

        await trackedStore.clearMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'plan',
          aggregateId: 'missing-plan',
        );
        expect(committedRowCounts, [1]);

        await expectLater(
          () => trackedStore.recordPlanCreate(
            context: context,
            draft: const PlanningPlanCreateMutationDraft(
              planId: 'plan-2',
              slug: 'weekend-service',
              name: 'Duplicate slug',
            ),
          ),
          throwsA(isA<LocalPlanningSlugConflictException>()),
        );
        expect(committedRowCounts, [1]);
      },
    );

    test('pending mutations persist across database reopen', () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning-mutation-store-test',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final dbFile = File(p.join(directory.path, 'planning.sqlite'));

      var firstDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      var firstLocalStore = DriftPlanningLocalStore(firstDatabase);
      var firstStore = DriftPlanningMutationStore(
        database: firstDatabase,
        localStore: firstLocalStore,
      );

      await firstStore.recordPlanCreate(
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
      await firstDatabase.close();

      final secondDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      addTearDown(secondDatabase.close);
      final secondStore = DriftPlanningMutationStore(
        database: secondDatabase,
        localStore: DriftPlanningLocalStore(secondDatabase),
      );

      final pending = await secondStore.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      expect(pending.single.aggregateId, 'plan-local-1');
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.slug, 'weekend-service');
    });

    test('origin snapshots persist across database reopen', () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning-mutation-store-test-origin',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final dbFile = File(p.join(directory.path, 'planning.sqlite'));

      final firstDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      final firstStore = DriftPlanningMutationStore(
        database: firstDatabase,
        localStore: DriftPlanningLocalStore(firstDatabase),
      );
      await firstStore.recordSessionRename(
        context: const PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          name: 'Opening Set Updated',
          baseVersion: 3,
          originSnapshot: {
            'name': 'Opening Set',
            'slug': 'opening-set',
            'position': 10,
            'version': 3,
          },
        ),
      );
      await firstDatabase.close();

      final secondDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      addTearDown(secondDatabase.close);
      final secondStore = DriftPlanningMutationStore(
        database: secondDatabase,
        localStore: DriftPlanningLocalStore(secondDatabase),
      );

      final pending = await secondStore.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      expect(pending.single.originSnapshot?['name'], 'Opening Set');
      expect(pending.single.originSnapshot?['slug'], 'opening-set');
      expect(pending.single.originSnapshot?['position'], 10);
      expect(pending.single.originSnapshot?['version'], 3);
    });

    test('pending updates keep the original origin snapshot', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service Updated',
          description: 'First local draft',
          baseVersion: 3,
          originSnapshot: {
            'name': 'Weekend Service',
            'description': 'Original',
            'version': 3,
          },
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service Updated Again',
          description: 'Second local draft',
          baseVersion: 4,
          originSnapshot: {
            'name': 'Weekend Service',
            'description': 'Wrong later snapshot',
            'version': 4,
          },
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(pending, hasLength(1));
      expect(pending.single.originSnapshot?['name'], 'Weekend Service');
      expect(pending.single.originSnapshot?['description'], 'Original');
      expect(pending.single.originSnapshot?['version'], 3);
    });

    test(
      'retrying a conflicted plan edit refreshes the base version',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await localStore.replaceActiveProjection(
          userId: context.userId,
          organizationId: context.organizationId,
          plans: [
            CachedPlanRecord(
              id: 'plan-1',
              slug: 'weekend-service',
              name: 'Weekend Service',
              description: 'Canonical',
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 4, 1, 12),
              version: 5,
            ),
          ],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 1, 12),
        );

        await store.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-1',
            name: 'Weekend Service Updated',
            description: 'Pending locally',
            baseVersion: 3,
            originSnapshot: {
              'name': 'Weekend Service',
              'description': 'Original',
              'version': 3,
            },
          ),
        );

        await store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
          syncStatus: PlanningMutationSyncStatus.conflict,
          errorCode: PlanningMutationSyncErrorCode.conflict,
          errorMessage: 'base_version_conflict',
        );

        await store.retryMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        final retriedRecord = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(retriedRecord?.syncStatus, PlanningMutationSyncStatus.pending);
        expect(retriedRecord?.baseVersion, 5);
        expect(retriedRecord?.originSnapshot?['version'], 3);
      },
    );

    test(
      'migrates a version 3 planning database without losing mutations',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'planning-mutation-migration-test',
        );
        addTearDown(() async {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        final dbFile = File(p.join(directory.path, 'planning.sqlite'));

        final rawDb = sqlite3.open(dbFile.path);
        rawDb.execute('''
        create table planning_projection_owners (
          user_id text not null,
          organization_id text not null,
          snapshot_version integer not null,
          refreshed_at integer not null,
          primary key (user_id, organization_id)
        );
      ''');
        rawDb.execute('''
        create table cached_planning_plans (
          user_id text not null,
          organization_id text not null,
          snapshot_version integer not null,
          plan_id text not null,
          slug text not null,
          name text not null,
          description text,
          scheduled_for integer,
          updated_at integer not null,
          version integer not null,
          primary key (user_id, organization_id, plan_id)
        );
      ''');
        rawDb.execute('''
        create table cached_planning_sessions (
          user_id text not null,
          organization_id text not null,
          snapshot_version integer not null,
          session_id text not null,
          plan_id text not null,
          slug text not null,
          position integer not null,
          name text not null,
          version integer not null,
          primary key (user_id, organization_id, session_id)
        );
      ''');
        rawDb.execute('''
        create table cached_planning_session_items (
          user_id text not null,
          organization_id text not null,
          snapshot_version integer not null,
          session_item_id text not null,
          plan_id text not null,
          session_id text not null,
          position integer not null,
          song_id text not null,
          song_title text not null,
          primary key (user_id, organization_id, session_item_id)
        );
      ''');
        rawDb.execute('''
        create table cached_planning_mutations (
          user_id text not null,
          organization_id text not null,
          aggregate_type text not null,
          aggregate_id text not null,
          mutation_kind text not null,
          sync_status text not null,
          plan_id text,
          slug text,
          name text,
          description text,
          scheduled_for integer,
          position integer,
          base_version integer,
          error_code text,
          error_message text,
          order_key integer not null,
          updated_at integer not null,
          primary key (user_id, organization_id, aggregate_type, aggregate_id)
        );
      ''');
        rawDb.execute("""
        insert into cached_planning_mutations (
          user_id,
          organization_id,
          aggregate_type,
          aggregate_id,
          mutation_kind,
          sync_status,
          plan_id,
          name,
          base_version,
          order_key,
          updated_at
        ) values (
          'user-1',
          'org-1',
          'session_order',
          'plan-1',
          'session_reorder',
          'pending',
          'plan-1',
          'Imported reorder',
          3,
          1,
          1712793600000
        );
      """);
        rawDb.execute('pragma user_version = 3;');
        rawDb.close();

        final migratedDatabase = PlanningLocalDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        addTearDown(migratedDatabase.close);
        final migratedStore = DriftPlanningMutationStore(
          database: migratedDatabase,
          localStore: DriftPlanningLocalStore(migratedDatabase),
        );

        final pending = await migratedStore.readPendingMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        expect(pending, hasLength(1));
        expect(pending.single.aggregateId, 'plan-1');
        expect(pending.single.kind, PlanningMutationKind.sessionReorder);
        expect(pending.single.sessionId, isNull);
        expect(pending.single.songId, isNull);
        expect(pending.single.orderedSiblingIds, isNull);
      },
    );

    test('create then edit collapses into one pending plan create', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: PlanningPlanCreateMutationDraft(
          planId: 'plan-local-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Initial',
          scheduledFor: DateTime.utc(2026, 4, 12, 9),
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: PlanningPlanEditMutationDraft(
          planId: 'plan-local-1',
          name: 'Weekend Service Updated',
          description: 'Updated',
          scheduledFor: DateTime.utc(2026, 4, 13, 9),
        ),
      );

      final pending = await store.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.name, 'Weekend Service Updated');
      expect(pending.single.description, 'Updated');
      expect(pending.single.scheduledFor, DateTime.utc(2026, 4, 13, 9));
    });

    test(
      'clearing scheduled-for on a pending plan create removes it',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordPlanCreate(
          context: context,
          draft: PlanningPlanCreateMutationDraft(
            planId: 'plan-local-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Initial',
            scheduledFor: DateTime.utc(2026, 4, 12, 9),
          ),
        );
        await store.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-local-1',
            name: 'Weekend Service',
            description: 'Initial',
            scheduledFor: null,
          ),
        );

        final pending = await store.readPendingMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        expect(pending, hasLength(1));
        expect(pending.single.kind, PlanningMutationKind.planCreate);
        expect(pending.single.scheduledFor, isNull);
      },
    );

    test('clearing description on a pending plan create removes it', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: PlanningPlanCreateMutationDraft(
          planId: 'plan-local-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Initial',
          scheduledFor: DateTime.utc(2026, 4, 12, 9),
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: PlanningPlanEditMutationDraft(
          planId: 'plan-local-1',
          name: 'Weekend Service',
          description: null,
          scheduledFor: DateTime.utc(2026, 4, 12, 9),
        ),
      );

      final pending = await store.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.description, isNull);
    });

    test(
      'session mutations stay tied to the parent locally created plan and create then delete annihilates the local mutation',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-local-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        );
        await store.recordSessionCreate(
          context: context,
          draft: const PlanningSessionCreateMutationDraft(
            sessionId: 'session-local-1',
            planId: 'plan-local-1',
            slug: 'welcome',
            name: 'Welcome',
            position: 30,
          ),
        );
        await store.recordSessionRename(
          context: context,
          draft: const PlanningSessionRenameMutationDraft(
            sessionId: 'session-local-1',
            planId: 'plan-local-1',
            name: 'Welcome Team',
          ),
        );

        final beforeDelete = await store.readPendingMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        expect(beforeDelete, hasLength(2));
        expect(
          beforeDelete.last,
          isA<PlanningMutationRecord>()
              .having(
                (record) => record.aggregateId,
                'aggregateId',
                'session-local-1',
              )
              .having(
                (record) => record.kind,
                'kind',
                PlanningMutationKind.sessionCreate,
              )
              .having((record) => record.planId, 'planId', 'plan-local-1')
              .having((record) => record.name, 'name', 'Welcome Team'),
        );

        await store.recordSessionDelete(
          context: context,
          draft: const PlanningSessionDeleteMutationDraft(
            sessionId: 'session-local-1',
            planId: 'plan-local-1',
          ),
        );

        final afterDelete = await store.readPendingMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        expect(afterDelete, hasLength(1));
        expect(afterDelete.single.aggregateId, 'plan-local-1');
      },
    );

    test(
      'allocates locally unique provisional plan and session slugs before sync succeeds',
      () async {
        await localStore.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [
            CachedPlanRecord(
              id: 'plan-1',
              slug: 'weekend-service',
              name: 'Weekend Service',
              description: null,
              scheduledFor: DateTime.utc(2026, 4, 5, 9),
              updatedAt: DateTime.utc(2026, 4, 1, 12),
            ),
          ],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              slug: 'welcome',
              position: 10,
              name: 'Welcome',
            ),
          ],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 1, 12),
        );

        await store.recordPlanCreate(
          context: const PlanningMutationContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-local-1',
            slug: 'weekend-service-2',
            name: 'Weekend Service Copy',
          ),
        );

        expect(
          await store.allocatePlanSlug(
            userId: 'user-1',
            organizationId: 'org-1',
            name: 'Weekend Service',
          ),
          'weekend-service-3',
        );
        expect(
          await store.allocateSessionSlug(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
            name: 'Welcome',
          ),
          'welcome-2',
        );
      },
    );

    test(
      'persists sync error details and allows retrying a failed mutation',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-1',
            name: 'Updated Plan',
            description: 'Pending locally',
            baseVersion: 3,
          ),
        );

        await store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
          syncStatus: PlanningMutationSyncStatus.conflict,
          errorCode: PlanningMutationSyncErrorCode.conflict,
          errorMessage: 'base_version_conflict',
        );

        final failedRecord = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(failedRecord?.syncStatus, PlanningMutationSyncStatus.conflict);
        expect(failedRecord?.errorCode, PlanningMutationSyncErrorCode.conflict);
        expect(failedRecord?.errorMessage, 'base_version_conflict');

        await store.retryMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        final retriedRecord = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(retriedRecord?.syncStatus, PlanningMutationSyncStatus.pending);
        expect(retriedRecord?.errorCode, isNull);
        expect(retriedRecord?.errorMessage, isNull);
      },
    );

    test(
      'session reorder compacts by plan and keeps the earliest base version',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordSessionReorder(
          context: context,
          draft: const PlanningSessionReorderMutationDraft(
            planId: 'plan-1',
            orderedSessionIds: ['session-2', 'session-1', 'session-3'],
            baseVersion: 7,
          ),
        );
        await store.recordSessionReorder(
          context: context,
          draft: const PlanningSessionReorderMutationDraft(
            planId: 'plan-1',
            orderedSessionIds: ['session-3', 'session-2', 'session-1'],
            baseVersion: 9,
          ),
        );

        final pending = await store.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        );

        expect(pending, hasLength(1));
        expect(pending.single.kind, PlanningMutationKind.sessionReorder);
        expect(pending.single.aggregateId, 'plan-1');
        expect(pending.single.baseVersion, 7);
        expect(
          pending.single.orderedSiblingIds,
          orderedEquals(const ['session-3', 'session-2', 'session-1']),
        );
      },
    );

    test(
      'mutation lifecycle APIs address records by aggregate type and aggregate id',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordSessionDelete(
          context: context,
          draft: const PlanningSessionDeleteMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            baseVersion: 4,
          ),
        );
        await store.recordSessionItemReorder(
          context: context,
          draft: const PlanningSessionItemReorderMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            orderedSessionItemIds: ['item-2', 'item-1'],
            baseVersion: 7,
          ),
        );

        await store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.sessionDelete.aggregateType,
          aggregateId: 'session-1',
          syncStatus: PlanningMutationSyncStatus.conflict,
          errorCode: PlanningMutationSyncErrorCode.conflict,
          errorMessage: 'session_conflict',
        );

        final sessionDelete = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.sessionDelete.aggregateType,
          aggregateId: 'session-1',
        );
        final itemReorder = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.sessionItemReorder.aggregateType,
          aggregateId: 'session-1',
        );

        expect(sessionDelete?.syncStatus, PlanningMutationSyncStatus.conflict);
        expect(itemReorder?.syncStatus, PlanningMutationSyncStatus.pending);

        await store.clearMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.sessionDelete.aggregateType,
          aggregateId: 'session-1',
        );

        final remaining = await store.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        );
        expect(remaining, hasLength(1));
        expect(remaining.single.kind, PlanningMutationKind.sessionItemReorder);
      },
    );

    test(
      'session item create followed by delete annihilates a locally created item mutation',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordSessionItemCreateSong(
          context: context,
          draft: const PlanningSessionItemCreateSongMutationDraft(
            sessionItemId: 'item-local-1',
            sessionId: 'session-1',
            planId: 'plan-1',
            songId: 'song-2',
            songTitle: 'Beta',
            position: 20,
            baseVersion: 3,
          ),
        );
        await store.recordSessionItemDelete(
          context: context,
          draft: const PlanningSessionItemDeleteMutationDraft(
            sessionItemId: 'item-local-1',
            sessionId: 'session-1',
            planId: 'plan-1',
          ),
        );

        final pending = await store.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        );

        expect(pending, isEmpty);
      },
    );

    test(
      'session item reorder drops deleted siblings and compacts by session',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordSessionItemReorder(
          context: context,
          draft: const PlanningSessionItemReorderMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            orderedSessionItemIds: ['item-3', 'item-1', 'item-2'],
            baseVersion: 5,
          ),
        );
        await store.recordSessionItemDelete(
          context: context,
          draft: const PlanningSessionItemDeleteMutationDraft(
            sessionItemId: 'item-1',
            sessionId: 'session-1',
            planId: 'plan-1',
            baseVersion: 5,
          ),
        );

        final pending = await store.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        );

        expect(pending, hasLength(2));
        final reorder = pending.firstWhere(
          (record) => record.kind == PlanningMutationKind.sessionItemReorder,
        );
        expect(
          reorder.orderedSiblingIds,
          orderedEquals(const ['item-3', 'item-2']),
        );
      },
    );
  });

  group('PlanningMutationStore.localRevision (D1, sync-snapshot-identity)', () {
    // docs/specs/2026-08-05-sync-snapshot-identity.md D1: localRevision is
    // local bookkeeping incremented by the store on every local write to a
    // mutation row -- unrelated to baseVersion/version (which track the
    // server's view) and never sent to the backend. This group proves the
    // "every" in that sentence across the write paths the spec calls out by
    // name: a fold (planEdit onto a still-pending planCreate) and a status
    // write (saveSyncAttemptResult, retryMutation).
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('increments by exactly one on every local write, including a fold '
        'and status writes, and never regresses', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );
      final afterCreate = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(
        afterCreate!.localRevision,
        1,
        reason: 'a brand-new row starts at revision 1',
      );

      // Fold: recordPlanEdit onto a still-pending planCreate lands in the
      // SAME row (this is the exact fold the spec's "Problem" section
      // names), not a new one -- the revision must still advance.
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service',
          description: 'Edited description',
        ),
      );
      final afterFold = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(afterFold!.localRevision, 2);
      expect(afterFold.description, 'Edited description');

      // A status write (the shape saveSyncAttemptResult's failure path
      // uses -- no expectedRevision, so it applies unconditionally) also
      // advances the revision.
      final newRevision = await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.failedDependency,
        errorCode: PlanningMutationSyncErrorCode.dependencyBlocked,
      );
      expect(newRevision, 3);
      final afterStatusWrite = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(afterStatusWrite!.localRevision, 3);

      // retryMutation is also a local write (it clears the error and
      // rebases) and must advance the revision too.
      await store.retryMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      final afterRetry = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(afterRetry!.localRevision, 4);
      expect(afterRetry.syncStatus, PlanningMutationSyncStatus.pending);
    });

    test(
      'a conditional saveSyncAttemptResult that matches applies and returns '
      'the new revision; a stale one does not apply and returns null',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        );

        // Matching expectedRevision: applies.
        final applied = await store.saveSyncAttemptResult(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'plan',
          aggregateId: 'plan-1',
          syncStatus: PlanningMutationSyncStatus.accepted,
          expectedRevision: 1,
        );
        expect(applied, 2);

        // A snapshot from before the mutation existed at its new revision:
        // stale, must not apply.
        final stale = await store.saveSyncAttemptResult(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'plan',
          aggregateId: 'plan-1',
          syncStatus: PlanningMutationSyncStatus.accepted,
          expectedRevision: 1,
        );
        expect(stale, isNull);

        final record = await store.readMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'plan',
          aggregateId: 'plan-1',
        );
        expect(
          record!.syncStatus,
          PlanningMutationSyncStatus.accepted,
          reason: 'the stale attempt must not have overwritten anything',
        );
        expect(record.localRevision, 2);

        // clearMutation mirrors the same contract: a matching revision
        // deletes, a stale one leaves the row untouched.
        final staleClear = await store.clearMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'plan',
          aggregateId: 'plan-1',
          expectedRevision: 1,
        );
        expect(staleClear, isFalse);
        expect(
          await store.readMutation(
            userId: 'user-1',
            organizationId: 'org-1',
            aggregateType: 'plan',
            aggregateId: 'plan-1',
          ),
          isNotNull,
        );

        final matchingClear = await store.clearMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'plan',
          aggregateId: 'plan-1',
          expectedRevision: 2,
        );
        expect(matchingClear, isTrue);
        expect(
          await store.readMutation(
            userId: 'user-1',
            organizationId: 'org-1',
            aggregateType: 'plan',
            aggregateId: 'plan-1',
          ),
          isNull,
        );
      },
    );
  });

  group('PlanningMutationStore missing-record handling (D4, in-flight '
      'create cancellation)', () {
    // docs/specs/2026-08-06-in-flight-create-cancellation.md D4:
    // saveSyncAttemptResult and retryMutation must report "did not apply"
    // (the same vocabulary D3 already established for a stale revision)
    // rather than throw when the target row does not exist -- a row can
    // vanish for the ordinary reason that the user deleted the item while
    // a sync was awaiting the backend for it (ADR-028 D10 collapse).
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('saveSyncAttemptResult against a nonexistent aggregate returns null '
        'instead of throwing', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      // No record ever created for this aggregate -- readMutation would
      // return null.
      final result = await store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'ghost-plan',
        syncStatus: PlanningMutationSyncStatus.accepted,
        expectedRevision: 1,
      );
      expect(result, isNull);
    });

    test('retryMutation against a nonexistent aggregate returns false instead '
        'of throwing', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      final result = await store.retryMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'ghost-plan',
      );
      expect(result, isFalse);
    });

    test('saveSyncAttemptResult and retryMutation against an EXISTING record '
        'are unchanged -- they still apply and report success, including the '
        'ADR-030 revision conditioning', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      // saveSyncAttemptResult: matching revision still applies and
      // returns the new revision, exactly as before D4.
      final applied = await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.failedDependency,
        expectedRevision: 1,
      );
      expect(applied, 2);

      // retryMutation: an existing record is reset to pending and
      // reports true.
      final retried = await store.retryMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(retried, isTrue);

      final record = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(record!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(record.errorCode, isNull);
    });
  });

  group('PlanningMutationStore content folds reset status (ADR-030 '
      'follow-up)', () {
    // ADR-030 "Known Follow-Up": a fold that carries an existing row
    // forward with copyWith must not carry the row's CURRENT syncStatus
    // along with it. The important case is the ADR-019 durable-marker
    // window -- the row is `accepted` (backend confirmed, not yet cleared)
    // -- and a further local edit lands in that same row. New local intent
    // is by definition unsent, so folding it in must reset the row to
    // `pending` (and drop any stale error left by a prior attempt), or a
    // later sync run's accepted-durable-marker branch will skip the remote
    // send and reconcile the newer, never-sent content as if the backend
    // already had it.
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('recordPlanEdit folding onto an accepted-but-uncleared planCreate '
        'resets the row to pending with the newer content', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );

      // Simulate the ADR-019 durable-marker window: the backend accepted
      // this create, but the row has not been cleared yet (e.g. a crash
      // between accept and clear -- LF-1).
      await store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.planCreate.aggregateType,
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );
      final accepted = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(accepted!.syncStatus, PlanningMutationSyncStatus.accepted);

      // The user edits the same plan while the row is still marked
      // accepted -- new, unsent content landing on it.
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service',
          description: 'Edited after acceptance',
        ),
      );

      final afterFold = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );

      expect(
        afterFold!.syncStatus,
        PlanningMutationSyncStatus.pending,
        reason:
            'new local intent is unsent by definition; a row still '
            'labelled accepted would make a later sync skip sending it',
      );
      expect(afterFold.description, 'Edited after acceptance');
    });

    test(
      'recordSessionRename folding onto an accepted-but-uncleared '
      'sessionCreate resets the row to pending with the newer name',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordSessionCreate(
          context: context,
          draft: const PlanningSessionCreateMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            slug: 'welcome',
            name: 'Welcome',
            position: 10,
          ),
        );
        await store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.sessionCreate.aggregateType,
          aggregateId: 'session-1',
          syncStatus: PlanningMutationSyncStatus.accepted,
        );

        await store.recordSessionRename(
          context: context,
          draft: const PlanningSessionRenameMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            name: 'Welcome Team',
          ),
        );

        final afterFold = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'session',
          aggregateId: 'session-1',
        );

        expect(afterFold!.syncStatus, PlanningMutationSyncStatus.pending);
        expect(afterFold.name, 'Welcome Team');
      },
    );

    test('a delete collapsing into an accepted-but-uncleared session reorder '
        'resets that row to pending with the trimmed sibling list', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordSessionReorder(
        context: context,
        draft: const PlanningSessionReorderMutationDraft(
          planId: 'plan-1',
          orderedSessionIds: ['session-1', 'session-2', 'session-3'],
          baseVersion: 4,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.sessionReorder.aggregateType,
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      // session-2 already exists remotely (no pending sessionCreate for
      // it), so this takes the ordinary delete path, which folds the
      // removal into the still-accepted reorder row via
      // _removeSessionFromPendingReorder.
      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-1',
          baseVersion: 4,
        ),
      );

      final reorderAfter = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session_order',
        aggregateId: 'plan-1',
      );

      expect(reorderAfter!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(
        reorderAfter.orderedSiblingIds,
        orderedEquals(const ['session-1', 'session-3']),
      );
    });

    test(
      'a delete collapsing into an accepted-but-uncleared session-item '
      'reorder resets that row to pending with the trimmed sibling list',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordSessionItemReorder(
          context: context,
          draft: const PlanningSessionItemReorderMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            orderedSessionItemIds: ['item-1', 'item-2', 'item-3'],
            baseVersion: 4,
          ),
        );
        await store.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: PlanningMutationKind.sessionItemReorder.aggregateType,
          aggregateId: 'session-1',
          syncStatus: PlanningMutationSyncStatus.accepted,
        );

        await store.recordSessionItemDelete(
          context: context,
          draft: const PlanningSessionItemDeleteMutationDraft(
            sessionItemId: 'item-2',
            sessionId: 'session-1',
            planId: 'plan-1',
            baseVersion: 4,
          ),
        );

        final reorderAfter = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'session_item_order',
          aggregateId: 'session-1',
        );

        expect(reorderAfter!.syncStatus, PlanningMutationSyncStatus.pending);
        expect(
          reorderAfter.orderedSiblingIds,
          orderedEquals(const ['item-1', 'item-3']),
        );
      },
    );

    test('a stale error left by a failed attempt does not survive a content '
        'fold', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.planCreate.aggregateType,
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
        errorMessage: 'base_version_conflict',
      );

      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service',
          description: 'Edited after failure',
        ),
      );

      final afterFold = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );

      expect(afterFold!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(afterFold.errorCode, isNull);
      expect(afterFold.errorMessage, isNull);
      expect(afterFold.description, 'Edited after failure');
    });

    test('saveSyncAttemptResult transitioning to accepted clears a stale error '
        'left by a prior failed attempt, even with no content fold in between '
        '(M3, PR #64 review)', () async {
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.planCreate.aggregateType,
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
        errorMessage: 'base_version_conflict',
      );

      // Retried and accepted -- exactly the shape
      // PlanningMutationSyncController._run's accepted-marker write uses:
      // no errorCode/errorMessage argument at all.
      await store.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.planCreate.aggregateType,
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      final record = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(record!.syncStatus, PlanningMutationSyncStatus.accepted);
      expect(record.errorCode, isNull);
      expect(record.errorMessage, isNull);
    });

    test(
      'two concurrent saveSyncAttemptResult calls with no expectedRevision '
      'do not lose an increment to a stale Dart-side read (M2, PR #64 '
      'review) -- this exercises DriftPlanningMutationStore directly, '
      'without the BudgetedPlanningMutationStore queue that serialises it '
      'in production, because the atomicity must not depend on that caller',
      () async {
        const context = PlanningMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        await store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        );

        // Both calls are the ungated shape the sync controller's
        // failure-status write uses (no expectedRevision): a Dart-side
        // read-then-write would let both read the same pre-write revision
        // and each apply their own +1 on top of it, silently discarding one
        // of the two increments (or worse, regressing the counter if a
        // third write had already landed in between).
        await Future.wait([
          store.saveSyncAttemptResult(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: 'plan',
            aggregateId: 'plan-1',
            syncStatus: PlanningMutationSyncStatus.failedDependency,
            errorCode: PlanningMutationSyncErrorCode.dependencyBlocked,
          ),
          store.saveSyncAttemptResult(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: 'plan',
            aggregateId: 'plan-1',
            syncStatus: PlanningMutationSyncStatus.pending,
          ),
        ]);

        final record = await store.readMutation(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'plan',
          aggregateId: 'plan-1',
        );
        expect(
          record!.localRevision,
          3,
          reason:
              'started at 1 (the create); two concurrent unguarded status '
              'writes must both be reflected, landing on 3 -- not 2, which '
              'would mean one write silently lost its increment to a stale '
              'Dart-side read',
        );
      },
    );
  });

  group('recordPlanDelete (spec D5)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;
    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );
    const draft = PlanningPlanDeleteMutationDraft(
      planId: 'plan-1',
      baseVersion: 2,
      baseContentVersion: 5,
      originSnapshot: {'name': 'Sunday Service'},
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await database.close();
    });

    Future<List<PlanningMutationRecord>> all() =>
        store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

    Future<void> seedChildren() async {
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-new',
          planId: 'plan-1',
          slug: 'new',
          name: 'New',
          position: 3,
        ),
      );
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          name: 'Renamed',
          baseVersion: 1,
        ),
      );
      await store.recordSessionReorder(
        context: context,
        draft: const PlanningSessionReorderMutationDraft(
          planId: 'plan-1',
          orderedSessionIds: ['session-2', 'session-1'],
          baseVersion: 2,
        ),
      );
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-new',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song',
          position: 1,
          baseVersion: 1,
        ),
      );
      await store.recordSessionItemReorder(
        context: context,
        draft: const PlanningSessionItemReorderMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-1',
          orderedSessionItemIds: ['item-b', 'item-a'],
          baseVersion: 1,
        ),
      );
      // A child of ANOTHER plan must never be touched.
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-x',
          planId: 'plan-2',
          name: 'Other plan',
          baseVersion: 1,
        ),
      );
    }

    test('(d) a synced plan gets a pending delete with the draft bases, a '
        'fresh order key, and loses its not-yet-sent child rows', () async {
      await seedChildren();
      final maxKeyBefore = (await all())
          .map((record) => record.orderKey)
          .reduce((a, b) => a > b ? a : b);

      await store.recordPlanDelete(context: context, draft: draft);

      final records = await all();
      expect(records.map((record) => record.aggregateId), [
        'session-x',
        'plan-1',
      ]);
      final delete = records.last;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.syncStatus, PlanningMutationSyncStatus.pending);
      expect(delete.baseVersion, 2);
      expect(delete.baseContentVersion, 5);
      expect(delete.originSnapshot, {'name': 'Sunday Service'});
      expect(delete.orderKey, greaterThan(maxKeyBefore));
    });

    test(
      '(d) in-flight child rows (sending/accepted/cancelling) survive',
      () async {
        await seedChildren();
        await store.saveSyncAttemptResult(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'session',
          aggregateId: 'session-new',
          syncStatus: PlanningMutationSyncStatus.sending,
        );
        await store.saveSyncAttemptResult(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: 'session_item',
          aggregateId: 'item-new',
          syncStatus: PlanningMutationSyncStatus.accepted,
        );

        await store.recordPlanDelete(context: context, draft: draft);

        expect((await all()).map((record) => record.aggregateId).toSet(), {
          'session-new',
          'item-new',
          'session-x',
          'plan-1',
        });
      },
    );

    test(
      '(d) over a pending planEdit keeps the edit\'s base version',
      () async {
        await store.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-1',
            name: 'Edited',
            baseVersion: 1,
            originSnapshot: {'name': 'Before Edit'},
          ),
        );

        await store.recordPlanDelete(context: context, draft: draft);

        final delete = (await all()).single;
        expect(delete.kind, PlanningMutationKind.planDelete);
        expect(delete.baseVersion, 1);
        expect(delete.baseContentVersion, 5);
        expect(delete.originSnapshot, {'name': 'Before Edit'});
      },
    );

    test('(a) a never-sent planCreate collapses with every child row, in '
        'any status', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-1',
          name: 'Local',
        ),
      );
      await seedChildren();
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-new',
        syncStatus: PlanningMutationSyncStatus.sending,
      );

      await store.recordPlanDelete(context: context, draft: draft);

      expect((await all()).map((record) => record.aggregateId), ['session-x']);
    });

    test('(b) a sending planCreate becomes a cancelling tombstone', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-1',
          name: 'Local',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.sending,
      );

      await store.recordPlanDelete(context: context, draft: draft);

      final tombstone = (await all()).single;
      expect(tombstone.kind, PlanningMutationKind.planCreate);
      expect(tombstone.syncStatus, PlanningMutationSyncStatus.cancelling);
    });

    test('(c) an accepted planCreate becomes a pending delete based on the '
        'fresh plan', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-1',
          name: 'Local',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 1,
        ),
      );

      final delete = (await all()).single;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.syncStatus, PlanningMutationSyncStatus.pending);
      expect(delete.baseVersion, 1);
      expect(delete.baseContentVersion, 1);
    });

    test('baseContentVersion persists across a database reopen', () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning-mutation-store-test-plan-delete',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final dbFile = File(p.join(directory.path, 'planning.sqlite'));

      final firstDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      final firstStore = DriftPlanningMutationStore(
        database: firstDatabase,
        localStore: DriftPlanningLocalStore(firstDatabase),
      );

      await firstStore.recordPlanDelete(context: context, draft: draft);
      await firstDatabase.close();

      final secondDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      addTearDown(secondDatabase.close);
      final secondStore = DriftPlanningMutationStore(
        database: secondDatabase,
        localStore: DriftPlanningLocalStore(secondDatabase),
      );

      final pending = await secondStore.readPendingMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(pending, hasLength(1));
      expect(pending.single.aggregateId, 'plan-1');
      expect(pending.single.kind, PlanningMutationKind.planDelete);
      expect(pending.single.baseVersion, 2);
      expect(pending.single.baseContentVersion, 5);
    });

    test('deleting a synced session drops its not-yet-sent item rows, keeps '
        'in-flight ones, and takes a fresh order key (spec D6)', () async {
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          name: 'Renamed',
          baseVersion: 3,
        ),
      );
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-pending',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song',
          position: 1,
          baseVersion: 3,
        ),
      );
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-sending',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-2',
          songTitle: 'Song 2',
          position: 2,
          baseVersion: 3,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session_item',
        aggregateId: 'item-sending',
        syncStatus: PlanningMutationSyncStatus.sending,
      );
      await store.recordSessionItemReorder(
        context: context,
        draft: const PlanningSessionItemReorderMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          orderedSessionItemIds: ['item-b', 'item-a'],
          baseVersion: 3,
        ),
      );
      final renameKey = (await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      ))!.orderKey;

      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          baseVersion: 3,
        ),
      );

      final records = await store.readAllMutations(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(records.map((record) => record.aggregateId).toList(), [
        'item-sending',
        'session-1',
      ]);
      final delete = records.last;
      expect(delete.kind, PlanningMutationKind.sessionDelete);
      expect(delete.baseVersion, 3);
      expect(delete.orderKey, greaterThan(renameKey));
    });
  });

  group('applyAcceptedWriteEffects (spec D7, D8)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;
    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      await localStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026),
            version: 2,
            contentVersion: 5,
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            position: 1,
            name: 'S',
            version: 3,
          ),
        ],
        items: const [],
        refreshedAt: DateTime.utc(2026),
      );
    });

    tearDown(() async {
      await database.close();
    });

    PlanningMutationRecord accepted(
      PlanningMutationKind kind, {
      String aggregateId = 'item-9',
      int? version,
      int? planContentVersion,
    }) => PlanningMutationRecord(
      aggregateId: aggregateId,
      organizationId: 'org-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      baseVersion: version,
      acceptedPlanContentVersion: planContentVersion,
      kind: kind,
      syncStatus: PlanningMutationSyncStatus.pending,
      orderKey: 99,
      updatedAt: DateTime.utc(2026),
    );

    Future<PlanningMutationRecord?> planRow() => store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    );

    Future<int?> projectionContentVersion() async =>
        (await localStore.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
        ))?.plan.contentVersion;

    test('rule 1: a contiguous own child write rebases the pending plan '
        'delete and the projection', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: true,
      );

      expect((await planRow())!.baseContentVersion, 6);
      expect(await projectionContentVersion(), 6);
    });

    test('rule 1: a gap (foreign write interleaved) changes nothing', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 7,
        ),
        remoteResponse: true,
      );

      expect((await planRow())!.baseContentVersion, 5);
      expect(await projectionContentVersion(), 5);
    });

    test(
      'rule 1 is idempotent and ignores planEdit/planCreate responses',
      () async {
        await store.recordPlanDelete(
          context: context,
          draft: const PlanningPlanDeleteMutationDraft(
            planId: 'plan-1',
            baseVersion: 2,
            baseContentVersion: 5,
          ),
        );
        final child = accepted(
          PlanningMutationKind.sessionItemDelete,
          version: 4,
          planContentVersion: 6,
        );
        for (var i = 0; i < 2; i += 1) {
          await store.applyAcceptedWriteEffects(
            userId: 'user-1',
            organizationId: 'org-1',
            accepted: child,
            remoteResponse: true,
          );
        }
        expect((await planRow())!.baseContentVersion, 6);

        // A planEdit response whose content_version happens to be base + 1
        // must not rebase anything (planEdit does not bump content).
        await store.applyAcceptedWriteEffects(
          userId: 'user-1',
          organizationId: 'org-1',
          accepted: accepted(
            PlanningMutationKind.planEdit,
            aggregateId: 'plan-1',
            version: 9,
            planContentVersion: 7,
          ),
          remoteResponse: true,
        );
        expect((await planRow())!.baseContentVersion, 6);
        expect(await projectionContentVersion(), 6);
      },
    );

    test('rule 2: a contiguous own planEdit rebases the delete that '
        'overwrote it', () async {
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Edited',
          baseVersion: 2,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.sending,
      );
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.planEdit,
          aggregateId: 'plan-1',
          version: 3,
          planContentVersion: 5,
        ),
        remoteResponse: true,
      );

      final delete = (await planRow())!;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.baseVersion, 3);
      expect(delete.baseContentVersion, 5);
    });

    test('rule 3: a contiguous own item write rebases a pending session '
        'delete', () async {
      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          baseVersion: 3,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: true,
      );

      final delete = (await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      ))!;
      expect(delete.baseVersion, 4);
    });

    test('remoteResponse: false never rebases', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: false,
      );

      expect((await planRow())!.baseContentVersion, 5);
      expect(await projectionContentVersion(), 5);
    });

    test('an in-flight delete row is never rebased', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: true,
      );

      expect((await planRow())!.baseContentVersion, 5);
    });

    test('D8: an accepted planDelete purges every remaining child row, in '
        'any status, and nothing of other plans', () async {
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          name: 'R',
          baseVersion: 3,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-x',
          planId: 'plan-2',
          name: 'Other',
          baseVersion: 1,
        ),
      );
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.planDelete,
          aggregateId: 'plan-1',
          version: 2,
        ),
        remoteResponse: false,
      );

      expect(
        (await store.readAllMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        )).map((record) => record.aggregateId).toSet(),
        {'session-x', 'plan-1'},
      );
    });

    test('D8: an accepted sessionDelete purges its item rows', () async {
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song',
          position: 1,
          baseVersion: 3,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session_item',
        aggregateId: 'item-1',
        syncStatus: PlanningMutationSyncStatus.failedDependency,
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionDelete,
          aggregateId: 'session-1',
          version: 3,
        ),
        remoteResponse: true,
      );

      expect(
        await store.readAllMutations(userId: 'user-1', organizationId: 'org-1'),
        isEmpty,
      );
    });
  });
}
