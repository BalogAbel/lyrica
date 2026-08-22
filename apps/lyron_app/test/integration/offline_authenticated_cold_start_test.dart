// Integration coverage for Task 1.5 of
// docs/specs/2026-08-19-local-data-durability-contract.md: proves that the
// offline-authenticated cold-start fix built in Tasks 1.1-1.4 actually holds
// end to end, through the real provider graph, for the acceptance criteria
// that are fundamentally about offline auth-stream edge cases:
//
//   1. Cold start, offline, expired access token, valid refresh token ->
//      songs visible, zero deletions. (This one turns out to be handled by
//      pre-existing connectivity-failure/ADR-016 code, not by Tasks
//      1.1-1.4 -- see the test's own doc comment below.)
//   2. Cold start, offline, gotrue emits `signedOut` -> zero deletions,
//      `sessionExpired`, songs visible.
//   3. Persisted session removed from SharedPreferences while
//      `LastKnownIdentity` survives -> zero deletions, songs visible.
//   7. Simulated multi-day offline span with repeated cold starts -> songs
//      remain visible on every cold start.
//
// Deliberately does NOT follow the pattern most of test/integration/ uses
// (signing in against a real local Supabase backend via
// SupabaseConfig.fromEnvironment()): none of the above conditions are
// naturally reproducible against a live backend, and depending on one here
// would make these tests flaky/non-deterministic for exactly the property
// they are supposed to nail down deterministically. Instead this mirrors the
// full-ProviderContainer-with-fakes pattern already proven correct in
// test/application/providers_test.dart and
// test/application/auth/app_auth_controller_test.dart: a fully controllable
// fake AuthRepository, an in-memory fake LastKnownIdentityStore, and a REAL
// in-memory Drift SongCatalogDatabase/DriftSongCatalogStore so the actual
// local-read path is exercised -- only the network/auth boundary is faked.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../support/drift_test_setup.dart';

// Trivial LocalDataLifecycle wrapping the test's real song catalog store, for
// tests that only exercise catalog refresh/offline-authenticated paths --
// planning/identity/events deps are never invoked by these flows.
LocalDataLifecycle _lifecycleFor(SongCatalogStore store) {
  return LocalDataLifecycle(
    songCatalogStore: store,
    planningLocalStore: _NoopPlanningLocalStore(),
    identityStore: _NoopLastKnownIdentityStore(),
    noteLastKnownIdentity: (_) {},
    eventsRecorder: _NoopLocalDataEventsRecorder(),
  );
}

class _NoopPlanningLocalStore implements PlanningLocalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLastKnownIdentityStore implements LastKnownIdentityStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}
}

