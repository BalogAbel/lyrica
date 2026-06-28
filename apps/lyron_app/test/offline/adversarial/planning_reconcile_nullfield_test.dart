import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// LF-8: corrupt backend-accepted mutations must not be silently coerced
/// into empty-string/zero projection rows. A null on a field that is
/// REQUIRED for a valid create means the mutation itself is corrupt, and
/// the reconciler must surface that loudly (throw) instead of writing a
/// placeholder row that looks like legitimate data.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningMutationReconciler (LF-8 null-field corruption)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late PlanningMutationReconciler reconciler;

    const userId = 'user-1';
    const organizationId = 'org-1';

    final testContext = ActivePlanningReadContext(
      userId: userId,
      organizationId: organizationId,
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      reconciler = PlanningMutationReconciler(localStore: () => localStore);

      await localStore.replaceActiveProjection(
        userId: userId,
        organizationId: organizationId,
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'team-rehearsal',
            name: 'Team Rehearsal',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            slug: 'warm-up',
            position: 10,
            name: 'Warm-Up',
          ),
        ],
        items: const [],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'sessionItemCreateSong with null songId throws ReconcileFieldError',
      () async {
        final record = PlanningMutationRecord(
          aggregateId: 'item-corrupt',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          planId: 'plan-1',
          sessionId: 'session-1',
          // songId is intentionally null: a corrupt create mutation.
          songId: null,
          songTitle: 'Corrupt Song',
          position: 20,
          baseVersion: 1,
        );

        expect(
          () => reconciler.reconcile(testContext, record),
          throwsA(isA<ReconcileFieldError>()),
        );
      },
    );

    test(
      'sessionItemCreateSong with null sessionId throws ReconcileFieldError',
      () async {
        final record = PlanningMutationRecord(
          aggregateId: 'item-corrupt-2',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          planId: 'plan-1',
          // sessionId is intentionally null: a corrupt create mutation.
          sessionId: null,
          songId: 'song-9',
          songTitle: 'Corrupt Song',
          position: 20,
          baseVersion: 1,
        );

        expect(
          () => reconciler.reconcile(testContext, record),
          throwsA(isA<ReconcileFieldError>()),
        );
      },
    );

    test('sessionCreate with null planId throws ReconcileFieldError', () async {
      final record = PlanningMutationRecord(
        aggregateId: 'session-corrupt',
        organizationId: organizationId,
        kind: PlanningMutationKind.sessionCreate,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        // planId is intentionally null: a corrupt create mutation.
        planId: null,
        slug: 'outro',
        name: 'Outro',
        position: 30,
        baseVersion: 1,
      );

      expect(
        () => reconciler.reconcile(testContext, record),
        throwsA(isA<ReconcileFieldError>()),
      );
    });
  });
}
