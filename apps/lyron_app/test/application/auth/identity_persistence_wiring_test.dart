import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late _RecordingLastKnownIdentityStore identityStore;
  late _FakeAuthRepository authRepository;
  late AppAuthController authController;

  setUp(() async {
    identityStore = _RecordingLastKnownIdentityStore();
    authRepository = _FakeAuthRepository();
    authController = AppAuthController(authRepository);
  });

  test(
    'signedIn writes the active organization and signedOut clears the identity',
    () async {
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user@example.com',
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async =>
                const ActiveOrganizationResolution.selected('org-selected'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.userId, 'user-1');
      expect(identityStore.writes.single.email, 'user@example.com');
      expect(identityStore.writes.single.organizationId, 'org-selected');
      expect(identityStore.clearCount, 0);

      await authController.signOut();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.clearCount, 1);
      expect(authController.state.status, AppAuthStatus.signedOut);
    },
  );

  test(
    'signedIn falls back to the cached organization when active lookup is unavailable',
    () async {
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user@example.com',
      );
      final cachedDatabase = SongCatalogDatabase.inMemory();
      final cachedStore = DriftSongCatalogStore(cachedDatabase);
      await cachedStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-cached',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 6, 28, 12),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogStoreProvider.overrideWithValue(cachedStore),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async =>
                const ActiveOrganizationResolution.unknownConnectivityFailure(),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await cachedDatabase.close();
      });

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.organizationId, 'org-cached');
      expect(identityStore.clearCount, 0);
    },
  );

  test(
    'stale signedIn persistence does not rewrite after signedOut clears identity',
    () async {
      final membershipLookup = Completer<ActiveOrganizationResolution>();
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user@example.com',
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          activeOrganizationResolutionProvider.overrideWithValue(
            () => membershipLookup.future,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);

      await authController.signOut();
      await Future<void>.delayed(Duration.zero);
      membershipLookup.complete(
        const ActiveOrganizationResolution.selected('org-selected'),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.writes, isEmpty);
      expect(identityStore.clearCount, 1);
      expect(authController.state.status, AppAuthStatus.signedOut);
    },
  );

  test(
    'stale signedIn persistence does not write after sessionExpired',
    () async {
      final membershipLookup = Completer<ActiveOrganizationResolution>();
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user@example.com',
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          activeOrganizationResolutionProvider.overrideWithValue(
            () => membershipLookup.future,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);

      authRepository.emit(null);
      await Future<void>.delayed(Duration.zero);
      membershipLookup.complete(
        const ActiveOrganizationResolution.selected('org-selected'),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.writes, isEmpty);
      expect(identityStore.clearCount, 0);
      expect(authController.state.status, AppAuthStatus.sessionExpired);
    },
  );

  test(
    'stale signedIn persistence does not rewrite after verified-empty cleanup',
    () async {
      final membershipLookup = Completer<ActiveOrganizationResolution>();
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user@example.com',
      );
      final planningDatabase = PlanningLocalDatabase.inMemory();
      final songDatabase = SongCatalogDatabase.inMemory();
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () => membershipLookup.future,
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await planningDatabase.close();
        await songDatabase.close();
      });

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);

      await container
          .read(verifiedEmptyMembershipCleanupCoordinatorProvider)
          .handleVerifiedEmptyMembership(userId: 'user-1');
      membershipLookup.complete(
        const ActiveOrganizationResolution.selected('org-selected'),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.writes, isEmpty);
      expect(identityStore.clearCount, 1);
      expect(authController.state.status, AppAuthStatus.signedIn);
    },
  );

  test('sessionExpired does not clear the stored identity', () async {
    authRepository.currentSession = const AppAuthSession(
      userId: 'user-1',
      email: 'user@example.com',
    );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        activeOrganizationResolutionProvider.overrideWithValue(
          () async => const ActiveOrganizationResolution.selected('org-1'),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(appAuthListenableProvider);
    await authController.restoreSession();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    authRepository.emit(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(identityStore.writes, hasLength(1));
    expect(identityStore.clearCount, 0);
    expect(authController.state.status, AppAuthStatus.sessionExpired);
  });
}

class _RecordingLastKnownIdentityStore implements LastKnownIdentityStore {
  final List<LastKnownIdentity> writes = <LastKnownIdentity>[];
  int clearCount = 0;

  @override
  Future<LastKnownIdentity?> read() async {
    return writes.isEmpty ? null : writes.last;
  }

  @override
  Future<void> write(LastKnownIdentity identity) async {
    writes.add(identity);
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? currentSession;

  @override
  Future<AppAuthSession?> restoreSession() async => currentSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

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

  void emit(AppAuthSession? session) => _controller.add(session);
}
