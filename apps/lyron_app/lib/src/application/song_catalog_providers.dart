import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth_providers.dart';
import 'package:lyron_app/src/application/core_providers.dart';
import 'package:lyron_app/src/application/planning_providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final songCatalogStoreProvider = Provider<SongCatalogStore>((ref) {
  return DriftSongCatalogStore(
    ref.watch(songCatalogDatabaseProvider),
    onStorageFootprintChanged: ref.watch(localStorageFootprintChangedProvider),
    writeRecovery: ref.watch(localStorageWriteRecoveryProvider),
  );
});

final supabaseSongRepositoryProvider = Provider<SupabaseSongRepository>((ref) {
  return SupabaseSongRepository(ref.watch(supabaseClientProvider));
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
      final authController = ref.read(appAuthControllerProvider);
      final controller = SongCatalogController(
        store: ref.watch(songCatalogStoreProvider),
        localDataLifecycle: ref.watch(localDataLifecycleProvider),
        remoteRepository: ref.watch(supabaseSongRepositoryProvider),
        authSessionReader: () => authController.state.session,
        organizationReader: ref.watch(activeOrganizationReaderProvider),
        sessionVerifier: ref.watch(catalogSessionVerifierProvider),
        onVerifiedEmptyMembership: ({required userId}) => ref
            .read(verifiedEmptyMembershipCleanupCoordinatorProvider)
            .handleVerifiedEmptyMembership(userId: userId),
        lastKnownIdentityReader: () {
          final identity = authController.lastKnownIdentity;
          if (identity == null) return null;
          return (
            userId: identity.userId,
            organizationId: identity.organizationId,
          );
        },
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
            unawaited(controller.handleOfflineAuthenticated());
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
