import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
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
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/sync/sync_overview.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_mutation_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/local_store_contract.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/offline/sync_policy.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:lyron_app/src/presentation/song_library/song_library_providers.dart';

String? selectActiveOrganizationId(Object? response) {
  if (response is! List) {
    return null;
  }

  final organizationIds = response.whereType<String>().toList(growable: false);
  if (organizationIds.isEmpty) {
    return null;
  }

  final sortedOrganizationIds = organizationIds.toList()..sort();
  return sortedOrganizationIds.first;
}

final syncOverviewProvider = Provider<SyncOverview>((ref) {
  return const SyncOverview(
    storeContract: defaultLocalStoreContract,
    policy: defaultSyncPolicy,
  );
});

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.read(supabaseClientProvider));
});

final appAuthControllerProvider = Provider<AppAuthController>((ref) {
  final controller = AppAuthController(ref.read(authRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

final appAuthListenableProvider = Provider<Listenable>((ref) {
  return ref.read(appAuthControllerProvider);
});

final songCatalogDatabaseProvider = Provider<SongCatalogDatabase>((ref) {
  final database = SongCatalogDatabase.local();
  ref.onDispose(database.close);
  return database;
});

final songCatalogStoreProvider = Provider<SongCatalogStore>((ref) {
  return DriftSongCatalogStore(ref.watch(songCatalogDatabaseProvider));
});

final planningLocalDatabaseProvider = Provider<PlanningLocalDatabase>((ref) {
  final database = PlanningLocalDatabase.local();
  ref.onDispose(database.close);
  return database;
});

final planningLocalStoreProvider = Provider<PlanningLocalStore>((ref) {
  return DriftPlanningLocalStore(ref.watch(planningLocalDatabaseProvider));
});

final planningMutationStoreProvider = Provider<PlanningMutationStore>((ref) {
  return DriftPlanningMutationStore(
    database: ref.watch(planningLocalDatabaseProvider),
    localStore: ref.watch(planningLocalStoreProvider),
  );
});

final supabaseSongRepositoryProvider = Provider<SupabaseSongRepository>((ref) {
  return SupabaseSongRepository(ref.watch(supabaseClientProvider));
});

final planningLocalReadRepositoryProvider =
    Provider<PlanningLocalReadRepository>((ref) {
      return PlanningLocalReadRepository(
        store: ref.watch(planningLocalStoreProvider),
        mutationStore: ref.watch(planningMutationStoreProvider),
        contextReader: () async {
          final syncState = ref.read(planningSyncStateProvider);
          final userId = syncState.userId;
          final organizationId = syncState.organizationId;
          if (userId == null || organizationId == null) {
            return null;
          }
          return ActivePlanningReadContext(
            userId: userId,
            organizationId: organizationId,
          );
        },
      );
    });

final planningWriteServiceProvider = Provider<PlanningWriteService>((ref) {
  return PlanningWriteService(
    ref.watch(planningRepositoryProvider),
    mutationStore: ref.watch(planningMutationStoreProvider),
    activeContextReader: () async => ref.read(activePlanningContextProvider),
    syncScheduler: (context) async {
      final activeContext = ref.read(activePlanningContextProvider);
      if (activeContext == null ||
          activeContext.userId != context.userId ||
          activeContext.organizationId != context.organizationId) {
        return;
      }
      try {
        await ref
            .read(planningMutationSyncControllerProvider)
            .syncPendingMutations(activeContext);
      } finally {
        ref.read(planningDataRevisionProvider.notifier).state += 1;
      }
    },
  );
});

final planningRemoteRefreshRepositoryProvider =
    Provider<PlanningRemoteRefreshRepository>((ref) {
      return SupabasePlanningRepository(ref.watch(supabaseClientProvider));
    });

final planningMutationRemoteRepositoryProvider =
    Provider<PlanningMutationRemoteRepository>((ref) {
      return SupabasePlanningMutationRepository(ref.watch(supabaseClientProvider));
    });

final planningMutationSyncControllerProvider =
    Provider<PlanningMutationSyncController>((ref) {
      return PlanningMutationSyncController(
        mutationStore: () => ref.read(planningMutationStoreProvider),
        remoteRepository: () => ref.read(planningMutationRemoteRepositoryProvider),
        refreshPlanning: () => ref.read(planningSyncControllerProvider).refreshPlanning(),
      );
    });

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  return ref.watch(planningLocalReadRepositoryProvider);
});

final activeOrganizationReaderProvider = Provider<ActiveOrganizationReader>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);

  return () async {
    final response = await client.rpc('current_organization_ids');
    return selectActiveOrganizationId(response);
  };
});

