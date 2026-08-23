// TODO(auth-invite-sso): stubs and signIn calls updated when SignInScreen + integration tests rewritten
// ignore_for_file: non_abstract_class_inherits_abstract_member, override_on_non_overriding_member, undefined_method
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/planning/active_planning_context_controller.dart';
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
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
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();
  setUp(() async {
    await closeSharedDatabases();
  });
  tearDown(() async {
    await closeSharedDatabases();
  });

  test('allows overriding the shared Supabase client provider', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(container.read(supabaseClientProvider), same(client));
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
        isA<BudgetedPlanningMutationStore>(),
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

  // D5 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  // Phase 4, Task 4.1 -- Step 1 of 2): these two tests used to prove that a
  // SINGLE verified-empty membership resolution purged the planning
  // projection, the song catalog, and its pending mutations end to end --
  // exactly the single-confirmation purge D5 exists to prevent. They now
  // prove the opposite invariant Step 1 requires through the same full
  // provider graph: a single resolution deletes nothing at all, and
  // everything stays readable.
  test(
    'verified empty membership on the planning boundary leaves planning and '
    'song data intact after one resolution',
    () async {
      final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final planningDatabase = PlanningLocalDatabase.inMemory();
      final songDatabase = SongCatalogDatabase.inMemory();
      final planningStore = DriftPlanningLocalStore(planningDatabase);
      final songStore = DriftSongCatalogStore(songDatabase);
      final foregroundState = _TestAppForegroundState();

      await planningStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 5, 1),
          ),
        ],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      await songStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      await songStore.saveSongMutation(
        const SongCatalogMutationDraft(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-2',
          slug: 'draft-song',
          title: 'Draft Song',
          source: '{title: Draft Song}',
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appAuthControllerProvider.overrideWith((_) => authController),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          appForegroundStateProvider.overrideWithValue(foregroundState),
          activeOrganizationReaderProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await planningDatabase.close();
        await songDatabase.close();
      });

      final controller = container.read(
        activePlanningContextControllerProvider,
      );
      await controller.refresh();

      // The active planning context clears (no organization resolved), but
      // nothing was deleted -- one verified-empty resolution only records
      // the membership-revocation marker (D5.1/D5.2).
      expect(controller.state, isNull);
      expect(
        await planningStore.hasProjection(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isTrue,
      );
      expect(
        await songStore.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isNotEmpty,
      );
      expect(
        await songStore.readSongMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'verified empty membership on the song catalog path leaves planning and '
    'song data intact after one resolution',
    () async {
      final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final planningDatabase = PlanningLocalDatabase.inMemory();
      final songDatabase = SongCatalogDatabase.inMemory();
      final planningStore = DriftPlanningLocalStore(planningDatabase);
      final songStore = DriftSongCatalogStore(songDatabase);
      final foregroundState = _TestAppForegroundState();

      await planningStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 5, 1),
          ),
        ],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      await songStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      await songStore.saveSongMutation(
        const SongCatalogMutationDraft(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-2',
          slug: 'draft-song',
          title: 'Draft Song',
          source: '{title: Draft Song}',
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appAuthControllerProvider.overrideWith((_) => authController),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          appForegroundStateProvider.overrideWithValue(foregroundState),
          activeOrganizationReaderProvider.overrideWithValue(() async => null),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await planningDatabase.close();
        await songDatabase.close();
      });

      container.read(planningSyncControllerProvider);
      final controller = container.read(songCatalogControllerProvider);
      await controller.refreshCatalog();

      // The catalog context clears (no organization resolved), but nothing
      // was deleted. planningSyncStateProvider's accessStatus is left
      // exactly as it was before this resolution -- Step 1 no longer runs
      // PlanningSyncController.handleVerifiedEmptyMembership's state reset
      // on a first resolution (that reset only belongs to an actual purge,
      // which does not happen here); with no organization ever resolved in
      // this test, that status never left its signedOut default.
      expect(controller.state.context, isNull);
      expect(
        container.read(planningSyncStateProvider).accessStatus,
        PlanningAccessStatus.signedOut,
      );
      expect(
        await planningStore.hasProjection(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isTrue,
      );
      expect(
        await songStore.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isNotEmpty,
      );
      expect(
        await songStore.readSongMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'session expired keeps the cached catalog and active song context readable',
    () async {
      final authRepository = _ControllableAuthRepository();
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        );
      final authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );
      await authController.restoreSession();
      final songDatabase = SongCatalogDatabase.inMemory();
      final songStore = DriftSongCatalogStore(songDatabase);
      final foregroundState = _TestAppForegroundState();
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => const [
          {
            'id': 'song-1',
            'slug': 'cached-song',
            'title': 'Cached Song',
            'version': 1,
          },
        ],
        getSongRow: (id) async => const {
          'id': 'song-1',
          'slug': 'cached-song',
          'chordpro_source': '{title: Cached Song}',
        },
      );

      await songStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );

      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          songCatalogStoreProvider.overrideWithValue(songStore),
          supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => 'org-1',
          ),
          appForegroundStateProvider.overrideWithValue(foregroundState),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await songDatabase.close();
      });
      final activeCatalogSubscription = container.listen(
        activeCatalogContextProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final songLibrarySubscription = container.listen(
        songLibraryListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(activeCatalogSubscription.close);
      addTearDown(songLibrarySubscription.close);

      await container.read(songCatalogControllerProvider).refreshCatalog();

      expect(
        container.read(activeCatalogContextProvider),
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
      expect(
        container.read(catalogSnapshotStateProvider).sessionStatus,
        CatalogSessionStatus.verified,
      );
      expect(
        await container.read(songLibraryListProvider.future),
        hasLength(1),
      );

      authRepository.emitSession(null);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(catalogSnapshotStateProvider).sessionStatus,
        CatalogSessionStatus.expired,
      );
      expect(
        container.read(activeCatalogContextProvider),
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
      expect(
        await container.read(songLibraryListProvider.future),
        hasLength(1),
      );
      expect(
        await songStore.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'explicit sign-out still clears the active song context and cache',
    () async {
      final authRepository = _ControllableAuthRepository();
      final authController = AppAuthController(authRepository);
      await authController.restoreSession();
      final songDatabase = SongCatalogDatabase.inMemory();
      final songStore = DriftSongCatalogStore(songDatabase);
      final foregroundState = _TestAppForegroundState();
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => const [
          {
            'id': 'song-1',
            'slug': 'cached-song',
            'title': 'Cached Song',
            'version': 1,
          },
        ],
        getSongRow: (id) async => const {
          'id': 'song-1',
          'slug': 'cached-song',
          'chordpro_source': '{title: Cached Song}',
        },
      );

      await songStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );

      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          songCatalogStoreProvider.overrideWithValue(songStore),
          supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => 'org-1',
          ),
          appForegroundStateProvider.overrideWithValue(foregroundState),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await songDatabase.close();
      });
      final activeCatalogSubscription = container.listen(
        activeCatalogContextProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final songLibrarySubscription = container.listen(
        songLibraryListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(activeCatalogSubscription.close);
      addTearDown(songLibrarySubscription.close);

      await container.read(songCatalogControllerProvider).refreshCatalog();

      expect(
        container.read(activeCatalogContextProvider),
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
      expect(
        await container.read(songLibraryListProvider.future),
        hasLength(1),
      );

      await authController.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(activeCatalogContextProvider), isNull);
      expect(await container.read(songLibraryListProvider.future), isEmpty);
      expect(
        await songStore.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    },
  );

  test(
    'propagates active catalog context changes into the planning context controller',
    () async {
      final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
      final database = PlanningLocalDatabase.inMemory();
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final catalogContextProvider = StateProvider<ActiveCatalogContext?>(
        (ref) => null,
      );
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          planningLocalDatabaseProvider.overrideWithValue(database),
          appAuthControllerProvider.overrideWith((_) => authController),
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
      await authController.restoreSession();
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
      addTearDown(() {
        container.dispose();
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
      await authController.restoreSession();
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
          appAuthControllerProvider.overrideWith((_) => authController),
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
      // The write service's own sync-scheduler choke point only bumps the
      // mutation-scoped revision (ARCH-2): it drives the badge/mutation-list
      // readers below without knowing whether a given write is
      // aggregate-affecting. In production, plan_detail_screen's `_editPlan`
      // handler bumps the aggregate revision itself because editing a plan's
      // summary is aggregate-scoped; simulate that same caller-side bump here
      // since this test calls the write service directly.
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
    'session-expired cleanup does not delete planning data restored by a newer signed-in generation',
    () async {
      final authRepository = _ControllableAuthRepository();
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        );
      final authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );
      await authController.restoreSession();
      final database = PlanningLocalDatabase.inMemory();
      final baseStore = DriftPlanningLocalStore(database);
      final blockingStore = _BlockingDeletePlanningLocalStore(baseStore);
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
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
      await Future<void>.delayed(Duration.zero);
      expect(blockingStore.deleteStarted.isCompleted, isFalse);

      await authController.signInWithOAuth(
        SignInMethod.google,
        redirectTo: 'lyron://auth',
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

  test(
    'accepted plan create/edit writes reconcile into the real local projection when refreshPlanning fails',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final database = PlanningLocalDatabase.inMemory();
      final localStore = DriftPlanningLocalStore(database);
      await localStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: const [],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          planningLocalDatabaseProvider.overrideWithValue(database),
          planningRemoteRefreshRepositoryProvider.overrideWithValue(
            const _FailingPlanningRemoteRefreshRepository(),
          ),
          planningMutationRemoteRepositoryProvider.overrideWithValue(
            const _AcceptedWriteFallbackPlanningMutationRemoteRepository(),
          ),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          planningSyncStateProvider.overrideWithValue(
            const PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: null,
            ),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container
          .read(planningSyncControllerProvider)
          .handleActiveContextChanged(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            refresh: false,
          );

      final writeService = container.read(planningWriteServiceProvider);
      final createdPlan = await writeService.createPlan(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const PlanCreateDraft(
          name: 'Weekend Service',
          description: 'Draft',
        ),
      );

      var plans = await container.read(planningRepositoryProvider).listPlans();
      expect(plans, hasLength(1));
      expect(plans.single.id, createdPlan.aggregateId);
      expect(plans.single.name, 'Weekend Service Accepted');
      expect(plans.single.description, 'Draft Accepted');
      await _expectNoPendingPlanningMutations(container);

      await writeService.editPlan(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: PlanEditDraft(
          planId: createdPlan.aggregateId,
          name: 'Weekend Service Revised',
          description: 'Draft revised',
        ),
      );

      plans = await container.read(planningRepositoryProvider).listPlans();
      expect(plans.single.id, createdPlan.aggregateId);
      expect(plans.single.name, 'Weekend Service Revised Accepted');
      expect(plans.single.description, 'Draft revised Accepted');
      await _expectNoPendingPlanningMutations(container);
    },
  );

  test(
    'accepted session create/rename/delete/reorder writes reconcile into the real local projection when refreshPlanning fails',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final database = PlanningLocalDatabase.inMemory();
      final localStore = DriftPlanningLocalStore(database);
      await localStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 5, 1),
            version: 1,
          ),
        ],
        sessions: [
          CachedSessionRecord(
            id: 'session-a',
            planId: 'plan-1',
            slug: 'welcome',
            position: 10,
            name: 'Welcome',
            version: 1,
          ),
          CachedSessionRecord(
            id: 'session-b',
            planId: 'plan-1',
            slug: 'announcements',
            position: 20,
            name: 'Announcements',
            version: 1,
          ),
        ],
        items: const [],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          planningLocalDatabaseProvider.overrideWithValue(database),
          planningRemoteRefreshRepositoryProvider.overrideWithValue(
            const _FailingPlanningRemoteRefreshRepository(),
          ),
          planningMutationRemoteRepositoryProvider.overrideWithValue(
            const _AcceptedWriteFallbackPlanningMutationRemoteRepository(),
          ),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          planningSyncStateProvider.overrideWithValue(
            const PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: null,
            ),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container
          .read(planningSyncControllerProvider)
          .handleActiveContextChanged(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            refresh: false,
          );

      final writeService = container.read(planningWriteServiceProvider);
      await writeService.createSession(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const SessionCreateDraft(planId: 'plan-1', name: 'Closing'),
      );

      var detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      final createdSession = detail.sessions.singleWhere(
        (session) => session.slug == 'closing-accepted',
      );
      expect(createdSession.name, 'Closing Accepted');
      expect(
        detail.sessions.map((session) => session.id),
        orderedEquals(['session-a', 'session-b', createdSession.id]),
      );
      await _expectNoPendingPlanningMutations(container);

      await writeService.renameSession(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: SessionRenameDraft(
          sessionId: createdSession.id,
          planId: 'plan-1',
          name: 'Closing Revised',
        ),
      );

      detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      expect(
        detail.sessions
            .firstWhere((session) => session.id == createdSession.id)
            .name,
        'Closing Revised Accepted',
      );
      await _expectNoPendingPlanningMutations(container);

      await writeService.reorderSessions(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: SessionReorderDraft(
          planId: 'plan-1',
          orderedSessionIds: [createdSession.id, 'session-b', 'session-a'],
        ),
      );

      detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      expect(
        detail.sessions.map((session) => session.id),
        orderedEquals([createdSession.id, 'session-b', 'session-a']),
      );
      await _expectNoPendingPlanningMutations(container);

      await writeService.deleteSession(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const SessionDeleteDraft(
          sessionId: 'session-a',
          planId: 'plan-1',
        ),
      );

      detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      expect(
        detail.sessions.map((session) => session.id),
        orderedEquals([createdSession.id, 'session-b']),
      );
      expect(
        detail.sessions.map((session) => session.name),
        orderedEquals(const ['Closing Revised Accepted', 'Announcements']),
      );
      await _expectNoPendingPlanningMutations(container);
    },
  );

  test(
    'accepted session item create/delete/reorder writes reconcile into the real local projection when refreshPlanning fails',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.restoreSession();
      final database = PlanningLocalDatabase.inMemory();
      final songDatabase = SongCatalogDatabase.inMemory();
      final localStore = DriftPlanningLocalStore(database);
      final songStore = DriftSongCatalogStore(songDatabase);
      await localStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
            description: 'Draft',
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 5, 1),
            version: 1,
          ),
        ],
        sessions: [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            slug: 'welcome',
            position: 10,
            name: 'Welcome',
            version: 1,
          ),
        ],
        items: [
          CachedSessionItemRecord(
            id: 'item-a',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 10,
            songId: 'song-1',
            songTitle: 'Alpha',
          ),
          CachedSessionItemRecord(
            id: 'item-b',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 20,
            songId: 'song-2',
            songTitle: 'Beta',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      await songStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-3', title: 'Gamma')],
        sources: const [SongSource(id: 'song-3', source: '{title: Gamma}')],
        refreshedAt: DateTime.utc(2026, 5, 1, 12),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          planningLocalDatabaseProvider.overrideWithValue(database),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningRemoteRefreshRepositoryProvider.overrideWithValue(
            const _FailingPlanningRemoteRefreshRepository(),
          ),
          planningMutationRemoteRepositoryProvider.overrideWithValue(
            const _AcceptedWriteFallbackPlanningMutationRemoteRepository(),
          ),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          planningSyncStateProvider.overrideWithValue(
            const PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: null,
            ),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
        await songDatabase.close();
      });

      await container
          .read(planningSyncControllerProvider)
          .handleActiveContextChanged(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            refresh: false,
          );

      final writeService = container.read(planningWriteServiceProvider);
      await writeService.addSongSessionItem(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const SessionItemCreateSongDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-3',
        ),
      );

      var detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      final createdItem = detail.sessions.single.items.singleWhere(
        (item) => item.song.id == 'song-3',
      );
      expect(createdItem.song.title, 'Gamma Accepted');
      expect(
        detail.sessions.single.items.map((item) => item.id),
        orderedEquals(['item-a', 'item-b', createdItem.id]),
      );
      await _expectNoPendingPlanningMutations(container);

      await writeService.reorderSessionItems(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: SessionItemReorderDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          orderedSessionItemIds: [createdItem.id, 'item-b', 'item-a'],
        ),
      );

      detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      expect(
        detail.sessions.single.items.map((item) => item.id),
        orderedEquals([createdItem.id, 'item-b', 'item-a']),
      );
      await _expectNoPendingPlanningMutations(container);

      await writeService.deleteSessionItem(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: SessionItemDeleteDraft(
          sessionItemId: 'item-b',
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      detail = await container
          .read(planningRepositoryProvider)
          .getPlanDetail('plan-1');
      expect(
        detail.sessions.single.items.map((item) => item.id),
        orderedEquals([createdItem.id, 'item-a']),
      );
      expect(
        detail.sessions.single.items.map((item) => item.song.title),
        orderedEquals(const ['Gamma Accepted', 'Alpha']),
      );
      await _expectNoPendingPlanningMutations(container);
    },
  );

  test('barrel exports the full application provider surface', () {
    // Compile-time guard: naming each provider proves the barrel still exports
    // it after the domain split. Deliberately does NOT read them (reading
    // autoDispose catalog/planning controllers triggers async refreshes and
    // platform calls). Runtime wiring is covered by the other tests here and
    // the full app suite, which resolve these through the same barrel.
    final surface = <Object>[
      // core
      syncOverviewProvider,
      supabaseClientProvider,
      songCatalogDatabaseProvider,
      planningLocalDatabaseProvider,
      // auth
      authRepositoryProvider,
      activeOrganizationResolutionProvider,
      appAuthControllerProvider,
      lastKnownIdentityDatabaseProvider,
      lastKnownIdentityStoreProvider,
      lastKnownIdentityPersistenceProvider,
      invitationRepositoryProvider,
      pendingInviteTokenControllerProvider,
      redeemControllerProvider,
      deepLinkListenerProvider,
      activeMembershipControllerProvider,
      membershipResolutionProvider,
      membershipRefreshEffectProvider,
      appAuthListenableProvider,
      activeOrganizationReaderProvider,
      capabilityResolverProvider,
      // song catalog
      songCatalogStoreProvider,
      supabaseSongRepositoryProvider,
      catalogSessionVerifierProvider,
      appForegroundStateProvider,
      songCatalogControllerProvider,
      activeCatalogContextProvider,
      catalogSnapshotStateProvider,
      // planning
      verifiedEmptyMembershipCleanupCoordinatorProvider,
      planningLocalStoreProvider,
      planningMutationStoreProvider,
      planningLocalReadRepositoryProvider,
      planningWriteServiceProvider,
      planningRemoteRefreshRepositoryProvider,
      planningMutationRemoteRepositoryProvider,
      planningMutationSyncControllerProvider,
      planningRepositoryProvider,
      activePlanningContextControllerProvider,
      activePlanningContextProvider,
      planningSyncControllerProvider,
      planningSyncStateProvider,
    ];

    expect(surface, hasLength(40));
    expect(surface.toSet(), hasLength(40)); // all distinct symbols
    expect(closeSharedDatabases, isA<Function>());
  });
}

