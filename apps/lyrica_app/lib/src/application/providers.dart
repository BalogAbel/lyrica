import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/auth/app_auth_state.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyrica_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyrica_app/src/application/sync/sync_overview.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_status.dart';
import 'package:lyrica_app/src/infrastructure/auth/supabase_auth_repository.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyrica_app/src/offline/local_store_contract.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyrica_app/src/offline/sync_policy.dart';
import 'package:lyrica_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:lyrica_app/src/presentation/song_library/song_library_providers.dart';

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

final supabaseSongRepositoryProvider = Provider<SupabaseSongRepository>((ref) {
  return SupabaseSongRepository(ref.watch(supabaseClientProvider));
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
