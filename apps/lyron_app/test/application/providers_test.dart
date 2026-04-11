import 'dart:async';

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
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
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

  test(
    'session-expired cleanup does not delete planning data restored by a newer signed-in generation',
    () async {
      final authRepository = _ControllableAuthRepository();
      final authController = AppAuthController(authRepository);
      await authController.signIn(
        email: 'demo@lyron.local',
        password: 'secret',
      );
      final database = PlanningLocalDatabase.inMemory();
      final baseStore = DriftPlanningLocalStore(database);
      final blockingStore = _BlockingDeletePlanningLocalStore(baseStore);
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          planningLocalStoreProvider.overrideWithValue(blockingStore),
          planningRemoteRefreshRepositoryProvider.overrideWithValue(
            const _StaticPlanningRemoteRefreshRepository(),
          ),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => 'org-1',
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        authController.dispose();
        await database.close();
      });

      await container
          .read(planningSyncControllerProvider)
          .handleActiveContextChanged(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          );

      expect(
        await blockingStore.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        hasLength(1),
      );

      authRepository.emitSession(null);
      await blockingStore.deleteStarted.future;

      await authController.signIn(
        email: 'demo@lyron.local',
        password: 'secret',
      );
      await container
          .read(planningSyncControllerProvider)
          .handleActiveContextChanged(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            refresh: false,
          );
      blockingStore.releaseDelete();
      await container.read(planningSyncControllerProvider).refreshPlanning();

      expect(
        await blockingStore.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        hasLength(1),
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

class _ControllableAuthRepository implements AuthRepository {
  final StreamController<AppAuthSession?> _controller =
      StreamController<AppAuthSession?>.broadcast();

  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {
    _controller.add(null);
  }

  void emitSession(AppAuthSession? session) {
    _controller.add(session);
  }
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
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

  final Future<void> Function() onSync;
  int syncCalls = 0;

  @override
  Future<void> syncPendingMutations(ActivePlanningReadContext context) async {
    syncCalls += 1;
    await onSync();
  }
}

class _BlockingDeletePlanningLocalStore implements PlanningLocalStore {
  _BlockingDeletePlanningLocalStore(this._delegate);

  final PlanningLocalStore _delegate;
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> _deleteGate = Completer<void>();

  void releaseDelete() {
    if (!_deleteGate.isCompleted) {
      _deleteGate.complete();
    }
  }

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return _delegate.countSongReferences(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) {
    return _delegate.deletePlanningData(
      userId: userId,
      organizationId: organizationId,
      shouldContinue: shouldContinue,
    );
  }

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {
    if (!deleteStarted.isCompleted) {
      deleteStarted.complete();
    }
    await _deleteGate.future;
    await _delegate.deletePlanningDataForUser(
      userId: userId,
      shouldContinue: shouldContinue,
    );
  }

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) {
    return _delegate.deleteSyncedSession(
      userId: userId,
      organizationId: organizationId,
      sessionId: sessionId,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) {
    return _delegate.hasProjection(
      userId: userId,
      organizationId: organizationId,
    );
  }

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) {
    return _delegate.readPlanDetail(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
    );
  }

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) {
    return _delegate.readPlanDetailBySlug(
      userId: userId,
      organizationId: organizationId,
      planSlug: planSlug,
    );
  }

  @override
  Future<String?> readLatestCachedOrganizationId({required String userId}) {
    return _delegate.readLatestCachedOrganizationId(userId: userId);
  }

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) {
    return _delegate.readPlanSummaries(
      userId: userId,
      organizationId: organizationId,
    );
  }

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) {
    return _delegate.readPlanSummaryBySlug(
      userId: userId,
      organizationId: organizationId,
      planSlug: planSlug,
    );
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
  }) {
    return _delegate.replaceActiveProjection(
      userId: userId,
      organizationId: organizationId,
      plans: plans,
      sessions: sessions,
      items: items,
      refreshedAt: refreshedAt,
      shouldContinue: shouldContinue,
    );
  }

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) {
    return _delegate.upsertSyncedPlan(
      userId: userId,
      organizationId: organizationId,
      plan: plan,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) {
    return _delegate.upsertSyncedSession(
      userId: userId,
      organizationId: organizationId,
      session: session,
      refreshedAt: refreshedAt,
    );
  }
}

class _StaticPlanningRemoteRefreshRepository
    implements PlanningRemoteRefreshRepository {
  const _StaticPlanningRemoteRefreshRepository();

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    return PlanningSyncPayload(
      plans: [
        PlanningSyncPlan(
          id: 'plan-1',
          slug: 'plan-$organizationId',
          name: 'Plan $organizationId',
          description: 'Description $organizationId',
          scheduledFor: DateTime.utc(2026, 4, 5, 9),
          updatedAt: DateTime.utc(2026, 4, 3, 12),
          version: 1,
        ),
      ],
      sessions: const [],
      items: const [],
    );
  }
}
