import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningStorageAccountant', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore mutationStore;
    late PlanningStorageAccountant accountant;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      accountant = PlanningStorageAccountant(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('reports zero for an empty store', () async {
      expect(
        await accountant.measureMutationBytes(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        0,
      );
      expect(
        await accountant.measureMutationCount(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        0,
      );
    });

    test('grows with mutation content and shrinks when cleared', () async {
      await mutationStore.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      final afterSmall = await accountant.measureMutationBytes(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(afterSmall, greaterThan(0));

      await mutationStore.recordPlanCreate(
        context: context,
        draft: PlanningPlanCreateMutationDraft(
          planId: 'plan-2',
          slug: 'midweek-service',
          name: 'Midweek Service',
          description: 'x' * 5000,
        ),
      );
      final afterLarge = await accountant.measureMutationBytes(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      // A 5000-character description must actually register: an accountant
      // that only counted rows would be blind to exactly the payloads that
      // make the store grow.
      expect(afterLarge - afterSmall, greaterThan(5000));

      expect(
        await accountant.measureMutationCount(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        2,
      );

      await mutationStore.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-2',
      );
      expect(
        await accountant.measureMutationBytes(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        afterSmall,
      );
    });

    test('scopes measurement to the given user and organization', () async {
      await mutationStore.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      expect(
        await accountant.measureMutationBytes(
          userId: 'other-user',
          organizationId: context.organizationId,
        ),
        0,
      );
    });

    test('measures the projection separately from mutations', () async {
      expect(await accountant.measureProjectionBytes(), 0);

      await localStore.replaceActiveProjection(
        userId: context.userId,
        organizationId: context.organizationId,
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            name: 'Weekend Service',
            description: 'x' * 3000,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            position: 1,
            name: 'Morning Session',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 1,
            songId: 'song-1',
            songTitle: 'Amazing Grace',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 7, 30),
      );

      // A 3000-character plan description must actually register: this is
      // only true if the payload-bearing columns of every measured table
      // are summed, not just the owner row.
      expect(await accountant.measureProjectionBytes(), greaterThan(3000));
    });
  });
}
