import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/planning/active_planning_context_controller.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('allows overriding the shared Supabase client provider', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(container.read(supabaseClientProvider), same(client));
  });

  test('selects a stable active organization id from RPC results', () {
    expect(
      selectActiveOrganizationId(const ['org-b', 'org-a', 'org-c']),
      'org-a',
    );
    expect(selectActiveOrganizationId(const []), isNull);
    expect(selectActiveOrganizationId('unexpected'), isNull);
  });

  test('wires PlanningRepository through the shared provider graph', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final database = PlanningLocalDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        planningLocalDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    expect(
      container.read(planningRepositoryProvider),
      isA<PlanningRepository>().having(
        (repository) => repository,
        'runtime type',
        isA<PlanningLocalReadRepository>(),
      ),
    );
  });

  test('wires planning local-first seams through the provider graph', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final database = PlanningLocalDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        planningLocalDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    expect(
      container.read(planningLocalStoreProvider),
      isA<PlanningLocalStore>(),
    );
    expect(
      container.read(planningLocalReadRepositoryProvider),
      isA<PlanningLocalReadRepository>(),
    );
    expect(
      container.read(planningMutationStoreProvider),
      isA<PlanningMutationStore>().having(
        (store) => store,
        'runtime type',
        isA<DriftPlanningMutationStore>(),
      ),
    );
    expect(
      container.read(planningWriteServiceProvider),
      isA<PlanningWriteService>(),
    );
    expect(
      container.read(planningMutationSyncControllerProvider),
      isA<PlanningMutationSyncController>(),
    );
    expect(
      container.read(planningRemoteRefreshRepositoryProvider),
      isA<PlanningRemoteRefreshRepository>().having(
        (repository) => repository,
        'runtime type',
        isA<SupabasePlanningRepository>(),
      ),
    );
    expect(
      container.read(planningSyncControllerProvider),
      isA<PlanningSyncController>(),
    );
    expect(
      container.read(activePlanningContextControllerProvider),
      isA<ActivePlanningContextController>(),
    );
  });

  test(
    'propagates active catalog context changes into the planning context controller',
    () async {
      final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
      final database = PlanningLocalDatabase.inMemory();
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.signIn(
        email: 'demo@lyron.local',
        password: 'secret',
      );
      final catalogContextProvider = StateProvider<ActiveCatalogContext?>(
        (ref) => null,
      );
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          planningLocalDatabaseProvider.overrideWithValue(database),
          appAuthControllerProvider.overrideWithValue(authController),
          activeCatalogContextProvider.overrideWith(
            (ref) => ref.watch(catalogContextProvider),
          ),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => throw StateError('offline'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        authController.dispose();
        await database.close();
      });

      container.read(activePlanningContextControllerProvider);
      container.read(catalogContextProvider.notifier).state =
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2');
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(activePlanningContextProvider),
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
      );
    },
  );

  test(
    'planning providers re-read after the revision signal changes',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.signIn(
        email: 'demo@lyron.local',
        password: 'secret',
      );
      final repository = _MutablePlanningRepository(
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
      final mutationStore = _MutablePlanningMutationStore(
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
          appAuthControllerProvider.overrideWithValue(authController),
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
      addTearDown(() {
        container.dispose();
        authController.dispose();
      });

      expect(
        (await container.read(planningPlanListProvider.future)).single.slug,
        'weekend-service',
      );
      expect(
        await container.read(hasUnsyncedPlanningMutationsProvider.future),
        isTrue,
      );
      expect(
        (await container.read(
          planningMutationEntriesProvider.future,
        )).single.syncStatus,
        PlanningMutationSyncStatus.pending,
      );

      repository.plans = [
        PlanSummary(
          id: 'plan-1',
          slug: 'weekend-service-2',
          name: 'Weekend Service',
          description: 'Draft',
          scheduledFor: null,
          updatedAt: DateTime(2026, 4, 10, 12),
        ),
      ];
      mutationStore
        ..entries = const []
        ..hasUnsynced = false;
      container.read(planningDataRevisionProvider.notifier).state += 1;

      expect(
        (await container.read(planningPlanListProvider.future)).single.slug,
        'weekend-service-2',
      );
      expect(
        await container.read(hasUnsyncedPlanningMutationsProvider.future),
        isFalse,
      );
      expect(
        await container.read(planningMutationEntriesProvider.future),
        isEmpty,
      );
    },
  );

  test(
    'planning write service sync invalidates cached planning providers through provider wiring',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.signIn(
        email: 'demo@lyron.local',
        password: 'secret',
      );
      final repository = _MutablePlanningRepository(
        plans: [
          PlanSummary(
            id: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime(2026, 4, 10),
            version: 1,
          ),
        ],
      );
      final mutationStore = _MutablePlanningMutationStore(
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
            baseVersion: 1,
          ),
        ],
        hasUnsynced: true,
      );
      final syncController = _RecordingPlanningMutationSyncController(
        onSync: () async {
          repository.plans = [
            PlanSummary(
              id: 'plan-1',
              slug: 'weekend-service-2',
              name: 'Weekend Service Revised',
              description: 'Synced',
              scheduledFor: null,
              updatedAt: DateTime(2026, 4, 10, 12),
              version: 2,
            ),
          ];
          mutationStore
            ..entries = const []
            ..hasUnsynced = false;
        },
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          planningRepositoryProvider.overrideWithValue(repository),
          planningMutationStoreProvider.overrideWithValue(mutationStore),
          planningMutationSyncControllerProvider.overrideWithValue(
            syncController,
          ),
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
      addTearDown(() {
        container.dispose();
        authController.dispose();
      });

      expect(
        (await container.read(planningPlanListProvider.future)).single.slug,
        'weekend-service',
      );
      expect(
        await container.read(hasUnsyncedPlanningMutationsProvider.future),
        isTrue,
      );
      expect(
        (await container.read(
          planningMutationEntriesProvider.future,
        )).single.syncStatus,
        PlanningMutationSyncStatus.pending,
      );

      await container
          .read(planningWriteServiceProvider)
          .editPlan(
            context: const PlanningWriteContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            draft: const PlanEditDraft(
              planId: 'plan-1',
              name: 'Weekend Service Revised',
              description: 'Synced',
            ),
          );

      expect(syncController.syncCalls, 1);
      expect(
        (await container.read(planningPlanListProvider.future)).single.slug,
        'weekend-service-2',
      );
      expect(
        await container.read(hasUnsyncedPlanningMutationsProvider.future),
        isFalse,
      );
      expect(
        await container.read(planningMutationEntriesProvider.future),
        isEmpty,
      );
    },
  );
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}