Future<void> _expectNoPendingPlanningMutations(
  ProviderContainer container,
) async {
  expect(
    await container
        .read(planningMutationStoreProvider)
        .readPendingMutations(userId: 'user-1', organizationId: 'org-1'),
    isEmpty,
  );
  expect(
    await container
        .read(planningMutationStoreProvider)
        .hasUnsyncedMutations(userId: 'user-1'),
    isFalse,
  );
}

class _FailingPlanningRemoteRefreshRepository
    implements PlanningRemoteRefreshRepository {
  const _FailingPlanningRemoteRefreshRepository();

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    throw Exception('offline');
  }
}

class _AcceptedWriteFallbackPlanningMutationRemoteRepository
    implements PlanningMutationRemoteRepository {
  const _AcceptedWriteFallbackPlanningMutationRemoteRepository();

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    switch (record.kind) {
      case PlanningMutationKind.planCreate:
        return record.copyWith(
          slug: '${record.slug}-accepted',
          name: '${record.name} Accepted',
          description: '${record.description} Accepted',
        );
      case PlanningMutationKind.planEdit:
        return record.copyWith(
          name: '${record.name} Accepted',
          description: '${record.description} Accepted',
        );
      case PlanningMutationKind.sessionCreate:
        return record.copyWith(
          slug: '${record.slug}-accepted',
          name: '${record.name} Accepted',
        );
      case PlanningMutationKind.sessionRename:
        return record.copyWith(name: '${record.name} Accepted');
      case PlanningMutationKind.sessionDelete:
      case PlanningMutationKind.sessionReorder:
        return record;
      case PlanningMutationKind.sessionItemCreateSong:
        return record.copyWith(songTitle: '${record.songTitle} Accepted');
      case PlanningMutationKind.sessionItemDelete:
      case PlanningMutationKind.sessionItemReorder:
        return record;
    }
  }
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