const _identity = LastKnownIdentity(
  userId: 'user-1',
  email: 'demo@lyron.local',
  organizationId: 'org-1',
);

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('offline cold start with an already-expired-but-present session stays '
      'signedIn and shows the cached catalog via the pre-existing '
      'connectivity-failure fallback (ADR-016)', () async {
    // REGRESSION GUARD, not proof of Tasks 1.1-1.4's offline-authenticated
    // machinery -- that is Acceptance 2 and Acceptance 3 below, both of
    // which drive a genuinely null session. This test instead confirms
    // that Task 1.2's _stateForSession change did not disturb the
    // pre-existing signedIn + connectivity-failure fallback path this
    // scenario actually takes.
    //
    // Verified against the pinned gotrue/supabase_flutter source (see
    // docs/specs/2026-08-19-local-data-durability-contract.md, F1):
    // SupabaseAuth.initialize() calls GoTrueClient.setInitialSession(),
    // which installs the persisted session unconditionally -- no expiry
    // check, no refresh attempt -- so client.auth.currentSession stays
    // non-null even when its access token has expired and there is no
    // network to refresh it. AuthRepository.restoreSession() (this app's
    // one seam onto currentSession) therefore resolves to a NON-null
    // session here, and AppAuthController converges on signedIn, never
    // sessionExpired. The background auto-refresh tick does then fail
    // (offline == AuthRetryableFetchException, a RETRYABLE error), but
    // _doRefresh's catch block only clears the session for a
    // NON-retryable failure; a retryable one just rethrows, leaving the
    // session untouched.
    //
    // So this scenario never reaches sessionExpired or
    // handleOfflineAuthenticated() at all. It is handled entirely by
    // pre-existing code: SongCatalogController._refreshCatalog's
    // connectivity-failure branches, which fall back to the cached
    // organization id (SongCatalogStore.readLatestCachedOrganizationId)
    // and surface the cached catalog with
    // CatalogSessionStatus.unverifiableDueToConnectivity /
    // CatalogConnectionStatus.offlineCached -- the ADR-016 cached-org
    // fallback documented in
    // docs/architecture/decisions/ADR-016-active-organization-resolution-semantics.md.
    final identityStore = _FakeLastKnownIdentityStore()..value = _identity;
    final authRepository = _OfflineAuthRepository()
      ..restoredSession = const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
        linkedProviders: [],
      );
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );

    await authController.restoreSession();
    expect(authController.state.status, AppAuthStatus.signedIn);
    expect(authController.state.status, isNot(AppAuthStatus.sessionExpired));

    final songDatabase = SongCatalogDatabase.inMemory();
    final baseStore = DriftSongCatalogStore(songDatabase);
    final countingStore = _DeleteCountingSongCatalogStore(baseStore);
    addTearDown(() async {
      await songDatabase.close();
    });

    await baseStore.replaceActiveSnapshot(
      userId: 'user-1',
      organizationId: 'org-1',
      summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
      refreshedAt: DateTime.utc(2026, 8, 1, 12),
    );

    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        songCatalogStoreProvider.overrideWithValue(countingStore),
        // The session verifier below already resolves to
        // unverifiableDueToConnectivity, which makes _refreshCatalog
        // return before ever reaching the remote repository. Kept as a
        // defense-in-depth trap, same as the shared helper's overrides.
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async =>
                throw StateError('remote must not be called while offline'),
            getSongRow: (id) async =>
                throw StateError('remote must not be called while offline'),
          ),
        ),
        // Simulates the org lookup failing for lack of network. Thrown as
        // a real connectivity-failure-shaped exception (see
        // isConnectivityFailure in connectivity_failure.dart) so
        // SongCatalogController._refreshCatalog classifies it as a
        // connectivity failure, not an authorization failure, and falls
        // back to SongCatalogStore.readLatestCachedOrganizationId
        // (ADR-016).
        activeOrganizationReaderProvider.overrideWithValue(
          () async => throw const SocketException('Failed host lookup'),
        ),
        // Simulates the session verifier being unable to reach the
        // backend. Returned directly as the status the real
        // catalogSessionVerifierProvider itself translates a connectivity
        // exception into (see song_catalog_providers.dart): that provider
        // catches SocketException/TimeoutException/AuthException
        // internally and never lets them escape as a raw throw, and
        // _refreshCatalog's call site has no try/catch around it to
        // survive one -- so a fake that threw here would not match the
        // real contract and would fail this test.
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.unverifiableDueToConnectivity,
        ),
        appForegroundStateProvider.overrideWithValue(_TestAppForegroundState()),
      ],
    );
    addTearDown(container.dispose);
    final subscriptions = _keepAlive(container);
    for (final subscription in subscriptions) {
      addTearDown(subscription.close);
    }

    // The provider wiring already triggered refreshCatalog() once,
    // fire-and-forget, the moment songCatalogControllerProvider was first
    // built (handleAuthStateChanged(authController.state) for the
    // signedIn case calls handleSessionAvailable() + refreshCatalog()).
    // Calling it again here explicitly coalesces with that in-flight call
    // (same session identity) and lets the test await completion
    // deterministically instead of racing an unawaited Future.
    await container.read(songCatalogControllerProvider).refreshCatalog();

    final snapshotState = container.read(catalogSnapshotStateProvider);
    expect(
      snapshotState.sessionStatus,
      CatalogSessionStatus.unverifiableDueToConnectivity,
    );
    expect(
      snapshotState.connectionStatus,
      CatalogConnectionStatus.offlineCached,
    );
    expect(
      container.read(activeCatalogContextProvider),
      const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
    );
    final songs = await container.read(songLibraryListProvider.future);
    expect(songs, hasLength(1));
    expect(songs.single.title, 'Cached Song');

    expect(countingStore.totalDeleteCalls, 0);
  });

  test('acceptance 2: offline cold start where the auth stream itself emits '
      'signedOut converges on sessionExpired, not signedOut, with zero '
      'deletions', () async {
    final identityStore = _FakeLastKnownIdentityStore()..value = _identity;
    final authRepository = _OfflineAuthRepository();
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );

    // Let the identity load settle before the stream emits (mirroring
    // app_auth_controller_test.dart's cold-start pattern), so the event
    // below is evaluated immediately against the loaded identity instead
    // of being buffered until the load completes.
    await Future<void>.delayed(Duration.zero);

    // This models gotrue's own cold-start `signedOut` event landing on the
    // auth stream -- the literal acceptance-criteria condition -- WITHOUT
    // restoreSession() ever having been awaited. AppAuthController's D2
    // rule (_stateForSession) must map this to sessionExpired, never the
    // destructive signedOut, because a LastKnownIdentity is on file.
    authRepository.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(authController.state.status, AppAuthStatus.sessionExpired);
    expect(authController.state.status, isNot(AppAuthStatus.signedOut));

    await _runOfflineColdStartScenario(
      authController: authController,
      identityStore: identityStore,
    );
  });

  test(
    'acceptance 3: a persisted session removed from SharedPreferences while '
    'LastKnownIdentity survives shows the cached songs with zero deletions',
    () async {
      // AuthRepository.restoreSession() is the only seam this app has onto
      // SharedPreferences' persisted session -- the app never reads
      // SharedPreferences directly. A session entry that has been wiped
      // (not merely stale) surfaces exactly the same way as acceptance 1's
      // expired-access-token case: restoreSession() resolving to null, with
      // no error. That is intentional, not an oversight -- the two root
      // causes are genuinely indistinguishable at this app's boundary; see
      // docs/specs/2026-08-19-local-data-durability-contract.md and this
      // task's own guidance. What distinguishes acceptance 3 here is that
      // the LastKnownIdentity store is a SEPARATE persistence mechanism from
      // the wiped session, and survives independently -- proven below by
      // constructing the identity store pre-populated while the auth
      // repository has genuinely nothing to restore.
      final identityStore = _FakeLastKnownIdentityStore()..value = _identity;
      final authRepository = _OfflineAuthRepository();
      final authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );

      await authController.restoreSession();
      expect(authController.state.status, AppAuthStatus.sessionExpired);
      expect(authController.state.status, isNot(AppAuthStatus.signedOut));
      expect(authController.state.lastKnownSession?.userId, 'user-1');

      await _runOfflineColdStartScenario(
        authController: authController,
        identityStore: identityStore,
      );
    },
  );

  test(
    'acceptance 7: songs stay visible with zero deletions across repeated '
    'offline cold starts spanning a simulated multi-day offline span',
    () async {
      // There is no TTL/wall-clock check anywhere in the read path after
      // Tasks 1.1-1.4 (that is the entire point of D2 -- token TTL is
      // irrelevant to local-data durability now), so there is no clock to
      // inject. Instead this proves the real property the "advanced clock"
      // criterion is about: repeating the full cold-start cycle multiple
      // times (simulating separate days/relaunches) against the SAME
      // persisted LastKnownIdentityStore and SongCatalogStore state, with a
      // fresh AppAuthController/SongCatalogController/ProviderContainer each
      // cycle (like a real app relaunch), asserting songs stay visible and
      // deletions stay at zero on EVERY cycle, not just the first.
      final identityStore = _FakeLastKnownIdentityStore()..value = _identity;
      final songDatabase = SongCatalogDatabase.inMemory();
      final baseStore = DriftSongCatalogStore(songDatabase);
      final countingStore = _DeleteCountingSongCatalogStore(baseStore);
      addTearDown(() async {
        await songDatabase.close();
      });

      await baseStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 8, 1, 12),
      );

      for (var cycle = 1; cycle <= 3; cycle += 1) {
        final authRepository = _OfflineAuthRepository();
        final authController = AppAuthController(
          authRepository,
          lastKnownIdentityStore: identityStore,
        );
        await authController.restoreSession();
        expect(
          authController.state.status,
          AppAuthStatus.sessionExpired,
          reason: 'cycle $cycle must stay offline-authenticated',
        );
        expect(
          authController.state.status,
          isNot(AppAuthStatus.signedOut),
          reason: 'cycle $cycle must never regress to a destructive state',
        );

        final container = ProviderContainer(
          overrides: _offlineOverrides(
            authController: authController,
            songCatalogStore: countingStore,
          ),
        );
        final subscriptions = _keepAlive(container);

        await container
            .read(songCatalogControllerProvider)
            .handleOfflineAuthenticated();

        expect(
          container.read(catalogSnapshotStateProvider).sessionStatus,
          CatalogSessionStatus.expired,
          reason: 'cycle $cycle',
        );
        expect(
          container.read(activeCatalogContextProvider),
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
          reason: 'cycle $cycle',
        );
        final songs = await container.read(songLibraryListProvider.future);
        expect(songs, hasLength(1), reason: 'cycle $cycle');
        expect(songs.single.title, 'Cached Song', reason: 'cycle $cycle');
        expect(
          countingStore.totalDeleteCalls,
          0,
          reason: 'cycle $cycle must not have deleted anything',
        );

        for (final subscription in subscriptions) {
          subscription.close();
        }
        container.dispose();
      }

      expect(await identityStore.read(), isNotNull);
      expect(countingStore.totalDeleteCalls, 0);
    },
  );

  test(
    'a concurrent online refreshCatalog() completing while '
    "handleOfflineAuthenticated()'s local read is still in flight is not "
    'clobbered once that stale read resolves -- PR #73 review finding 1',
    () async {
      final songDatabase = SongCatalogDatabase.inMemory();
      final baseStore = DriftSongCatalogStore(songDatabase);
      final gatedStore = _DeleteCountingSongCatalogStore(baseStore);
      addTearDown(() async {
        await songDatabase.close();
      });

      await baseStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 8, 1, 12),
      );

      AppAuthSession? currentSession; // starts null: offline cold start.
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
      final controller = SongCatalogController(
        store: gatedStore,
        localDataLifecycle: _lifecycleFor(gatedStore),
        remoteRepository: remoteRepository,
        authSessionReader: () => currentSession,
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        lastKnownIdentityReader: () =>
            (userId: 'user-1', organizationId: 'org-1'),
      );

      // Mirrors song_catalog_providers.dart's sessionExpired wiring:
      // handleSessionExpired() then handleOfflineAuthenticated(). Its local
      // read is the NEXT call to readActiveSummaries(), which the gate
      // holds open.
      final gate = Completer<void>();
      gatedStore.readActiveSummariesGate = gate;
      controller.handleSessionExpired();
      final offlineFuture = controller.handleOfflineAuthenticated();

      // Connectivity returns moments later: the auth stream flips to
      // signedIn and a real refresh runs to completion BEFORE the offline
      // read above has resolved. Its own call to readActiveSummaries() is
      // NOT gated (the gate is consumed by the first call, above), so it
      // proceeds and finishes normally.
      currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      );
      controller.handleSessionAvailable();
      await controller.refreshCatalog();

      expect(controller.state.connectionStatus, CatalogConnectionStatus.online);
      expect(controller.state.sessionStatus, CatalogSessionStatus.verified);

      // Now release the stale offline read.
      gate.complete();
      await offlineFuture;

      // The fresh online state must survive -- not be clobbered by the
      // now-resolving, now-stale offline result.
      expect(controller.state.connectionStatus, CatalogConnectionStatus.online);
      expect(controller.state.sessionStatus, CatalogSessionStatus.verified);
      expect(
        controller.state.context,
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
    },
  );
}

