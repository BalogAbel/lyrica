import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningMutationReconciler', () {
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

      // Bootstrap with initial projection
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
          CachedSessionRecord(
            id: 'session-2',
            planId: 'plan-1',
            slug: 'message',
            position: 20,
            name: 'Message',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 10,
            songId: 'song-1',
            songTitle: 'Alpha',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );
    });

    tearDown(() async {
      await database.close();
    });

    group('reconcile (characterization)', () {
      test('planCreate upserts new plan', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'plan-2',
          organizationId: organizationId,
          kind: PlanningMutationKind.planCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          slug: 'new-plan',
          name: 'New Plan',
          description: 'A new plan',
          scheduledFor: DateTime.utc(2026, 5, 1),
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-2',
        );
        expect(detail, isNotNull);
        expect(detail!.plan.id, 'plan-2');
        expect(detail.plan.name, 'New Plan');
        expect(detail.plan.description, 'A new plan');
      });

      test('planEdit updates existing plan', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'plan-1',
          organizationId: organizationId,
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          slug: 'rehearsal-edited',
          name: 'Rehearsal Edited',
          description: 'Updated description',
          baseVersion: 2,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        expect(detail!.plan.name, 'Rehearsal Edited');
        expect(detail.plan.description, 'Updated description');
      });

      test('sessionCreate upserts new session', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'session-3',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          planId: 'plan-1',
          slug: 'outro',
          name: 'Outro',
          position: 30,
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        expect(detail!.sessions.length, 3);
        final newSession = detail.sessions.firstWhere(
          (s) => s.id == 'session-3',
        );
        expect(newSession.name, 'Outro');
      });

      test('sessionRename updates session name', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'session-1',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionRename,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          planId: 'plan-1',
          slug: 'warm-up-new',
          name: 'Warm-Up New',
          position: 10,
          baseVersion: 2,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        final session = detail!.sessions.firstWhere((s) => s.id == 'session-1');
        expect(session.name, 'Warm-Up New');
      });

      test('sessionDelete removes session', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'session-2',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionDelete,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        expect(detail!.sessions.length, 1);
        expect(detail.sessions.first.id, 'session-1');
      });

      test('sessionReorder changes session order', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'session-1', // ignored for reorder
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionReorder,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          planId: 'plan-1',
          orderedSiblingIds: const ['session-2', 'session-1'],
          orderedSiblingPositions: const [10, 20],
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        expect(detail!.sessions[0].id, 'session-2');
        expect(detail.sessions[1].id, 'session-1');
      });

      test('sessionItemCreateSong upserts new item', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'item-2',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          planId: 'plan-1',
          sessionId: 'session-1',
          songId: 'song-3',
          songTitle: 'Gamma',
          position: 20,
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        final session = detail!.sessions.firstWhere((s) => s.id == 'session-1');
        expect(session.items.length, 2);
        final newItem = session.items.firstWhere((i) => i.id == 'item-2');
        expect(newItem.song.title, 'Gamma');
      });

      test('sessionItemDelete removes item', () async {
        final record = PlanningMutationRecord(
          aggregateId: 'item-1',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionItemDelete,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          sessionId: 'session-1',
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        final session = detail!.sessions.firstWhere((s) => s.id == 'session-1');
        expect(session.items.length, 0);
      });

      test('sessionItemReorder changes item order', () async {
        // Seed second item via reconciler create.
        await reconciler.reconcile(
          testContext,
          PlanningMutationRecord(
            aggregateId: 'item-2',
            organizationId: organizationId,
            kind: PlanningMutationKind.sessionItemCreateSong,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 4, 11, 10, 30),
            planId: 'plan-1',
            sessionId: 'session-1',
            songId: 'song-2',
            songTitle: 'Beta',
            position: 20,
            baseVersion: 1,
          ),
        );

        final record = PlanningMutationRecord(
          aggregateId: 'item-1', // ignored for reorder
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionItemReorder,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          sessionId: 'session-1',
          orderedSiblingIds: const ['item-2', 'item-1'],
          orderedSiblingPositions: const [10, 20],
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        final session = detail!.sessions.firstWhere((s) => s.id == 'session-1');
        expect(session.items[0].id, 'item-2');
        expect(session.items[1].id, 'item-1');
      });

      test(
        'sessionItemCreateSong with ordered siblings reorders items',
        () async {
          // Seed second item via reconciler create.
          await reconciler.reconcile(
            testContext,
            PlanningMutationRecord(
              aggregateId: 'item-2',
              organizationId: organizationId,
              kind: PlanningMutationKind.sessionItemCreateSong,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026, 4, 11, 10, 30),
              planId: 'plan-1',
              sessionId: 'session-1',
              songId: 'song-2',
              songTitle: 'Beta',
              position: 20,
              baseVersion: 1,
            ),
          );

          final record = PlanningMutationRecord(
            aggregateId: 'item-3',
            organizationId: organizationId,
            kind: PlanningMutationKind.sessionItemCreateSong,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 4, 11, 11),
            planId: 'plan-1',
            sessionId: 'session-1',
            songId: 'song-3',
            songTitle: 'Gamma',
            position: 15,
            orderedSiblingIds: const ['item-1', 'item-3', 'item-2'],
            orderedSiblingPositions: const [10, 15, 20],
            baseVersion: 1,
          );

          await reconciler.reconcile(testContext, record);

          final detail = await localStore.readPlanDetail(
            userId: userId,
            organizationId: organizationId,
            planId: 'plan-1',
          );
          expect(detail, isNotNull);
          final session = detail!.sessions.firstWhere(
            (s) => s.id == 'session-1',
          );
          expect(session.items.length, 3);
          expect(session.items[0].id, 'item-1');
          expect(session.items[1].id, 'item-3');
          expect(session.items[2].id, 'item-2');
        },
      );

      test('sessionItemDelete with ordered siblings reorders items', () async {
        // Seed second item via reconciler create.
        await reconciler.reconcile(
          testContext,
          PlanningMutationRecord(
            aggregateId: 'item-2',
            organizationId: organizationId,
            kind: PlanningMutationKind.sessionItemCreateSong,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 4, 11, 10, 30),
            planId: 'plan-1',
            sessionId: 'session-1',
            songId: 'song-2',
            songTitle: 'Beta',
            position: 20,
            baseVersion: 1,
          ),
        );

        final record = PlanningMutationRecord(
          aggregateId: 'item-1',
          organizationId: organizationId,
          kind: PlanningMutationKind.sessionItemDelete,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026, 4, 11, 11),
          sessionId: 'session-1',
          orderedSiblingIds: const ['item-2'],
          orderedSiblingPositions: const [10],
          baseVersion: 1,
        );

        await reconciler.reconcile(testContext, record);

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        expect(detail, isNotNull);
        final session = detail!.sessions.firstWhere((s) => s.id == 'session-1');
        expect(session.items.length, 1);
        expect(session.items.first.id, 'item-2');
      });
    });
  });
}
