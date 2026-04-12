import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('PlanningMutationStore', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      await database.close();
    });

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
}
