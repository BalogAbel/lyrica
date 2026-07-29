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
/// projection (LF-4), a name-only edit does not corrupt the plan's
/// unmodified description/scheduledFor (LF-5), and duplicate offline
/// song-adds collapse to a single visible item (LF-6).
///
/// LF-5 carries the plan's *current* (unchanged) description/scheduledFor in
/// the mutation draft rather than null, because a real edit draft always
/// carries the complete form state (see PlanEditDraft's single construction
/// site in plan_editor_dialog.dart): null on a planEdit mutation means the
/// field was explicitly cleared, not "leave it as-is".
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

        // act: mutation only changes the name; description/scheduledFor carry
        // their current (unchanged) values, as the real editor dialog would
        // -- null here would mean an explicit clear, not "leave as-is".
        await mutationStore.recordPlanEdit(
          context: context,
          draft: PlanningPlanEditMutationDraft(
            planId: 'plan-2',
            name: 'Updated Name',
            description: 'Important description',
            scheduledFor: scheduledFor,
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

    test(
      'LF-6: two offline song-adds with different item ids but the same songId '
      'collapse to a single visible session item',
      () async {
        // arrange: base plan with one empty session
        await localStore.replaceActiveProjection(
          userId: context.userId,
          organizationId: context.organizationId,
          plans: [
            CachedPlanRecord(
              id: 'plan-3',
              slug: 'duplicate-song-plan',
              name: 'Duplicate Song Plan',
              description: null,
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 4, 11, 10),
            ),
          ],
          sessions: const [
            CachedSessionRecord(
              id: 'session-3',
              planId: 'plan-3',
              slug: 'set-1',
              position: 10,
              name: 'Set 1',
            ),
          ],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 11, 10),
        );

        // act: same songId added twice offline with different item ids
        // (e.g. a retry after an ambiguous failure, or a double-tap that
        // raced two local mutation records before sync settled).
        await mutationStore.recordSessionItemCreateSong(
          context: context,
          draft: const PlanningSessionItemCreateSongMutationDraft(
            sessionItemId: 'item-local-a',
            sessionId: 'session-3',
            planId: 'plan-3',
            songId: 'song-dup',
            songTitle: 'Duplicate Song',
            position: 10,
            baseVersion: 1,
          ),
        );
        await mutationStore.recordSessionItemCreateSong(
          context: context,
          draft: const PlanningSessionItemCreateSongMutationDraft(
            sessionItemId: 'item-local-b',
            sessionId: 'session-3',
            planId: 'plan-3',
            songId: 'song-dup',
            songTitle: 'Duplicate Song',
            position: 20,
            baseVersion: 1,
          ),
        );

        final detail = await repository.getPlanDetail('plan-3');
        final session = detail.sessions.firstWhere(
          (value) => value.id == 'session-3',
        );

        final matchingItems = session.items
            .where((item) => item.song.id == 'song-dup')
            .toList(growable: false);

        expect(
          matchingItems,
          hasLength(1),
          reason:
              'The same songId added twice offline with different item ids '
              'must appear exactly once in the merged session, not twice.',
        );
      },
    );
  });
}
