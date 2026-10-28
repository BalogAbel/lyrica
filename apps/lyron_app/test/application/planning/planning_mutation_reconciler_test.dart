import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/session_item_key_edit.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
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

    group('reconcile sessionItemKeyEdit (S3 PR 2, PS15)', () {
      PlanningMutationRecord keyRecord({
        int? baseVersion = 2,
        SessionItemKeyEdit? keyEdit,
        int? keyBaseTranspose,
        int? keyBaseCapo,
      }) => PlanningMutationRecord(
        aggregateId: 'item-1',
        organizationId: organizationId,
        planId: 'plan-1',
        sessionId: 'session-1',
        kind: PlanningMutationKind.sessionItemKeyEdit,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        // A response-shaped record carries the RETURNED item version in
        // baseVersion and the server key in keyEdit (all set/clear). A
        // crash-resumed `accepted` marker is the unsent shape instead.
        baseVersion: baseVersion,
        keyBaseTranspose: keyBaseTranspose,
        keyBaseCapo: keyBaseCapo,
        keyEdit:
            keyEdit ??
            SessionItemKeyEdit(
              transposeMode: SessionItemKeyFieldMode.set,
              transpose: -3,
              capoMode: SessionItemKeyFieldMode.clear,
            ),
      );

      Future<SessionItemSummary> projectedItem() async {
        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-1',
        );
        return detail!.sessions
            .firstWhere((session) => session.id == 'session-1')
            .items
            .firstWhere((item) => item.id == 'item-1');
      }

      test('a failed post-sync refresh still gives the projected item the '
          'returned version and the server key', () async {
        await reconciler.reconcile(testContext, keyRecord());

        final item = await projectedItem();
        expect(item.version, 2);
        expect(item.planTranspose, -3);
        expect(item.planCapo, isNull);
      });

      test(
        'a set capo and a cleared transpose are written as returned',
        () async {
          await reconciler.reconcile(
            testContext,
            keyRecord(
              baseVersion: 5,
              keyEdit: SessionItemKeyEdit(
                transposeMode: SessionItemKeyFieldMode.clear,
                capoMode: SessionItemKeyFieldMode.set,
                capo: 4,
              ),
            ),
          );

          final item = await projectedItem();
          expect(item.version, 5);
          expect(item.planTranspose, isNull);
          expect(item.planCapo, 4);
        },
      );

      test(
        'a crash-resumed marker (unsent shape, a kept field) takes the '
        'edit applied over its base values, never a nulled kept field',
        () async {
          await reconciler.reconcile(
            testContext,
            keyRecord(
              baseVersion: 4,
              keyBaseTranspose: 1,
              keyBaseCapo: 2,
              keyEdit: SessionItemKeyEdit(
                transposeMode: SessionItemKeyFieldMode.set,
                transpose: 3,
                capoMode: SessionItemKeyFieldMode.keep,
              ),
            ),
          );

          final item = await projectedItem();
          expect(item.version, 4);
          expect(item.planTranspose, 3);
          expect(item.planCapo, 2, reason: 'kept: the base value, not null');
        },
      );

      test('a crash-resumed marker with a kept transpose and a cleared capo '
          'keeps the base transpose and clears the capo', () async {
        await reconciler.reconcile(
          testContext,
          keyRecord(
            baseVersion: 6,
            keyBaseTranspose: 5,
            keyBaseCapo: 2,
            keyEdit: SessionItemKeyEdit(
              transposeMode: SessionItemKeyFieldMode.keep,
              capoMode: SessionItemKeyFieldMode.clear,
            ),
          ),
        );

        final item = await projectedItem();
        expect(item.version, 6);
        expect(item.planTranspose, 5);
        expect(item.planCapo, isNull);
      });

      test('a record without its returned version is a corrupt mutation '
          '(LF-8)', () async {
        await expectLater(
          reconciler.reconcile(testContext, keyRecord(baseVersion: null)),
          throwsA(isA<ReconcileFieldError>()),
        );
      });
    });

    group('reconcile planDelete and plan content version', () {
      test('planDelete removes the plan, its sessions and its items', () async {
        await reconciler.reconcile(
          testContext,
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: organizationId,
            kind: PlanningMutationKind.planDelete,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        );

        expect(
          await localStore.readPlanDetail(
            userId: userId,
            organizationId: organizationId,
            planId: 'plan-1',
          ),
          isNull,
        );
      });

      test('planCreate seeds contentVersion from the accepted response '
          '(spec D4)', () async {
        await reconciler.reconcile(
          testContext,
          PlanningMutationRecord(
            aggregateId: 'plan-2',
            organizationId: organizationId,
            kind: PlanningMutationKind.planCreate,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 4, 11, 11),
            slug: 'new-plan',
            name: 'New Plan',
            baseVersion: 1,
            acceptedPlanContentVersion: 1,
          ),
        );

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-2',
        );
        expect(detail!.plan.contentVersion, 1);
      });

      test('planEdit never seeds contentVersion for a plan that is not in '
          'the projection (review gate 2, I7)', () async {
        // A planEdit response's content_version can include foreign writes;
        // upsertSyncedPlan takes the passed value for a brand-new row.
        await reconciler.reconcile(
          testContext,
          PlanningMutationRecord(
            aggregateId: 'plan-3',
            organizationId: organizationId,
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 4, 11, 11),
            slug: 'other-plan',
            name: 'Other Plan',
            baseVersion: 2,
            acceptedPlanContentVersion: 9,
          ),
        );

        final detail = await localStore.readPlanDetail(
          userId: userId,
          organizationId: organizationId,
          planId: 'plan-3',
        );
        expect(detail!.plan.contentVersion, isNull);
      });
    });
  });

  group('PlanningMutationReconciler F1 gate', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late PlanningMutationReconciler reconciler;

    const userId = 'user-1';
    const organizationId = 'org-1';

    final testContext = ActivePlanningReadContext(
      userId: userId,
      organizationId: organizationId,
    );

    // plan-1 v2 at content version [contentVersion], session-1 v2 'S' (or
    // [sessionName] at [sessionVersion]), item-1 at [itemVersion].
    Future<void> seed({
      int contentVersion = 4,
      int sessionVersion = 2,
      String sessionName = 'S',
      int itemVersion = 1,
    }) => localStore.replaceActiveProjection(
      userId: userId,
      organizationId: organizationId,
      plans: [
        CachedPlanRecord(
          id: 'plan-1',
          slug: 'plan-1',
          name: 'Plan',
          description: null,
          scheduledFor: null,
          updatedAt: DateTime.utc(2026, 4, 11, 10),
          version: 2,
          contentVersion: contentVersion,
        ),
      ],
      sessions: [
        CachedSessionRecord(
          id: 'session-1',
          planId: 'plan-1',
          position: 1,
          name: sessionName,
          version: sessionVersion,
        ),
      ],
      items: [
        CachedSessionItemRecord(
          id: 'item-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          position: 1,
          songId: 'song-1',
          songTitle: 'Alpha',
          version: itemVersion,
        ),
      ],
      refreshedAt: DateTime.utc(2026, 4, 11, 10),
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      reconciler = PlanningMutationReconciler(localStore: () => localStore);
      await seed();
    });

    tearDown(() async {
      await database.close();
    });

    Future<PlanDetail> detail() async => (await localStore.readPlanDetail(
      userId: userId,
      organizationId: organizationId,
      planId: 'plan-1',
    ))!;

    PlanningMutationRecord renameRecord({
      required int baseVersion,
      String name = 'Mine',
      int? acceptedPlanContentVersion,
    }) => PlanningMutationRecord(
      aggregateId: 'session-1',
      organizationId: organizationId,
      planId: 'plan-1',
      kind: PlanningMutationKind.sessionRename,
      syncStatus: PlanningMutationSyncStatus.accepted,
      orderKey: 1,
      updatedAt: DateTime.utc(2026, 4, 11, 11),
      name: name,
      baseVersion: baseVersion,
      acceptedPlanContentVersion: acceptedPlanContentVersion,
    );

    test('a rename response at R - 1 reconciles and advances to R', () async {
      await reconciler.reconcile(
        testContext,
        renameRecord(baseVersion: 3, acceptedPlanContentVersion: 5),
      );

      final d = await detail();
      expect(d.sessions.single.name, 'Mine');
      expect(d.sessions.single.version, 3);
      expect(d.plan.contentVersion, 5);
    });

    test('a crash-resumed rename marker does not overwrite a newer projected '
        'session', () async {
      await seed(sessionVersion: 4, sessionName: 'Foreign');

      await reconciler.reconcile(testContext, renameRecord(baseVersion: 2));

      final d = await detail();
      expect(d.sessions.single.name, 'Foreign');
      expect(d.sessions.single.version, 4);
      expect(d.plan.contentVersion, 4);
    });

    test('a crash-resumed rename marker over its own base still '
        'reconciles', () async {
      await reconciler.reconcile(testContext, renameRecord(baseVersion: 2));

      final d = await detail();
      expect(d.sessions.single.name, 'Mine');
      expect(d.sessions.single.version, 2);
      expect(d.plan.contentVersion, 4, reason: 'lag: no R, no advance');
    });

    PlanningMutationRecord planEditRecord({
      required int baseVersion,
      String name = 'Old',
      int? acceptedPlanContentVersion,
    }) => PlanningMutationRecord(
      aggregateId: 'plan-1',
      organizationId: organizationId,
      kind: PlanningMutationKind.planEdit,
      syncStatus: PlanningMutationSyncStatus.accepted,
      orderKey: 1,
      updatedAt: DateTime.utc(2026, 4, 11, 11),
      slug: 'plan-1',
      name: name,
      baseVersion: baseVersion,
      acceptedPlanContentVersion: acceptedPlanContentVersion,
    );

    test('a planEdit older than the projected plan is skipped', () async {
      await reconciler.reconcile(testContext, planEditRecord(baseVersion: 1));

      final d = await detail();
      expect(d.plan.name, 'Plan');
      expect(d.plan.version, 2);
    });

    test('a planEdit response never advances the content version', () async {
      await reconciler.reconcile(
        testContext,
        planEditRecord(
          baseVersion: 3,
          name: 'Edited',
          acceptedPlanContentVersion: 5,
        ),
      );

      final d = await detail();
      expect(d.plan.name, 'Edited');
      expect(d.plan.version, 3);
      expect(d.plan.contentVersion, 4);
    });

    test('a session created and since deleted by another member is not '
        'resurrected', () async {
      final create = PlanningMutationRecord(
        aggregateId: 'session-new',
        organizationId: organizationId,
        planId: 'plan-1',
        kind: PlanningMutationKind.sessionCreate,
        syncStatus: PlanningMutationSyncStatus.accepted,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        name: 'New',
        position: 2,
        baseVersion: 1,
        acceptedPlanContentVersion: 5,
      );
      await seed(contentVersion: 6);

      await reconciler.reconcile(testContext, create);

      var d = await detail();
      expect(d.sessions.map((session) => session.id), ['session-1']);
      expect(d.plan.contentVersion, 6);

      await seed(contentVersion: 4);

      await reconciler.reconcile(testContext, create);

      d = await detail();
      expect(d.sessions.map((session) => session.id), contains('session-new'));
      expect(d.plan.contentVersion, 5);
    });

    test('a session create is reconciled and gated at version 1, whatever '
        'its (retry-rebased) base version', () async {
      // MG8 keeps rebasing a retried create, so its base can be a PLAN
      // version (5); create_session always inserts the session at version 1.
      final create = PlanningMutationRecord(
        aggregateId: 'session-new',
        organizationId: organizationId,
        planId: 'plan-1',
        kind: PlanningMutationKind.sessionCreate,
        syncStatus: PlanningMutationSyncStatus.accepted,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        name: 'Mine',
        position: 2,
        baseVersion: 5,
      );

      await reconciler.reconcile(testContext, create);

      var d = await detail();
      final written = d.sessions.singleWhere((s) => s.id == 'session-new');
      expect(written.name, 'Mine');
      expect(written.version, 1);

      // A pull stored a foreign rename of the new session (v2): the resumed
      // marker (no returned content version) must not overwrite it.
      await localStore.replaceActiveProjection(
        userId: userId,
        organizationId: organizationId,
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 4, 11, 10),
            version: 2,
            contentVersion: 5,
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-new',
            planId: 'plan-1',
            position: 2,
            name: 'Foreign',
            version: 2,
          ),
        ],
        items: const [],
        refreshedAt: DateTime.utc(2026, 4, 11, 12),
      );

      await reconciler.reconcile(testContext, create);

      d = await detail();
      final kept = d.sessions.singleWhere((s) => s.id == 'session-new');
      expect(kept.name, 'Foreign');
      expect(kept.version, 2);
      expect(d.plan.contentVersion, 5);
    });

    test('a key edit without a returned content version is skipped when the '
        'item is newer', () async {
      final keyEdit = PlanningMutationRecord(
        aggregateId: 'item-1',
        organizationId: organizationId,
        planId: 'plan-1',
        sessionId: 'session-1',
        kind: PlanningMutationKind.sessionItemKeyEdit,
        syncStatus: PlanningMutationSyncStatus.accepted,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 11),
        baseVersion: 2,
        keyEdit: SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: -3,
          capoMode: SessionItemKeyFieldMode.clear,
        ),
      );
      await seed(itemVersion: 3);

      await reconciler.reconcile(testContext, keyEdit);

      var item = (await detail()).sessions.single.items.single;
      expect(item.version, 3);
      expect(item.planTranspose, isNull);

      await seed(itemVersion: 1);

      await reconciler.reconcile(testContext, keyEdit);

      item = (await detail()).sessions.single.items.single;
      expect(item.version, 2);
      expect(item.planTranspose, -3);
    });

    test('a corrupt record throws before any projection write, even when the '
        'projection is newer', () async {
      await seed(contentVersion: 9);

      await expectLater(
        reconciler.reconcile(
          testContext,
          PlanningMutationRecord(
            aggregateId: 'item-2',
            organizationId: organizationId,
            planId: 'plan-1',
            sessionId: 'session-1',
            kind: PlanningMutationKind.sessionItemCreateSong,
            syncStatus: PlanningMutationSyncStatus.accepted,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 4, 11, 11),
            songTitle: 'Gamma',
            position: 2,
            baseVersion: 1,
            acceptedPlanContentVersion: 5,
          ),
        ),
        throwsA(isA<ReconcileFieldError>()),
      );
    });
  });
}