/// Shared drive-and-assert body for acceptances 1, 2, and 3: builds the
/// full provider graph over the given (already offline-authenticated)
/// [authController], seeds a cached snapshot, drives the offline cold-start
/// read path, and asserts songs are visible with zero deletions.
Future<void> _runOfflineColdStartScenario({
  required AppAuthController authController,
  required _FakeLastKnownIdentityStore identityStore,
}) async {
  final songDatabase = SongCatalogDatabase.inMemory();
  final baseStore = DriftSongCatalogStore(songDatabase);
  final countingStore = _DeleteCountingSongCatalogStore(baseStore);
  addTearDown(() async {
    await songDatabase.close();
  });

  await baseStore.replaceActiveSnapshot(
    userId: 'user-1',
    organizationId: 'org-1',
    summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
    sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
    refreshedAt: DateTime.utc(2026, 8, 1, 12),
  );

  final container = ProviderContainer(
    overrides: _offlineOverrides(
      authController: authController,
      songCatalogStore: countingStore,
    ),
  );
  addTearDown(container.dispose);
  final subscriptions = _keepAlive(container);
  for (final subscription in subscriptions) {
    addTearDown(subscription.close);
  }

  // Drive the exact offline-authenticated cold-start method Tasks 1.1-1.4
  // added (SongCatalogController.handleOfflineAuthenticated()). The
  // provider wiring in song_catalog_providers.dart already triggers this
  // once, fire-and-forget, the moment songCatalogControllerProvider is
  // first built (its handleAuthStateChanged(authController.state) call) --
  // calling it again here explicitly is idempotent (it bails out once
  // _state.context is already set) and lets the test await completion
  // deterministically instead of racing an unawaited Future.
  await container
      .read(songCatalogControllerProvider)
      .handleOfflineAuthenticated();

  expect(
    container.read(catalogSnapshotStateProvider).sessionStatus,
    CatalogSessionStatus.expired,
  );
  expect(
    container.read(activeCatalogContextProvider),
    const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
  );
  final songs = await container.read(songLibraryListProvider.future);
  expect(songs, hasLength(1));
  expect(songs.single.title, 'Cached Song');

  // Zero deletions, proven by a call counter on the real store, not
  // inferred from the songs still being readable.
  expect(countingStore.deleteSongCalls, 0);
  expect(countingStore.deleteCatalogsForUserCalls, 0);
  expect(countingStore.deleteCatalogCalls, 0);
  expect(countingStore.totalDeleteCalls, 0);
}