final activePlanningContextControllerProvider =
    ChangeNotifierProvider<ActivePlanningContextController>((ref) {
      final authController = ref.watch(appAuthControllerProvider);
      final controller = ActivePlanningContextController(
        authSessionReader: () => authController.state.session,
        organizationReader: () => ref.read(activeOrganizationReaderProvider)(),
        latestOrganizationReader: ({required userId}) {
          return ref
              .read(planningLocalStoreProvider)
              .readLatestCachedOrganizationId(userId: userId);
        },
      );

      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
          case AppAuthStatus.sessionExpired:
            controller.clear();
            return;
          case AppAuthStatus.signedIn:
            unawaited(
              controller.refresh(allowCachedFallback: controller.state == null),
            );
            return;
        }
      }

      void authListener() {
        handleAuthStateChanged(authController.state);
      }

      ref.listen<ActiveCatalogContext?>(activeCatalogContextProvider, (
        _,
        next,
      ) {
        controller.syncToCatalogContext(next);
      });

      authController.addListener(authListener);
      ref.onDispose(() => authController.removeListener(authListener));
      handleAuthStateChanged(authController.state);
      return controller;
    });

final activePlanningContextProvider = Provider<ActivePlanningReadContext?>((
  ref,
) {
  return ref.watch(activePlanningContextControllerProvider).state;
});

final planningSyncControllerProvider =
    ChangeNotifierProvider<PlanningSyncController>((ref) {
      final authController = ref.watch(appAuthControllerProvider);
      final controller = PlanningSyncController(
        localStore: () => ref.read(planningLocalStoreProvider),
        remoteRepository: () =>
            ref.read(planningRemoteRefreshRepositoryProvider),
        authSessionReader: () => authController.state.session,
      );

      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
          case AppAuthStatus.sessionExpired:
            controller.handleSessionExpired();
            return;
          case AppAuthStatus.signedIn:
            return;
        }
      }

      ref.listen<ActivePlanningReadContext?>(activePlanningContextProvider, (
        _,
        next,
      ) {
        unawaited(controller.handleActiveContextChanged(next));
      });

      void authListener() {
        handleAuthStateChanged(authController.state);
      }

      authController.addListener(authListener);
      ref.onDispose(() => authController.removeListener(authListener));
      final activeContext = ref.read(activePlanningContextProvider);
      if (activeContext != null) {
        unawaited(controller.handleActiveContextChanged(activeContext));
      }
      handleAuthStateChanged(authController.state);
      return controller;
    });

final planningSyncStateProvider = Provider<PlanningSyncState>((ref) {
  return ref.watch(planningSyncControllerProvider).state;
});

final catalogSessionVerifierProvider = Provider<CatalogSessionVerifier>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return () async {
    if (client.auth.currentSession == null) {
      return CatalogSessionStatus.expired;
    }

    try {
      await client.auth.getUser();
      return CatalogSessionStatus.verified;
    } on AuthException catch (error) {
      return isConnectivityFailure(error)
          ? CatalogSessionStatus.unverifiableDueToConnectivity
          : CatalogSessionStatus.expired;
    } on SocketException catch (error) {
      return isConnectivityFailure(error)
          ? CatalogSessionStatus.unverifiableDueToConnectivity
          : CatalogSessionStatus.expired;
    } on TimeoutException catch (error) {
      return isConnectivityFailure(error)
          ? CatalogSessionStatus.unverifiableDueToConnectivity
          : CatalogSessionStatus.expired;
    } on Object catch (error) {
      if (isConnectivityFailure(error)) {
        return CatalogSessionStatus.unverifiableDueToConnectivity;
      }
      rethrow;
    }
  };
});

final appForegroundStateProvider = Provider<AppForegroundState>((ref) {
  final foregroundState = WidgetsBindingAppForegroundState();
  ref.onDispose(foregroundState.dispose);
  return foregroundState;
});

final songCatalogControllerProvider =
    ChangeNotifierProvider.autoDispose<SongCatalogController>((ref) {
      final authController = ref.watch(appAuthControllerProvider);
      final controller = SongCatalogController(
        store: ref.watch(songCatalogStoreProvider),
        remoteRepository: ref.watch(supabaseSongRepositoryProvider),
        authSessionReader: () => authController.state.session,
        organizationReader: ref.watch(activeOrganizationReaderProvider),
        sessionVerifier: ref.watch(catalogSessionVerifierProvider),
        foregroundState: ref.watch(appForegroundStateProvider),
      );

      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
          case AppAuthStatus.sessionExpired:
            controller.handleSessionExpired();
            return;
          case AppAuthStatus.signedIn:
            controller.handleSessionAvailable();
            unawaited(controller.refreshCatalog());
            return;
        }
      }

      void authListener() {
        handleAuthStateChanged(authController.state);
      }

      authController.addListener(authListener);
      ref.onDispose(() => authController.removeListener(authListener));
      handleAuthStateChanged(authController.state);
      unawaited(controller.refreshCatalog());
      return controller;
    });

final activeCatalogContextProvider =
    Provider.autoDispose<ActiveCatalogContext?>((ref) {
      return ref.watch(songCatalogControllerProvider).state.context;
    });

final catalogSnapshotStateProvider = Provider.autoDispose<CatalogSnapshotState>(
  (ref) {
    return ref.watch(songCatalogControllerProvider).state;
  },
);
