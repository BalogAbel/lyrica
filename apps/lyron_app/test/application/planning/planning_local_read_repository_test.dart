import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningLocalReadRepository', () {
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

      await localStore.replaceActiveProjection(
        userId: context.userId,
        organizationId: context.organizationId,
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
          CachedSessionItemRecord(
            id: 'item-2',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 20,
            songId: 'song-2',
            songTitle: 'Beta',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'pending session reorder immediately changes merged plan detail ordering',
      () async {
        await mutationStore.recordSessionReorder(
          context: context,
          draft: const PlanningSessionReorderMutationDraft(
            planId: 'plan-1',
            orderedSessionIds: ['session-2', 'session-1'],
            baseVersion: 1,
          ),
        );

        final detail = await repository.getPlanDetail('plan-1');

        expect(
          detail.sessions.map((session) => session.id),
          orderedEquals(const ['session-2', 'session-1']),
        );
      },
    );

    test(
      'pending song add, delete, and reorder overlay into merged session items',
      () async {
        await mutationStore.recordSessionItemCreateSong(
          context: context,
          draft: const PlanningSessionItemCreateSongMutationDraft(
            sessionItemId: 'item-local-1',
            sessionId: 'session-1',
            planId: 'plan-1',
            songId: 'song-3',
            songTitle: 'Gamma',
            position: 30,
            baseVersion: 1,
          ),
        );
        await mutationStore.recordSessionItemDelete(
          context: context,
          draft: const PlanningSessionItemDeleteMutationDraft(
            sessionItemId: 'item-1',
            sessionId: 'session-1',
            planId: 'plan-1',
            baseVersion: 1,
          ),
        );
        await mutationStore.recordSessionItemReorder(
          context: context,
          draft: const PlanningSessionItemReorderMutationDraft(
            sessionId: 'session-1',
            planId: 'plan-1',
            orderedSessionItemIds: ['item-local-1', 'item-2'],
            baseVersion: 1,
          ),
        );

        final detail = await repository.getPlanDetail('plan-1');
        final session = detail.sessions.firstWhere(
          (value) => value.id == 'session-1',
        );

        expect(
          session.items.map((item) => item.id),
          orderedEquals(const ['item-local-1', 'item-2']),
        );
        expect(session.items.first.song.title, 'Gamma');
      },
    );
  });
}