List<Override> _offlineOverrides({
  required AppAuthController authController,
  required SongCatalogStore songCatalogStore,
}) {
  return [
    appAuthControllerProvider.overrideWith((_) => authController),
    songCatalogStoreProvider.overrideWithValue(songCatalogStore),
    // The remote repository must never be reached while offline -- any call
    // fails loudly instead of silently succeeding, which would mask a
    // regression that accidentally routes the cold-start path over the
    // network.
    supabaseSongRepositoryProvider.overrideWithValue(
      SupabaseSongRepository.testing(
        listSongsRows: () async =>
            throw StateError('remote must not be called while offline'),
        getSongRow: (id) async =>
            throw StateError('remote must not be called while offline'),
      ),
    ),
    catalogSessionVerifierProvider.overrideWithValue(
      () async => throw StateError(
        'session verifier must not be called by the offline-authenticated '
        'cold-start path',
      ),
    ),
    activeOrganizationReaderProvider.overrideWithValue(
      () async => throw StateError(
        'organization reader must not be called by the offline-authenticated '
        'cold-start path',
      ),
    ),
    appForegroundStateProvider.overrideWithValue(_TestAppForegroundState()),
  ];
}

/// Riverpod disposes autoDispose providers once they have no listeners;
/// mirrors providers_test.dart's pattern of subscribing to the
/// autoDispose-dependent providers under test so they stay alive across the
/// `await`s below instead of being torn down between reads.
List<ProviderSubscription<Object?>> _keepAlive(ProviderContainer container) {
  return [
    container.listen(
      activeCatalogContextProvider,
      (_, _) {},
      fireImmediately: true,
    ),
    container.listen(songLibraryListProvider, (_, _) {}, fireImmediately: true),
  ];
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
}

