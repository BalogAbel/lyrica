import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// LF-T3 contract: folding repeated intent into one row per aggregate must
/// preserve exactly-once sync (ADR-019) and OCC base-version semantics.
/// A squashed record still has to reconcile correctly and must never
/// manufacture a conflict that the un-squashed sequence would not have had.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('DriftPlanningMutationStore squash contract', () {
    late PlanningLocalDatabase database;
    late DriftPlanningMutationStore store;

    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      store = DriftPlanningMutationStore(
        database: database,
        localStore: DriftPlanningLocalStore(database),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('planEdit folded into a pending planCreate leaves exactly one '
        'record, still a create', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Sunday Service',
          description: 'Second slot',
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(pending, hasLength(1));
      // Exactly-once: the fold must not turn one create into create+edit,
      // which would send the aggregate twice.
      expect(pending.single.kind, PlanningMutationKind.planCreate);
      expect(pending.single.name, 'Sunday Service');
      expect(pending.single.description, 'Second slot');
      // A create has no base version to conflict against; folding an edit
      // into it must not invent one.
      expect(pending.single.baseVersion, isNull);
    });

    test('repeated planEdit keeps the FIRST captured base version and '
        'origin snapshot', () async {
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-2',
          name: 'First',
          baseVersion: 7,
          originSnapshot: {'name': 'Original'},
        ),
      );
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-2',
          name: 'Second',
          baseVersion: 9,
          originSnapshot: {'name': 'Stale'},
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      expect(pending, hasLength(1));
      expect(pending.single.name, 'Second');
      // OCC: the base version is the version the user actually started
      // from. Advancing it on a later local edit would silently defeat
      // conflict detection against a concurrent remote change.
      expect(pending.single.baseVersion, 7);
      expect(pending.single.originSnapshot, {'name': 'Original'});
    });

    test('sessionDelete of a still-pending sessionCreate removes the record '
        'entirely rather than queueing a delete', () async {
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-3',
          slug: 'first-set',
          name: 'First Set',
          position: 0,
        ),
      );
      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-3',
        ),
      );

      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      // Exactly-once: the session never existed remotely, so a delete must
      // not be sent for it.
      expect(pending, isEmpty);
    });

    test('sessionDelete of a pending sessionCreate also removes that '
        "session's pending item mutations", () async {
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-4',
          slug: 'second-set',
          name: 'Second Set',
          position: 1,
        ),
      );
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-2',
          planId: 'plan-4',
          songId: 'song-1',
          songTitle: 'Song One',
          position: 0,
        ),
      );
      await store.recordSessionItemReorder(
        context: context,
        draft: const PlanningSessionItemReorderMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-4',
          orderedSessionItemIds: ['item-1'],
        ),
      );

      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-4',
        ),
      );

      final remaining = await store.readAllMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      // Nothing may survive that references a session which never existed
      // remotely: those rows can only ever fail dependencyBlocked, and they
      // would consume the mutation budget forever.
      expect(remaining, isEmpty);
    });
  });
}
