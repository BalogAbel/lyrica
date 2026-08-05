import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
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

    test('merge keeps a failed planEdit visible instead of reverting', () async {
      // arrange: projection has plan P (name "Server Name"); mutation store has a planEdit on P
      //          with name "Edited Name", syncStatus=failedDependency
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

      // simulate sync failure
      await mutationStore.saveSyncAttemptResult(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.failedDependency,
      );

      // act
      final plans = await repository.listPlans();

      // assert: the plan P in result has name "Edited Name" (the edit), NOT "Server Name"
      final plan = plans.firstWhere((p) => p.id == 'plan-1');
      expect(plan.name, equals('Edited Name'));
    });

    test(
      'a visible failed planEdit does not blank an unmodified description/scheduledFor',
      () async {
        // arrange: plan P has description D and scheduledFor S in projection;
        //          a planEdit mutation changed only the name, syncStatus=conflict.
        // A real edit draft always carries the complete form state, so a
        // name-only change still carries the plan's current (unchanged)
        // description and scheduledFor rather than null -- null now means
        // "explicitly cleared", not "unchanged".
        final planWithDetails = CachedPlanRecord(
          id: 'plan-2',
          slug: 'detailed-plan',
          name: 'Original Name',
          description: 'Important description',
          scheduledFor: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 4, 11, 10),
        );

        await localStore.replaceActiveProjection(
          userId: context.userId,
          organizationId: context.organizationId,
          plans: [planWithDetails],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 11, 10),
        );

        // record edit that changes only name; description/scheduledFor carry
        // their current (unchanged) values, as the real editor dialog would.
        await mutationStore.recordPlanEdit(
          context: context,
          draft: PlanningPlanEditMutationDraft(
            planId: 'plan-2',
            name: 'Updated Name',
            description: 'Important description',
            scheduledFor: DateTime.utc(2026, 5, 1),
            baseVersion: 1,
          ),
        );

        // simulate sync conflict
        await mutationStore.saveSyncAttemptResult(
          userId: context.userId,
          organizationId: context.organizationId,
          aggregateType: 'plan',
          aggregateId: 'plan-2',
          syncStatus: PlanningMutationSyncStatus.conflict,
        );

        // act
        final plans = await repository.listPlans();
        final plan = plans.firstWhere((p) => p.id == 'plan-2');

        // assert: returned plan keeps description D and scheduledFor S (NOT blanked), and shows edited name
        expect(plan.name, equals('Updated Name'));
        expect(plan.description, equals('Important description'));
        expect(plan.scheduledFor, equals(DateTime.utc(2026, 5, 1)));
      },
    );

    test('a cleared scheduled-for is not masked by the base plan', () async {
      final planWithSchedule = CachedPlanRecord(
        id: 'plan-3',
        slug: 'scheduled-plan',
        name: 'Scheduled Plan',
        description: 'Some description',
        scheduledFor: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 4, 11, 10),
      );

      await localStore.replaceActiveProjection(
        userId: context.userId,
        organizationId: context.organizationId,
        plans: [planWithSchedule],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );

      await mutationStore.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-3',
          name: 'Scheduled Plan',
          description: 'Some description',
          scheduledFor: null,
          baseVersion: 1,
        ),
      );

      final plans = await repository.listPlans();
      final summary = plans.firstWhere((p) => p.id == 'plan-3');
      expect(summary.scheduledFor, isNull);

      final detail = await repository.getPlanDetail('plan-3');
      expect(detail.plan.scheduledFor, isNull);
    });

    test('a cleared description is not masked by the base plan', () async {
      final planWithDescription = CachedPlanRecord(
        id: 'plan-4',
        slug: 'described-plan',
        name: 'Described Plan',
        description: 'Some description',
        scheduledFor: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 4, 11, 10),
      );

      await localStore.replaceActiveProjection(
        userId: context.userId,
        organizationId: context.organizationId,
        plans: [planWithDescription],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 4, 11, 10),
      );

      await mutationStore.recordPlanEdit(
        context: context,
        draft: PlanningPlanEditMutationDraft(
          planId: 'plan-4',
          name: 'Described Plan',
          description: null,
          scheduledFor: DateTime.utc(2026, 5, 1),
          baseVersion: 1,
        ),
      );

      final plans = await repository.listPlans();
      final summary = plans.firstWhere((p) => p.id == 'plan-4');
      expect(summary.description, isNull);

      final detail = await repository.getPlanDetail('plan-4');
      expect(detail.plan.description, isNull);
    });
  });

  group('PlanningLocalReadRepository slug resolution', () {
    // These use recording fakes instead of the Drift-backed stores above so
    // the store/mutation-store call counts can be asserted directly (LF-9).

    test('getPlanDetailBySlug reads the mutation set once and never lists '
        'every plan', () async {
      final store = _RecordingPlanningLocalStore(
        summaries: [
          PlanSummary(
            id: 'plan-1',
            slug: 'team-rehearsal',
            name: 'Team Rehearsal',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        ],
        details: {
          'plan-1': PlanDetail(
            plan: PlanSummary(
              id: 'plan-1',
              slug: 'team-rehearsal',
              name: 'Team Rehearsal',
              description: null,
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 4, 11, 10),
            ),
            sessions: const [],
          ),
        },
      );
      final mutationStore = _RecordingPlanningMutationStore(
        actionable: const [],
      );
      final repository = PlanningLocalReadRepository(
        store: store,
        mutationStore: mutationStore,
        contextReader: () async => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

      final detail = await repository.getPlanDetailBySlug('team-rehearsal');

      expect(detail?.plan.id, 'plan-1');
      expect(
        mutationStore.readActionableMutationsCalls,
        1,
        reason: 'exactly one actionable-mutation read per slug open',
      );
      expect(
        store.readPlanSummariesCalls,
        0,
        reason: 'must not fall back to a full plan-summary listing',
      );
    });

    test('a plan that exists only as a pending planCreate mutation is still '
        'found by slug', () async {
      final store = _RecordingPlanningLocalStore(summaries: [], details: {});
      final pendingCreate = PlanningMutationRecord(
        aggregateId: 'plan-offline-1',
        organizationId: 'org-1',
        slug: 'offline-only-plan',
        name: 'Offline Only Plan',
        kind: PlanningMutationKind.planCreate,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026, 4, 11, 10),
      );
      final mutationStore = _RecordingPlanningMutationStore(
        actionable: [pendingCreate],
      );
      final repository = PlanningLocalReadRepository(
        store: store,
        mutationStore: mutationStore,
        contextReader: () async => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

      final summary = await repository.getPlanSummaryBySlug(
        'offline-only-plan',
      );
      final detail = await repository.getPlanDetailBySlug('offline-only-plan');

      expect(summary?.id, 'plan-offline-1');
      expect(detail?.plan.id, 'plan-offline-1');
      expect(
        store.readPlanSummaryBySlugCalls,
        0,
        reason: 'a pending create resolves without touching the store',
      );
    });
  });
}

