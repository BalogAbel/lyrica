import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

/// Spec: docs/specs/2026-08-08-web-catalog-refresh-race.md (D2).
///
/// `songCatalogControllerProvider` must not refresh while auth is still
/// `initializing` -- a refresh at that point has no session to act on and
/// can only misreport an `expired` catalog session status. The provider
/// should refresh exactly once auth resolves to a known state, driven
/// solely through `handleAuthStateChanged`.
void main() {
  test(
    'does not refresh the catalog while auth is initializing, and refreshes '
    'exactly once auth resolves to signedIn',
    () async {
      final authRepository = _ControllableAuthRepository();
      final authController = AppAuthController(authRepository);
      // Deliberately do NOT await restoreSession yet: the controller's
      // constructor leaves state at AppAuthStatus.initializing, which is
      // the state under test.
      final songDatabase = SongCatalogDatabase.inMemory();
      final songStore = DriftSongCatalogStore(songDatabase);
      var listSongsCalls = 0;
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async {
          listSongsCalls += 1;
          return const [
            {'id': 'song-1', 'slug': 'alpha', 'title': 'Alpha', 'version': 1},
          ];
        },
        getSongRow: (id) async => const {
          'id': 'song-1',
          'slug': 'alpha',
          'chordpro_source': '{title: Alpha}',
        },
      );
      final foregroundState = _TestAppForegroundState();

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

      // Build the controller while auth is still `initializing`.
      final subscription = container.listen(
        songCatalogControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(authController.state.status.name, 'initializing');
      expect(listSongsCalls, 0);
      // A refresh fired with no session sets sessionStatus to `expired`
      // (SongCatalogController._refreshCatalog's null-session branch) even
      // though nothing has actually expired -- exactly the misleading
      // status the spec (D2) says an unconditional refresh under
      // `initializing` produces. Asserting the state stayed at its
      // untouched default catches a reintroduced unconditional refresh
      // even in cases where it wouldn't otherwise change listSongsCalls.
      expect(
        container.read(songCatalogControllerProvider).state.sessionStatus,
        isNot(CatalogSessionStatus.expired),
      );

      // Now let auth resolve to signedIn; the listener installed at
      // construction (handleAuthStateChanged) must be the thing that
      // triggers the refresh -- not a trailing unconditional call.
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);

      expect(listSongsCalls, 1);
    },
  );
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

class _TestAppForegroundState implements AppForegroundState {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => _controller.stream;
}
