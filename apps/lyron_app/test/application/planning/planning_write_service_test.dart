import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningWriteService', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore mutationStore;
    late PlanningLocalReadRepository repository;
    late PlanningWriteService service;
    late Future<void> Function() seedProjection;
    late int syncCalls;
    late ActivePlanningReadContext? activeContext;
    late List<SongSummary> visibleSongs;

    const context = PlanningWriteContext(
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
      repository = PlanningLocalReadRepository(
        store: localStore,
        mutationStore: mutationStore,
        contextReader: () async => activeContext,
      );
      syncCalls = 0;
      visibleSongs = const [
        SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
        SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
      ];
      activeContext = const ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      service = PlanningWriteService(
        repository,
        mutationStore: mutationStore,
        listVisibleSongs: ({required userId, required organizationId}) async {
          return visibleSongs;
        },
        activeContextReader: () async => activeContext,
        syncScheduler: (_) async {
          syncCalls += 1;
        },
        idGenerator: () => 'generated-id-1',
      );
      seedProjection = () {
        return localStore.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [
            CachedPlanRecord(
              id: 'plan-1',
              slug: 'sunday-am',
              name: 'Sunday AM',
              description: 'Original',
              scheduledFor: DateTime.utc(2026, 4, 13, 9),
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
            CachedSessionRecord(
              id: 'session-2',
              planId: 'plan-1',
              slug: 'closing',
              position: 20,
              name: 'Closing',
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
          refreshedAt: DateTime.utc(2026, 4, 1, 12),
        );
      };
    });

    tearDown(() async {
      await database.close();
    });

    test('pending plan create appears immediately in listPlans', () async {
      await service.createPlan(
        context: context,
        draft: const PlanCreateDraft(
          name: 'Weekend Service',
          description: 'Local draft',
          scheduledFor: null,
        ),
      );

      final plans = await repository.listPlans();

      expect(plans, hasLength(1));
      expect(plans.single.id, 'generated-id-1');
      expect(plans.single.slug, 'weekend-service');
      expect(plans.single.name, 'Weekend Service');
      expect(syncCalls, 1);
    });

    test(
      'createPlan returns the stored local mutation even if sync clears it immediately',
      () async {
        service = PlanningWriteService(
          repository,
          mutationStore: mutationStore,
          activeContextReader: () async => activeContext,
          syncScheduler: (_) async {
            syncCalls += 1;
            await mutationStore.clearMutation(
              userId: context.userId,
              organizationId: context.organizationId,
              aggregateType: PlanningMutationKind.planCreate.aggregateType,
              aggregateId: 'generated-id-1',
            );
          },
          idGenerator: () => 'generated-id-1',
        );

        final mutation = await service.createPlan(
          context: context,
          draft: const PlanCreateDraft(
            name: 'Weekend Service',
            description: 'Local draft',
          ),
        );

        expect(mutation.aggregateId, 'generated-id-1');
        expect(mutation.slug, 'weekend-service');
        expect(syncCalls, 1);
      },
    );

    test('pending plan edit updates merged list and detail fields', () async {
      await seedProjection();

      await service.editPlan(
        context: context,
        draft: const PlanEditDraft(
          planId: 'plan-1',
          name: 'Sunday AM Updated',
          description: 'Adjusted locally',
          scheduledFor: null,
        ),
      );

      final plans = await repository.listPlans();
      final detail = await repository.getPlanDetail('plan-1');

      expect(plans.single.name, 'Sunday AM Updated');
      expect(plans.single.description, 'Adjusted locally');
      expect(detail.plan.name, 'Sunday AM Updated');
      expect(detail.plan.description, 'Adjusted locally');
      final mutation = await mutationStore.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: 'plan-1',
      );
      expect(mutation?.baseVersion, 1);
      expect(syncCalls, 1);
    });

    test(
      'eligible session delete disappears from merged plan detail immediately',
      () async {
        await seedProjection();

        await service.deleteSession(
          context: context,
          draft: const SessionDeleteDraft(
            sessionId: 'session-2',
            planId: 'plan-1',
          ),
        );

        final detail = await repository.getPlanDetail('plan-1');
        expect(
          detail.sessions.map((session) => session.id),
          orderedEquals(const ['session-1']),
        );
        final mutation = await mutationStore.readMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: PlanningMutationKind.sessionDelete.aggregateType,
          aggregateId: 'session-2',
        );
        expect(mutation?.baseVersion, 1);
        expect(syncCalls, 1);
      },
    );

    test(
      'failed authorization and dependency mutations no longer overlay the normal merged view',
      () async {
        await seedProjection();

        await database
            .into(database.cachedPlanningMutations)
            .insert(
              CachedPlanningMutationsCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                aggregateType: 'plan',
                aggregateId: 'plan-1',
                mutationKind: PlanningMutationKind.planEdit.value,
                syncStatus:
                    PlanningMutationSyncStatus.failedAuthorization.value,
                name: const Value('Blocked name'),
                orderKey: 1,
                updatedAt: DateTime.utc(2026, 4, 10, 9),
              ),
            );
        await database
            .into(database.cachedPlanningMutations)
            .insert(
              CachedPlanningMutationsCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                aggregateType: 'session',
                aggregateId: 'session-2',
                mutationKind: PlanningMutationKind.sessionDelete.value,
                syncStatus: PlanningMutationSyncStatus.failedDependency.value,
                planId: const Value('plan-1'),
                orderKey: 2,
                updatedAt: DateTime.utc(2026, 4, 10, 9),
              ),
            );

        final plans = await repository.listPlans();
        final detail = await repository.getPlanDetail('plan-1');

        expect(plans.single.name, 'Sunday AM');
        expect(
          detail.sessions.map((session) => session.id),
          orderedEquals(const ['session-1', 'session-2']),
        );
      },
    );

    test(
      'merged plan ordering and local session ordering remain deterministic',
      () async {
        await localStore.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [
            CachedPlanRecord(
              id: 'plan-b',
              slug: 'plan-b',
              name: 'Plan B',
              description: null,
              scheduledFor: DateTime.utc(2026, 4, 12, 9),
              updatedAt: DateTime.utc(2026, 4, 2, 10),
            ),
            CachedPlanRecord(
              id: 'plan-a',
              slug: 'plan-a',
              name: 'Plan A',
              description: null,
              scheduledFor: DateTime.utc(2026, 4, 12, 9),
              updatedAt: DateTime.utc(2026, 4, 3, 10),
            ),
          ],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-a',
              slug: 'welcome',
              position: 10,
              name: 'Welcome',
            ),
          ],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 1, 12),
        );

        await service.createPlan(
          context: context,
          draft: const PlanCreateDraft(name: 'Plan C', scheduledFor: null),
        );
        await service.createSession(
          context: context,
          draft: const SessionCreateDraft(planId: 'plan-a', name: 'Message'),
        );

        final plans = await repository.listPlans();
        final detail = await repository.getPlanDetail('plan-a');

        expect(
          plans.map((plan) => plan.id),
          orderedEquals(const ['plan-a', 'plan-b', 'generated-id-1']),
        );
        expect(
          detail.sessions.map((session) => session.id),
          orderedEquals(const ['session-1', 'generated-id-1']),
        );
        expect(
          detail.sessions.map((session) => session.position),
          orderedEquals(const [10, 11]),
        );
        expect(syncCalls, 2);
      },
    );

    test(
      'rejects writes when supplied context diverges from active context',
      () async {
        activeContext = const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-2',
        );

        await expectLater(
          () => service.createPlan(
            context: context,
            draft: const PlanCreateDraft(name: 'Weekend Service'),
          ),
          throwsA(isA<PlanningWriteContextMismatchException>()),
        );
        expect(syncCalls, 0);
      },
    );

    test(
      'session reorder records the plan base version from the merged detail',
      () async {
        await seedProjection();

        await service.reorderSessions(
          context: context,
          draft: const SessionReorderDraft(
            planId: 'plan-1',
            orderedSessionIds: ['session-2', 'session-1'],
          ),
        );

        final mutation = await mutationStore.readMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType: PlanningMutationKind.sessionReorder.aggregateType,
          aggregateId: 'plan-1',
        );
        expect(mutation?.kind, PlanningMutationKind.sessionReorder);
        expect(mutation?.baseVersion, 1);
        expect(
          mutation?.orderedSiblingIds,
          orderedEquals(const ['session-2', 'session-1']),
        );
      },
    );

    test(
      'song-backed session item add records the session base version and local append position',
      () async {
        await seedProjection();

        await service.addSongSessionItem(
          context: context,
          draft: const SessionItemCreateSongDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            songId: 'song-2',
          ),
        );

        final mutation = await mutationStore.readMutation(
          userId: 'user-1',
          organizationId: 'org-1',
          aggregateType:
              PlanningMutationKind.sessionItemCreateSong.aggregateType,
          aggregateId: 'generated-id-1',
        );
        expect(mutation?.kind, PlanningMutationKind.sessionItemCreateSong);
        expect(mutation?.planId, 'plan-1');
        expect(mutation?.sessionId, 'session-1');
        expect(mutation?.songId, 'song-2');
        expect(mutation?.position, 11);
        expect(mutation?.baseVersion, 1);
      },
    );

    test(
      'duplicate song add is blocked before recording a local mutation',
      () async {
        await seedProjection();

        await expectLater(
          () => service.addSongSessionItem(
            context: context,
            draft: const SessionItemCreateSongDraft(
              sessionId: 'session-1',
              planId: 'plan-1',
              songId: 'song-1',
            ),
          ),
          throwsA(isA<DuplicateSessionSongException>()),
        );

        final pending = await mutationStore.readPendingMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(pending, isEmpty);
      },
    );
  });
}
