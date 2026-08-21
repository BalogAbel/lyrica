// Integration coverage for Task 1.5 of
// docs/specs/2026-08-19-local-data-durability-contract.md: proves that the
// offline-authenticated cold-start fix built in Tasks 1.1-1.4 actually holds
// end to end, through the real provider graph, for the acceptance criteria
// that are fundamentally about offline auth-stream edge cases:
//
//   1. Cold start, offline, expired access token, valid refresh token ->
//      songs visible, zero deletions.
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../support/drift_test_setup.dart';

const _identity = LastKnownIdentity(
  userId: 'user-1',
  email: 'demo@lyron.local',
  organizationId: 'org-1',
);

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test(
    'acceptance 1: offline cold start with an expired access token but a '
    'valid refresh token shows the cached songs with zero deletions',
    () async {
      // From this app's perspective, an access token that has expired while
      // its refresh token would normally still be valid ONLINE surfaces,
      // OFFLINE (no network available to actually perform the refresh), as
      // AuthRepository.restoreSession() resolving to null -- there is no
      // session to hand back synchronously, and no network to refresh one.
      // AuthRepository.restoreSession() is this app's one seam onto that
      // condition.
      final identityStore = _FakeLastKnownIdentityStore()..value = _identity;
      final authRepository = _OfflineAuthRepository();
      final authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );

      await authController.restoreSession();
      expect(authController.state.status, AppAuthStatus.sessionExpired);
      expect(authController.state.status, isNot(AppAuthStatus.signedOut));

      await _runOfflineColdStartScenario(
        authController: authController,
        identityStore: identityStore,
      );
    },
  );

  test(
    'acceptance 2: offline cold start where the auth stream itself emits '
    'signedOut converges on sessionExpired, not signedOut, with zero '
    'deletions',
    () async {
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
    },
  );

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

        await container.read(songCatalogControllerProvider).handleOfflineAuthenticated();

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
  await container.read(songCatalogControllerProvider).handleOfflineAuthenticated();

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
    container.listen(activeCatalogContextProvider, (_, _) {}, fireImmediately: true),
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
/// interface (`deleteSong`, `deleteCatalogsForUser`, `deleteCatalog`). Used
/// to PROVE "zero deletions" via an actual call counter against the real
/// local-read path, rather than inferring it from the songs still being
/// readable afterwards. Mirrors the spirit of providers_test.dart's
/// `_BlockingDeletePlanningLocalStore` (the equivalent decorator already
/// proven correct for the planning store).
class _DeleteCountingSongCatalogStore implements SongCatalogStore {
  _DeleteCountingSongCatalogStore(this._delegate);

  final SongCatalogStore _delegate;
  int deleteSongCalls = 0;
  int deleteCatalogsForUserCalls = 0;
  int deleteCatalogCalls = 0;

  int get totalDeleteCalls =>
      deleteSongCalls + deleteCatalogsForUserCalls + deleteCatalogCalls;

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
  }) => _delegate.readActiveSummaries(
    userId: userId,
    organizationId: organizationId,
  );

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
  }) => _delegate.clearSongMutation(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

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
  }) => _delegate.resolveCancelledSongCreate(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    created: created,
    acceptedVersion: acceptedVersion,
  );

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