class _RecordingPlanningLocalStore implements PlanningLocalStore {
  _RecordingPlanningLocalStore({
    required List<PlanSummary> summaries,
    required Map<String, PlanDetail> details,
  }) : _summaries = summaries,
       _details = details;

  final List<PlanSummary> _summaries;
  final Map<String, PlanDetail> _details;

  int readPlanSummariesCalls = 0;
  int readPlanSummaryBySlugCalls = 0;
  int readPlanDetailCalls = 0;
  int readPlanDetailBySlugCalls = 0;

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) async {
    readPlanSummariesCalls += 1;
    return _summaries;
  }

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async {
    readPlanSummaryBySlugCalls += 1;
    for (final summary in _summaries) {
      if (summary.slug == planSlug) {
        return summary;
      }
    }
    return null;
  }

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) async {
    readPlanDetailCalls += 1;
    return _details[planId];
  }

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async {
    readPlanDetailBySlugCalls += 1;
    for (final detail in _details.values) {
      if (detail.plan.slug == planSlug) {
        return detail;
      }
    }
    return null;
  }

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async => _details.isNotEmpty;

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async => null;

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}
}

class _RecordingPlanningMutationStore implements PlanningMutationStore {
  _RecordingPlanningMutationStore({
    required List<PlanningMutationRecord> actionable,
  }) : _actionable = actionable;

  final List<PlanningMutationRecord> _actionable;
  int readActionableMutationsCalls = 0;

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async {
    readActionableMutationsCalls += 1;
    return _actionable;
  }

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'unused';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'unused';

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async => false;

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async => false;

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => _actionable;

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    for (final entry in _actionable) {
      if (entry.kind.aggregateType == aggregateType &&
          entry.aggregateId == aggregateId) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => _actionable;

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => true;

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) async => null;
}
