import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:path/path.dart' as p;

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
              .having((record) => record.aggregateId, 'aggregateId', 'session-local-1')
              .having((record) => record.kind, 'kind', PlanningMutationKind.sessionCreate)
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

    test('persists sync error details and allows retrying a failed mutation', () async {
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
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
        errorMessage: 'base_version_conflict',
      );

      final failedRecord = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateId: 'plan-1',
      );

      expect(failedRecord?.syncStatus, PlanningMutationSyncStatus.conflict);
      expect(failedRecord?.errorCode, PlanningMutationSyncErrorCode.conflict);
      expect(failedRecord?.errorMessage, 'base_version_conflict');

      await store.retryMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateId: 'plan-1',
      );

      final retriedRecord = await store.readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateId: 'plan-1',
      );

      expect(retriedRecord?.syncStatus, PlanningMutationSyncStatus.pending);
      expect(retriedRecord?.errorCode, isNull);
      expect(retriedRecord?.errorMessage, isNull);
    });
  });
}
