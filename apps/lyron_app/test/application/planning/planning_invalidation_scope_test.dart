// TODO(auth-invite-sso): stubs and signIn calls updated when SignInScreen + integration tests rewritten
// ignore_for_file: non_abstract_class_inherits_abstract_member, override_on_non_overriding_member, undefined_method
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';

/// Pins WHICH revision signal each planning reader depends on. The planning
/// read providers are `autoDispose`, so each is kept alive with a no-op
/// `container.listen(..., fireImmediately: true)` and recomputation is
/// observed only through the fakes' call counters (not through disposal or
/// simple re-reads, which would return the same cached Future).
void main() {
  test(
    'mutation revision invalidates only the mutation-facing readers (#5/#6), not #1/#4',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final repository = _CountingPlanningRepository(
        plans: [
          PlanSummary(
            id: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime(2026, 4, 10),
          ),
        ],
      );
      final mutationStore = _CountingPlanningMutationStore(
        entries: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
        hasUnsynced: true,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          planningRepositoryProvider.overrideWithValue(repository),
          planningMutationStoreProvider.overrideWithValue(mutationStore),
          planningSyncStateProvider.overrideWithValue(
            PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: DateTime(2026, 4, 10, 12),
            ),
          ),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Keep each reader alive so it only recomputes on invalidation.
      // container.dispose (registered above) closes these subscriptions.
      container.listen(
        planningPlanDetailProvider('plan-1'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        hasUnsyncedPlanningMutationsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        planningMutationEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        planningPlanListProvider,
        (_, _) {},
        fireImmediately: true,
      );

      // Settle initial async reads.
      await container.read(planningPlanDetailProvider('plan-1').future);
      await container.read(hasUnsyncedPlanningMutationsProvider.future);
      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);

      final detailCallsBefore = repository.getPlanDetailCalls;
      final listCallsBefore = repository.listPlansCalls;
      final mutationCallsBefore = mutationStore.readAllCalls;
      final hasUnsyncedCallsBefore = mutationStore.hasUnsyncedCalls;

      // Bump the MUTATION signal.
      container.read(planningMutationRevisionProvider.notifier).state += 1;
      await container.read(planningMutationEntriesProvider.future);
      await container.read(hasUnsyncedPlanningMutationsProvider.future);
      await container.read(planningPlanDetailProvider('plan-1').future);
      await container.read(planningPlanListProvider.future);

      // #5 and #6 recompute; #4 and #1 do NOT.
      expect(mutationStore.readAllCalls, greaterThan(mutationCallsBefore));
      expect(
        mutationStore.hasUnsyncedCalls,
        greaterThan(hasUnsyncedCallsBefore),
      );
      expect(repository.getPlanDetailCalls, detailCallsBefore);
      expect(repository.listPlansCalls, listCallsBefore);
    },
  );

  test(
    'aggregate revision invalidates the plan detail and list readers (#4/#1)',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final repository = _CountingPlanningRepository(
        plans: [
          PlanSummary(
            id: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime(2026, 4, 10),
          ),
        ],
      );
      final mutationStore = _CountingPlanningMutationStore(
        entries: const [],
        hasUnsynced: false,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          planningRepositoryProvider.overrideWithValue(repository),
          planningMutationStoreProvider.overrideWithValue(mutationStore),
          planningSyncStateProvider.overrideWithValue(
            PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: DateTime(2026, 4, 10, 12),
            ),
          ),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // container.dispose (registered above) closes these subscriptions.
      container.listen(
        planningPlanDetailProvider('plan-1'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        planningPlanListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        planningMutationEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await container.read(planningPlanDetailProvider('plan-1').future);
      await container.read(planningPlanListProvider.future);
      await container.read(planningMutationEntriesProvider.future);

      final detailCallsBefore = repository.getPlanDetailCalls;
      final listCallsBefore = repository.listPlansCalls;
      final mutationCallsBefore = mutationStore.readAllCalls;

      container.read(planningDataRevisionProvider.notifier).state += 1;
      await container.read(planningPlanDetailProvider('plan-1').future);
      await container.read(planningPlanListProvider.future);
      await container.read(planningMutationEntriesProvider.future);

      expect(repository.getPlanDetailCalls, greaterThan(detailCallsBefore));
      expect(repository.listPlansCalls, greaterThan(listCallsBefore));
      // #5 watches both signals, so the aggregate bump also recomputes it.
      expect(mutationStore.readAllCalls, greaterThan(mutationCallsBefore));
    },
  );
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local');

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _CountingPlanningRepository implements PlanningRepository {
  _CountingPlanningRepository({required this.plans});

  List<PlanSummary> plans;
  int getPlanDetailCalls = 0;
  int listPlansCalls = 0;

  @override
  Future<PlanDetail> getPlanDetail(String planId) {
    getPlanDetailCalls += 1;
    final plan = plans.firstWhere((candidate) => candidate.id == planId);
    return Future.value(PlanDetail(plan: plan, sessions: const []));
  }

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) {
    final plan = plans
        .where((candidate) => candidate.slug == planSlug)
        .firstOrNull;
    if (plan == null) {
      return Future.value(null);
    }
    return Future.value(PlanDetail(plan: plan, sessions: const []));
  }

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async {
    for (final plan in plans) {
      if (plan.slug == planSlug) {
        return plan;
      }
    }
    return null;
  }

  @override
  Future<List<PlanSummary>> listPlans() async {
    listPlansCalls += 1;
    return plans;
  }
}

class _CountingPlanningMutationStore implements PlanningMutationStore {
  _CountingPlanningMutationStore({
    required this.entries,
    required this.hasUnsynced,
  });

  List<PlanningMutationRecord> entries;
  bool hasUnsynced;
  int readAllCalls = 0;
  int hasUnsyncedCalls = 0;

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
  Future<bool> hasUnsyncedMutations({required String userId}) async {
    hasUnsyncedCalls += 1;
    return hasUnsynced;
  }

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async {
    readAllCalls += 1;
    return entries;
  }

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    for (final entry in entries) {
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
  }) async => entries;

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => entries;

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
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => true;

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