/// A fully controllable AuthRepository fake, mirroring
/// app_auth_controller_test.dart's `_FakeAuthRepository`: restoreSession()
/// returns whatever [restoredSession] currently holds (null by default,
/// modelling "nothing to restore" -- an expired token with no network to
/// refresh it, or a wiped SharedPreferences entry, are the same observation
/// from this app's boundary), and [emit] drives the auth stream
/// independently to model a gotrue-originated event such as `signedOut`.
class _OfflineAuthRepository implements AuthRepository {
  AppAuthSession? restoredSession;
  final StreamController<AppAuthSession?> _controller =
      StreamController<AppAuthSession?>.broadcast();

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

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

/// Wraps a real [DriftSongCatalogStore], delegating every method, while
/// counting calls to every delete-shaped method on the [SongCatalogStore]
/// interface: `deleteSong`, `deleteCatalogsForUser`, `deleteCatalog`,
/// `clearSongMutation`, and the `created: false` branch of
/// `resolveCancelledSongCreate` (which discards a cancellation tombstone
/// outright -- see that method's doc comment on [SongCatalogStore] -- while
/// the `created: true` branch only rewrites a row's status, so it is not
/// counted). Used to PROVE "zero deletions" via an actual call counter
/// against the real local-read path, rather than inferring it from the songs
/// still being readable afterwards. Mirrors the spirit of
/// providers_test.dart's `_BlockingDeletePlanningLocalStore` (the equivalent
/// decorator already proven correct for the planning store).
class _DeleteCountingSongCatalogStore implements SongCatalogStore {
  _DeleteCountingSongCatalogStore(this._delegate);