class _ControllableAuthRepository implements AuthRepository {
  final StreamController<AppAuthSession?> _controller =
      StreamController<AppAuthSession?>.broadcast();

  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local');

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {
    _controller.add(
      const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
    );
  }

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {}

  void emitSession(AppAuthSession? session) {
    _controller.add(session);
  }
}

class _FakeLastKnownIdentityStore implements LastKnownIdentityStore {
  LastKnownIdentity? value;

  @override
  Future<LastKnownIdentity?> read() async => value;

  @override
  Future<void> write(LastKnownIdentity identity) async {
    value = identity;
  }

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<EmptyMembershipResolutionOutcome> resolveEmptyMembership({
    required String userId,
  }) async => const EmptyMembershipResolutionIgnored();

  @override
  Future<bool> clearMembershipRevocation({required String userId}) async =>
      false;

  @override
  Future<bool> hasCurrentMembershipRevocationMarker({
    required String userId,
    required DateTime markedAt,
  }) async => false;
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
  // Stub for docs/specs/2026-08-06-in-flight-create-cancellation.md (D3):
  // none of these tests exercise the in-flight-create-cancellation
  // tombstone path, which is covered against the real
  // DriftPlanningMutationStore in
  // test/offline/adversarial/planning_in_flight_create_cancellation_test.dart.
  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) async => false;
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
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async => false;

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
  Future<void> syncPendingMutations(
    ActivePlanningReadContext context, {
    PlanningMutationFailureObserver? onMutationFailure,
  }) async {
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
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.deleteSyncedSessionItem(
      userId: userId,
      organizationId: organizationId,
      sessionId: sessionId,
      sessionItemId: sessionItemId,
      sessionVersion: sessionVersion,
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
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.replaceSyncedSessionItemOrder(
      userId: userId,
      organizationId: organizationId,
      sessionId: sessionId,
      orderedSessionItemIds: orderedSessionItemIds,
      orderedSessionItemPositions: orderedSessionItemPositions,
      sessionVersion: sessionVersion,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.replaceSyncedSessionOrder(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
      orderedSessionIds: orderedSessionIds,
      orderedSessionPositions: orderedSessionPositions,
      planVersion: planVersion,
      refreshedAt: refreshedAt,
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

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.upsertSyncedSessionItem(
      userId: userId,
      organizationId: organizationId,
      item: item,
      sessionVersion: sessionVersion,
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

class _TestAppForegroundState implements AppForegroundState {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isForeground = true;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> watchForeground() => _controller.stream;

  void setForeground(bool value) {
    _isForeground = value;
    _controller.add(value);
  }
}