class _MutablePlanningRepository implements PlanningRepository {
  _MutablePlanningRepository({required this.plans});

  List<PlanSummary> plans;

  @override
  Future<PlanDetail> getPlanDetail(String planId) {
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
  Future<List<PlanSummary>> listPlans() async => plans;
}

class _MutablePlanningMutationStore implements PlanningMutationStore {
  _MutablePlanningMutationStore({
    required this.entries,
    required this.hasUnsynced,
  });

  List<PlanningMutationRecord> entries;
  bool hasUnsynced;

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
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateId,
  }) async {}

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async =>
      hasUnsynced;

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => entries;

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateId,
  }) async {
    for (final entry in entries) {
      if (entry.aggregateId == aggregateId) {
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
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {
    entries = [
      PlanningMutationRecord(
        aggregateId: draft.planId,
        organizationId: context.organizationId,
        slug: draft.slug,
        name: draft.name,
        description: draft.description,
        scheduledFor: draft.scheduledFor,
        kind: PlanningMutationKind.planCreate,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    ];
    hasUnsynced = true;
  }

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {
    entries = [
      PlanningMutationRecord(
        aggregateId: draft.planId,
        organizationId: context.organizationId,
        name: draft.name,
        description: draft.description,
        scheduledFor: draft.scheduledFor,
        kind: PlanningMutationKind.planEdit,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
        baseVersion: draft.baseVersion,
      ),
    ];
    hasUnsynced = true;
  }

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
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateId,
  }) async {}

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}
}

class _RecordingPlanningMutationSyncController
    extends PlanningMutationSyncController {
  _RecordingPlanningMutationSyncController({required this.onSync})
    : super(
        mutationStore: () => throw UnimplementedError(),
        remoteRepository: () => throw UnimplementedError(),
        refreshPlanning: () async {},
      );

  final Future<void> Function() onSync;
  int syncCalls = 0;

  @override
  Future<void> syncPendingMutations(ActivePlanningReadContext context) async {
    syncCalls += 1;
    await onSync();
  }
}