  final SongCatalogStore _delegate;
  int deleteSongCalls = 0;
  int deleteCatalogsForUserCalls = 0;
  int deleteCatalogCalls = 0;
  int clearSongMutationCalls = 0;
  int resolveCancelledSongCreateDiscardCalls = 0;
  // When set, the NEXT call to readActiveSummaries() awaits this before
  // delegating (only the next one -- consumed on first use, so a second,
  // later call is never blocked by it). Lets a test hold
  // handleOfflineAuthenticated()'s local read mid-flight to interleave it
  // with a concurrent refreshCatalog()'s own call to the same method.
  Completer<void>? readActiveSummariesGate;

  int get totalDeleteCalls =>
      deleteSongCalls +
      deleteCatalogsForUserCalls +
      deleteCatalogCalls +
      clearSongMutationCalls +
      resolveCancelledSongCreateDiscardCalls;

  @override
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  }) => _delegate.replaceActiveSnapshot(
    userId: userId,
    organizationId: organizationId,
    summaries: summaries,
    sources: sources,
    refreshedAt: refreshedAt,
  );

  @override
  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  }) async {
    final gate = readActiveSummariesGate;
    if (gate != null) {
      readActiveSummariesGate = null;
      await gate.future;
    }
    return _delegate.readActiveSummaries(
      userId: userId,
      organizationId: organizationId,
    );
  }

  @override
  Future<SongSummary?> readActiveSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => _delegate.readActiveSummaryBySlug(
    userId: userId,
    organizationId: organizationId,
    songSlug: songSlug,
  );

  @override
  Future<SongSummary?> readActiveSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _delegate.readActiveSummaryById(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _delegate.readActiveSource(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<String?> readLatestCachedOrganizationId({required String userId}) =>
      _delegate.readLatestCachedOrganizationId(userId: userId);

  @override
  Future<void> saveSongMutation(SongCatalogMutationDraft mutation) =>
      _delegate.saveSongMutation(mutation);

  @override
  Future<bool> hasUnsyncedSongMutations({required String userId}) =>
      _delegate.hasUnsyncedSongMutations(userId: userId);

  @override
  Future<List<CachedCatalogSongMutation>> readSongMutations({
    required String userId,
    required String organizationId,
    List<SongSyncStatus>? syncStatuses,
  }) => _delegate.readSongMutations(
    userId: userId,
    organizationId: organizationId,
    syncStatuses: syncStatuses,
  );

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySongId({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _delegate.readSongMutationBySongId(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => _delegate.readSongMutationBySlug(
    userId: userId,
    organizationId: organizationId,
    songSlug: songSlug,
  );

  @override
  Future<bool> hasVisibleSongSlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => _delegate.hasVisibleSongSlug(
    userId: userId,
    organizationId: organizationId,
    songSlug: songSlug,
  );

  @override
  Future<String> allocateAvailableSongSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) => _delegate.allocateAvailableSongSlug(
    userId: userId,
    organizationId: organizationId,
    title: title,
  );

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    deleteSongCalls += 1;
    return _delegate.deleteSong(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
    int? expectedRevision,
  }) => _delegate.reconcileSyncedSong(
    userId: userId,
    organizationId: organizationId,
    summary: summary,
    source: source,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    clearSongMutationCalls += 1;
    return _delegate.clearSongMutation(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<int?> markSongCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) => _delegate.markSongCreateSending(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    expectedRevision: expectedRevision,
  );

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) {
    if (!created) {
      resolveCancelledSongCreateDiscardCalls += 1;
    }
    return _delegate.resolveCancelledSongCreate(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
      created: created,
      acceptedVersion: acceptedVersion,
    );
  }

  @override
  Future<int?> saveSongMutationStatus({
    required String userId,
    required String organizationId,
    required String songId,
    required String syncStatus,
    String? syncErrorContext,
    int? expectedRevision,
  }) => _delegate.saveSongMutationStatus(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    syncStatus: syncStatus,
    syncErrorContext: syncErrorContext,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> deleteCatalogsForUser({required String userId}) {
    deleteCatalogsForUserCalls += 1;
    return _delegate.deleteCatalogsForUser(userId: userId);
  }

  @override
  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  }) {
    deleteCatalogCalls += 1;
    return _delegate.deleteCatalog(
      userId: userId,
      organizationId: organizationId,
    );
  }
}

class _TestAppForegroundState implements AppForegroundState {
  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => const Stream<bool>.empty();
}
