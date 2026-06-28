import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// Adversarial coverage for the offline merge in
/// `PlanningLocalReadRepository`: confirms actionable mutations
/// (pending/accepted/failed*/conflict) stay visible over the base
/// projection (LF-4), and partial edits do not blank untouched fields (LF-5).
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningLocalReadRepository merge visibility (adversarial)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore mutationStore;
    late PlanningLocalReadRepository repository;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      repository = PlanningLocalReadRepository(
        store: localStore,
        mutationStore: mutationStore,
        contextReader: () async => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'LF-4: a conflicted planEdit keeps the edited name visible in list and detail',
      () async {
        // arrange: base plan version 1, name "Server Name"
        await localStore.replaceActiveProjection(
          userId: context.userId,
          organizationId: context.organizationId,
          plans: [
            CachedPlanRecord(
              id: 'plan-1',
              slug: 'team-rehearsal',
              name: 'Server Name',
              description: null,
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 4, 11, 10),
            ),
          ],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 11, 10),
        );

        await mutationStore.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-1',
            name: 'Edited Name',
            description: null,
            scheduledFor: null,
            baseVersion: 1,
          ),
        );

        // simulate a conflict on sync
        await mutationStore.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'plan',
          aggregateId: 'plan-1',
          syncStatus: PlanningMutationSyncStatus.conflict,
        );

        // act + assert: list shows the edited name, not the base name
        final plans = await repository.listPlans();
        final listed = plans.firstWhere((p) => p.id == 'plan-1');
        expect(listed.name, equals('Edited Name'));

        // act + assert: detail shows the edited name too
        final detail = await repository.getPlanDetail('plan-1');
        expect(detail.plan.name, equals('Edited Name'));
      },
    );

    test(
      'LF-5: a name-only planEdit preserves base description and scheduledFor',
      () async {
        // arrange: base plan has description + scheduledFor set
        final scheduledFor = DateTime.utc(2026, 5, 1);
        await localStore.replaceActiveProjection(
          userId: context.userId,
          organizationId: context.organizationId,
          plans: [
            CachedPlanRecord(
              id: 'plan-2',
              slug: 'detailed-plan',
              name: 'Original Name',
              description: 'Important description',
              scheduledFor: scheduledFor,
              updatedAt: DateTime.utc(2026, 4, 11, 10),
            ),
          ],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 11, 10),
        );

        // act: mutation only sets name; description/scheduledFor are null on the mutation
        await mutationStore.recordPlanEdit(
          context: context,
          draft: const PlanningPlanEditMutationDraft(
            planId: 'plan-2',
            name: 'Updated Name',
            description: null,
            scheduledFor: null,
            baseVersion: 1,
          ),
        );

        final plans = await repository.listPlans();
        final plan = plans.firstWhere((p) => p.id == 'plan-2');

        expect(plan.name, equals('Updated Name'));
        expect(plan.description, equals('Important description'));
        expect(plan.scheduledFor, equals(scheduledFor));

        final detail = await repository.getPlanDetail('plan-2');
        expect(detail.plan.name, equals('Updated Name'));
        expect(detail.plan.description, equals('Important description'));
        expect(detail.plan.scheduledFor, equals(scheduledFor));
      },
    );
  });
}
