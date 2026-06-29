import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// LF-T6 (characterization probe): [PlanningMutationReconciler] stamps
/// reconciled records with whatever clock it is given. By default that is
/// the device wall clock (`DateTime.now().toUtc()`), which means a device
/// with a skewed clock will write skewed timestamps into the local
/// projection -- there is no server-clock anchor to correct it.
///
/// This probe documents that current behaviour using the injectable `now`
/// seam added to the reconciler: a deliberately skewed clock flows through
/// untouched into the upserted plan's `updatedAt`. Building an actual
/// server-clock anchor (validating/correcting device time against a
/// trusted source) is OUT OF SCOPE and deferred.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningMutationReconciler (LF-T6 clock-skew probe)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;

    const userId = 'user-1';
    const organizationId = 'org-1';

    final testContext = ActivePlanningReadContext(
      userId: userId,
      organizationId: organizationId,
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);

      await localStore.replaceActiveProjection(
        userId: userId,
        organizationId: organizationId,
        plans: const [],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('reconcile stamps records with the injected clock; device skew '
        'flows through (LF-T6 probe)', () async {
      final skewed = DateTime.utc(2030, 1, 1);
      final reconciler = PlanningMutationReconciler(
        localStore: () => localStore,
        now: () => skewed,
      );

      final record = PlanningMutationRecord(
        aggregateId: 'plan-skewed',
        organizationId: organizationId,
        kind: PlanningMutationKind.planCreate,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        // The record's own updatedAt is irrelevant to this probe: the
        // reconciler always restamps with its injected clock.
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        slug: 'skewed-plan',
        name: 'Skewed Plan',
        baseVersion: 1,
      );

      await reconciler.reconcile(testContext, record);

      final detail = await localStore.readPlanDetail(
        userId: userId,
        organizationId: organizationId,
        planId: 'plan-skewed',
      );

      expect(detail, isNotNull);
      // Device clock flows through untouched: no server-clock anchor
      // corrects or rejects a skewed timestamp.
      expect(detail!.plan.updatedAt, skewed);
    });
  });
}
