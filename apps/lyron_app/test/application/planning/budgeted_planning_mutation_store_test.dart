import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('BudgetedPlanningMutationStore', () {
    late PlanningLocalDatabase database;
    late SongCatalogDatabase catalogDatabase;
    late DriftPlanningMutationStore delegate;
    late PlanningStorageAccountant accountant;
    late _RecordingEvictor evictor;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      catalogDatabase = SongCatalogDatabase.inMemory();
      delegate = DriftPlanningMutationStore(
        database: database,
        localStore: DriftPlanningLocalStore(database),
      );
      accountant = PlanningStorageAccountant(database);
      evictor = _RecordingEvictor(
        SongCatalogEvictor(
          database: catalogDatabase,
          accountant: CatalogStorageAccountant(catalogDatabase),
        ),
      );
    });

    tearDown(() async {
      await database.close();
      await catalogDatabase.close();
    });

    BudgetedPlanningMutationStore storeWithBudget(LocalStorageBudget budget) {
      return BudgetedPlanningMutationStore(
        delegate: delegate,
        accountant: accountant,
        evictor: evictor,
        budget: budget,
      );
    }

    test('allows writes below the refuse threshold', () async {
      final store = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      expect(
        await store.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        hasLength(1),
      );
    });

    test('refuses a new write once the mutation budget is exhausted, without '
        'evicting anything', () async {
      final store = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );

      await expectLater(
        () => store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        ),
        throwsA(isA<PlanningMutationBudgetExceededException>()),
      );

      // Catalog eviction cannot free mutation budget, so attempting it here
      // would destroy cached data for no benefit.
      expect(evictor.calls, 0);
    });

    test('a refused write leaves existing pending mutations untouched, and '
        'discard still works', () async {
      final permissive = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1000000),
      );
      await permissive.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      final exhausted = storeWithBudget(
        const LocalStorageBudget(mutationRefuseBytes: 1),
      );
      await expectLater(
        () => exhausted.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-2',
            slug: 'midweek-service',
            name: 'Midweek Service',
          ),
        ),
        throwsA(isA<PlanningMutationBudgetExceededException>()),
      );

      expect(
        await exhausted.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        hasLength(1),
      );

      // A full store must always be drainable: guarding clearMutation would
      // make the budget a trap with no way out.
      await exhausted.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(
        await exhausted.readPendingMutations(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        isEmpty,
      );
    });

    test(
      'propagates a domain slug conflict without eviction or retry',
      () async {
        final store = storeWithBudget(
          const LocalStorageBudget(mutationRefuseBytes: 1000000),
        );
        await store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        );

        await expectLater(
          () => store.recordPlanCreate(
            context: context,
            draft: const PlanningPlanCreateMutationDraft(
              planId: 'plan-2',
              slug: 'weekend-service',
              name: 'Duplicate',
            ),
          ),
          throwsA(isA<LocalPlanningSlugConflictException>()),
        );
        expect(evictor.calls, 0);
      },
    );
  });
}

/// Counts eviction calls so the tests can assert that eviction happens only
/// on a storage failure, never on a budget refusal.
class _RecordingEvictor implements SongCatalogEvictor {
  _RecordingEvictor(this._delegate);

  final SongCatalogEvictor _delegate;
  int calls = 0;

  @override
  Future<int> evictDroppable() {
    calls += 1;
    return _delegate.evictDroppable();
  }
}
