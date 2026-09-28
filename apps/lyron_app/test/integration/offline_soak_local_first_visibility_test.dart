// Task 2.8 (docs/plans/2026-09-28-offline-catalog-local-first-visibility.md)
// -- the mandatory offline-soak acceptance test for the whole slice, per
// docs/specs/2026-09-28-offline-catalog-local-first-visibility.md's
// Acceptance section:
//
//   "for as long as a non-empty local snapshot exists for the current
//   (userId, organizationId), songLibraryListProvider never yields [],
//   across signedIn and sessionExpired, across fake lifecycle transitions,
//   manual/automatic sync triggers, and a network that never resolves --
//   except immediately after a genuine D1 purge."
//
// Uses the full real provider graph (songCatalogControllerProvider,
// songLibraryListProvider, appAuthControllerProvider,
// unifiedManualSyncControllerProvider, foregroundSyncListenerProvider), the
// same "full-ProviderContainer-with-fakes" pattern already proven in
// test/application/providers_test.dart and
// test/integration/offline_authenticated_cold_start_test.dart: only the true
// I/O boundaries (network, foreground-lifecycle stream) are faked; the local
// read/write path runs through real in-memory Drift stores.
//
// Two tests:
//   1. The core claim -- hung network + lifecycle churn + manual/automatic
//      sync + both auth states in one sequence -- catalog never empties.
//   2. The D1 counter-example -- a genuine two-confirmation
//      membership-revocation purge is the ONE legitimate point where the
//      catalog list goes empty, asserted explicitly, with every earlier
//      checkpoint proven non-empty first.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

const _userId = 'u1';
const _organizationId = 'org1';
const _email = 'demo@lyron.local';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('offline soak: catalog stays visible under hung network, lifecycle '
      'churn, and manual+automatic sync across signedIn and sessionExpired '
      '(LF-T2.8 core)', () {
    fakeAsync((async) {
      final songDatabase = SongCatalogDatabase.inMemory();
      final songStore = DriftSongCatalogStore(songDatabase);
      addTearDown(() async => songDatabase.close());

      // Seed a non-empty snapshot for (u1, org1) -- present before any
      // refresh ever runs, so local-first must be what surfaces it.
      songStore.replaceActiveSnapshot(
        userId: _userId,
        organizationId: _organizationId,
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 9, 1, 12),
      );
      async.flushMicrotasks();

      final planningDatabase = PlanningLocalDatabase.inMemory();
      final planningStore = DriftPlanningLocalStore(planningDatabase);
      addTearDown(() async => planningDatabase.close());

      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: _userId,
          email: _email,
          organizationId: _organizationId,
        );

      final authRepository = _ControllableAuthRepository(
        initialSession: const AppAuthSession(userId: _userId, email: _email),
      );
      final authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );
      authController.restoreSession();
      async.flushMicrotasks();
      expect(authController.state.status, AppAuthStatus.signedIn);

      final foregroundState = _TestAppForegroundState();
      final orgReader = _ToggleableOrgReader()..resolveFast(_organizationId);

      // A never-resolving repository stands in for "the network never
      // answers" for the listSongs/getSongSource leg too (ingredient 4 --
      // per the spec, existing suites' fakes answer too fast to have
      // caught F-B/F-E). Only reached once the org lookup itself has
      // resolved, but kept hung throughout the churn phase below as a
      // second independent guarantee that nothing on that leg is needed
      // to keep the cached catalog visible.
      final songRepository = _ToggleableSongRepository()
        ..resolveFast(
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sourceBysong: const {
            'song-1': SongSource(id: 'song-1', source: '{title: Cached Song}'),
          },
        );

      final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');

      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appAuthControllerProvider.overrideWith((_) => authController),
          songCatalogStoreProvider.overrideWithValue(songStore),
          planningLocalStoreProvider.overrideWithValue(planningStore),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          appForegroundStateProvider.overrideWithValue(foregroundState),
          activeOrganizationReaderProvider.overrideWithValue(orgReader.call),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
          supabaseSongRepositoryProvider.overrideWithValue(
            songRepository.asSupabaseSongRepository(),
          ),
          // Planning is not this test's concern. authSessionReader always
          // null keeps PlanningSyncController on its own already-proven
          // non-destructive null-session guard (spec Step 2.1's planning
          // counterpart), so it never touches the network either.
          planningSyncControllerProvider.overrideWith(
            (ref) => PlanningSyncController(
              localStore: () => planningStore,
              localDataLifecycle: ref.watch(localDataLifecycleProvider),
              remoteRepository: () =>
                  throw StateError('planning remote must not be called'),
              authSessionReader: () => null,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subscriptions = <ProviderSubscription<Object?>>[
        container.listen(
          activeCatalogContextProvider,
          (_, _) {},
          fireImmediately: true,
        ),
        container.listen(
          songLibraryListProvider,
          (_, _) {},
          fireImmediately: true,
        ),
        container.listen(
          unifiedManualSyncControllerProvider,
          (_, _) {},
          fireImmediately: true,
        ),
      ];
      for (final subscription in subscriptions) {
        addTearDown(subscription.close);
      }
      // Boots the lifecycle subscription (plain Provider, not
      // autoDispose -- stays alive for the container's lifetime once
      // read).
      container.read(foregroundSyncListenerProvider);

      // Riverpod recomputes songLibraryListProvider reactively once
      // catalogSnapshotStateProvider changes, but that recomputation
      // itself starts a new microtask chain (another local DB read) --
      // reading it mid-recompute can observe a stale cached value (e.g.
      // the very first build's synchronous `[]`, from before context was
      // established). Flushing again immediately before the read drains
      // that chain so the assertion always observes the settled value.
      void expectCatalogVisible(String reason) {
        // autoDispose providers recompute lazily: a dependency change
        // (e.g. songCatalogControllerProvider.notifyListeners()) marks
        // songLibraryListProvider dirty, but the new Future is only
        // actually started on the NEXT read/watch, not at notify time.
        // So: read once to kick off (or observe) the recompute, flush to
        // drain it, then read again for the settled value.
        container.read(songLibraryListProvider);
        async.flushMicrotasks();
        final songs = container.read(songLibraryListProvider).value;
        expect(songs, isNotNull, reason: '$reason (still loading)');
        expect(songs, isNotEmpty, reason: reason);
      }

      // --- Phase A: signedIn, fast network -- confirm baseline. ---
      // The provider graph already fired refreshCatalog() once,
      // fire-and-forget, the moment songCatalogControllerProvider was
      // first built. Flushing settles it.
      async.flushMicrotasks();
      expectCatalogVisible('phase A: signedIn with a working network');
      expect(
        container.read(activeCatalogContextProvider),
        const ActiveCatalogContext(
          userId: _userId,
          organizationId: _organizationId,
        ),
      );
      expect(
        container.read(catalogSnapshotStateProvider).connectionStatus,
        CatalogConnectionStatus.online,
      );

      // --- Phase B: flip the network to hang, stay signedIn. ---
      final hangCompleter = orgReader.hang();
      songRepository.hang();

      final syncController = container.read(
        unifiedManualSyncControllerProvider,
      );

      // Manual syncNow() presses interleaved with automatic
      // inactive->resumed lifecycle triggers, several times, while the
      // org lookup never resolves. None of these are awaited to
      // completion -- by construction they cannot complete while hung --
      // only pumped, exactly proving the catalog does not need the
      // network to stay visible.
      for (var i = 0; i < 3; i += 1) {
        unawaited(syncController.syncNow());
        async.flushMicrotasks();
        expectCatalogVisible('phase B manual press #$i under hung network');

        foregroundState.setForeground(false);
        async.flushMicrotasks();
        foregroundState.setForeground(true);
        async.flushMicrotasks();
        expectCatalogVisible(
          'phase B lifecycle churn #$i (inactive->resumed) under hung '
          'network',
        );
      }
      // A directly-driven refreshCatalog() (e.g. a periodic tick) hits
      // the same hang and must not disturb the already-established
      // context either.
      unawaited(container.read(songCatalogControllerProvider).refreshCatalog());
      async.flushMicrotasks();
      expectCatalogVisible(
        'phase B direct refreshCatalog() under hung network',
      );
      expect(
        container.read(activeCatalogContextProvider),
        const ActiveCatalogContext(
          userId: _userId,
          organizationId: _organizationId,
        ),
        reason: 'context must survive an in-flight hung network attempt',
      );

      // Drain every manual/automatic press left in flight from the hang
      // above (UnifiedManualSyncController.syncNow() single-flights: a
      // press made while one is already in flight is queued behind it,
      // not started fresh) before moving on -- otherwise the
      // sessionExpired-under-hang assertions below would actually be
      // observing THIS still-pending in-flight run, not a fresh
      // requiresReauth short-circuit.
      orgReader.resolveFast(_organizationId);
      songRepository.resolveFast(
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sourceBysong: const {
          'song-1': SongSource(id: 'song-1', source: '{title: Cached Song}'),
        },
      );
      hangCompleter.complete(_organizationId);
      async.flushMicrotasks();
      expectCatalogVisible('phase B after the hung network finally resolves');
      // Make the drain assumption load-bearing: isRunning only flips back
      // to false once UnifiedManualSyncController._runUntilQuiescent's
      // `do { ... } while (_queued)` loop has genuinely exited with no
      // press queued behind it -- i.e. every in-flight/queued press from
      // the hang above has actually finished, not just the first one.
      // Without this, phase C's requiresReauth assertions below could be
      // silently observing a still-in-flight run from phase B instead of
      // a fresh call, and this test would give no signal either way.
      expect(
        syncController.isRunning,
        isFalse,
        reason:
            'every manual/automatic sync press queued behind the hung '
            'network must have fully drained before phase C begins',
      );

      // --- Phase C: session expires. ---
      authRepository.emitSession(null);
      async.flushMicrotasks();
      expect(authController.state.status, AppAuthStatus.sessionExpired);
      expectCatalogVisible('phase C: right after sessionExpired');

      // Manual syncNow() under sessionExpired must short-circuit to
      // requiresReauth without attempting any network step -- proven here
      // by completing promptly against a network double that is hung
      // again (a second hang, independent of phase B's).
      final secondHang = orgReader.hang();
      songRepository.hang();
      final reauthResult = syncController.syncNow();
      var reauthSettled = false;
      reauthResult.then((_) => reauthSettled = true);
      async.flushMicrotasks();
      expect(
        reauthSettled,
        isTrue,
        reason:
            'manual sync under sessionExpired must not block on the '
            'network at all',
      );
      expect(syncController.lastResult.requiresReauth, isTrue);
      expectCatalogVisible(
        'phase C after a manual sync press (requiresReauth)',
      );

      // More lifecycle churn while sessionExpired: automatic triggers
      // must also short-circuit (requiresReauth) rather than prompting or
      // hiding data, and the catalog must stay visible throughout.
      for (var i = 0; i < 2; i += 1) {
        foregroundState.setForeground(false);
        async.flushMicrotasks();
        foregroundState.setForeground(true);
        async.flushMicrotasks();
        expectCatalogVisible(
          'phase C lifecycle churn #$i under sessionExpired',
        );
      }
      expect(
        container.read(activeCatalogContextProvider),
        const ActiveCatalogContext(
          userId: _userId,
          organizationId: _organizationId,
        ),
        reason: 'context must survive sessionExpired + lifecycle churn',
      );

      // --- Phase D: sign back in and let the network resolve. ---
      authRepository.emitSession(
        const AppAuthSession(userId: _userId, email: _email),
      );
      async.flushMicrotasks();
      expect(authController.state.status, AppAuthStatus.signedIn);
      expectCatalogVisible('phase D: back to signedIn, network still hung');

      orgReader.resolveFast(_organizationId);
      songRepository.resolveFast(
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sourceBysong: const {
          'song-1': SongSource(id: 'song-1', source: '{title: Cached Song}'),
        },
      );
      if (!secondHang.isCompleted) {
        secondHang.complete(_organizationId);
      }
      async.flushMicrotasks();

      final finalSyncResult = syncController.syncNow();
      var finalSettled = false;
      finalSyncResult.then((_) => finalSettled = true);
      async.flushMicrotasks();
      expect(finalSettled, isTrue);
      expectCatalogVisible('phase D: network resolved, still visible');
      expect(
        container.read(catalogSnapshotStateProvider).connectionStatus,
        CatalogConnectionStatus.online,
      );
    });
  });

  test('offline soak: a genuine two-confirmation membership-revocation purge '
      'is the only point where the catalog list goes empty (LF-T2.8 D1 '
      'counter-example)', () async {
    final songDatabase = SongCatalogDatabase.inMemory();
    final songStore = DriftSongCatalogStore(songDatabase);
    addTearDown(() async => songDatabase.close());

    await songStore.replaceActiveSnapshot(
      userId: _userId,
      organizationId: _organizationId,
      summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
      refreshedAt: DateTime.utc(2026, 9, 1, 12),
    );

    final planningDatabase = PlanningLocalDatabase.inMemory();
    final planningStore = DriftPlanningLocalStore(planningDatabase);
    addTearDown(() async => planningDatabase.close());

    final identityStore = DriftLastKnownIdentityStore.inMemory();
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userId,
        email: _email,
        organizationId: _organizationId,
      ),
    );

    final authRepository = _ControllableAuthRepository(
      initialSession: const AppAuthSession(userId: _userId, email: _email),
    );
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
    await authController.restoreSession();
    expect(authController.state.status, AppAuthStatus.signedIn);

    // Real LocalDataLifecycle, real Drift-backed stores -- only the
    // monotonic clock behind the D5.3 60s confirmation cooldown is
    // injected, so the test advances it explicitly instead of sleeping.
    var monotonicElapsed = Duration.zero;
    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: (_) {},
      eventsRecorder: _NoopLocalDataEventsRecorder(),
      monotonicNow: () => monotonicElapsed,
    );

    // Real VerifiedEmptyMembershipCleanupCoordinator wired to the real
    // lifecycle above. countPendingWork is pinned to 0 -- a genuinely
    // zero-pending-work resolution, which the real gate itself decides
    // skips the confirmation dialog (LocalDataLifecycle
    // .maybePurgeForMembershipRevocation: `initialCount == 0` never calls
    // requestConfirmation at all) -- so requestConfirmation throwing if
    // called is a real assertion that the dialog path was never needed
    // here, not a stub papering over it.
    final coordinator = VerifiedEmptyMembershipCleanupCoordinator(
      localDataLifecycle: lifecycle,
      countPendingWork: ({required userId}) async => 0,
      requestConfirmation: ({required pendingCount}) async => throw StateError(
        'zero pending work must skip the confirmation dialog entirely',
      ),
      invalidateLastKnownIdentityPersistence: () async {},
    );

    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final foregroundState = _TestAppForegroundState();

    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        appAuthControllerProvider.overrideWith((_) => authController),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        verifiedEmptyMembershipCleanupCoordinatorProvider.overrideWithValue(
          coordinator,
        ),
        appForegroundStateProvider.overrideWithValue(foregroundState),
        // A genuine, online, authenticated resolution that finds no
        // membership -- not a connectivity failure. Every refresh in this
        // test takes this path.
        activeOrganizationReaderProvider.overrideWithValue(() async => null),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.verified,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async => throw StateError(
              'listSongs must not be reached -- the org lookup resolves '
              'to null (no membership) before that call site',
            ),
            getSongRow: (id) async => throw StateError(
              'getSongRow must not be reached -- the org lookup resolves '
              'to null (no membership) before that call site',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final subscriptions = <ProviderSubscription<Object?>>[
      container.listen(
        activeCatalogContextProvider,
        (_, _) {},
        fireImmediately: true,
      ),
      container.listen(
        songLibraryListProvider,
        (_, _) {},
        fireImmediately: true,
      ),
    ];
    for (final subscription in subscriptions) {
      addTearDown(subscription.close);
    }

    final controller = container.read(songCatalogControllerProvider);

    // First resolution: local-first establishes context from the cached
    // snapshot, THEN the org lookup genuinely resolves to null. Per
    // D5.4/D5.5 a single verified-empty resolution only records the
    // marker -- it must not purge, and the invariant says context/reads
    // are untouched.
    await controller.refreshCatalog();
    var songs = await container.read(songLibraryListProvider.future);
    expect(
      songs,
      isNotEmpty,
      reason: 'a single verified-empty resolution must not purge',
    );
    expect(
      controller.state.context,
      const ActiveCatalogContext(
        userId: _userId,
        organizationId: _organizationId,
      ),
    );

    // Clear the cooldown D5.3 requires between the two confirmations.
    monotonicElapsed += const Duration(seconds: 61);

    // Second resolution: same user, same still-null org lookup, cooldown
    // elapsed -- this is the genuine second counted confirmation. With
    // zero pending work, LocalDataLifecycle authorizes and runs the
    // purge with no dialog. This is the ONLY point in this whole test
    // where an empty list is correct.
    await controller.refreshCatalog();
    songs = await container.read(songLibraryListProvider.future);
    expect(
      songs,
      isEmpty,
      reason:
          'a genuine second, cooldown-separated, zero-pending-work '
          'confirmation must purge, and songLibraryListProvider must '
          'reflect that as the one legitimate empty result',
    );
    expect(
      controller.state.context,
      isNull,
      reason:
          'a genuine D1 purge is one of the four invariant causes '
          'allowed to clear context',
    );
    expect(
      await songStore.readActiveSummaries(
        userId: _userId,
        organizationId: _organizationId,
      ),
      isEmpty,
      reason:
          'the purge must have actually deleted the local snapshot, '
          'not merely reset in-memory state',
    );
  });
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

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}

  @override
  Future<void> recordMembershipRevocationMarked({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationCleared({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationPurgeDeclined({
    required String userId,
    required MembershipRevocationPurgeDeclineReason reason,
  }) async {}
}

/// Mirrors providers_test.dart's `_ControllableAuthRepository`: a
/// restoreSession() that returns whatever [initialSession] holds, and an
/// independently drivable stream (emitSession) that models a
/// gotrue-originated auth-state change -- including a null emission
/// modelling session expiry.
class _ControllableAuthRepository implements AuthRepository {
  _ControllableAuthRepository({this.initialSession});

  AppAuthSession? initialSession;
  final StreamController<AppAuthSession?> _controller =
      StreamController<AppAuthSession?>.broadcast();

  @override
  Future<AppAuthSession?> restoreSession() async => initialSession;

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
  Future<void> signOut() async {
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {}

  void emitSession(AppAuthSession? session) => _controller.add(session);
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

/// A [activeOrganizationReaderProvider]-shaped double whose behavior can be
/// swapped mid-test: a fast-resolving org id, or a hang -- one shared
/// [Completer] that every call issued while hung awaits, so completing it
/// later resolves every one of those in-flight calls at once (the "network
/// double that never resolves for at least one phase" ingredient, per the
/// spec's own callout that fast-answering fakes elsewhere in this repo's
/// suites did not catch F-B/F-E).
class _ToggleableOrgReader {
  Future<String?> Function() _impl = () async => null;

  Future<String?> call() => _impl();

  void resolveFast(String? organizationId) {
    _impl = () async => organizationId;
  }

  Completer<String?> hang() {
    final completer = Completer<String?>();
    _impl = () => completer.future;
    return completer;
  }
}

/// Same shape as [_ToggleableOrgReader] but for the listSongs/getSongSource
/// leg of a refresh, wrapped as a real [SupabaseSongRepository.testing]
/// instance so the controller's remote-repository seam is exercised
/// unmodified.
class _ToggleableSongRepository {
  Future<List<Map<String, dynamic>>> Function() _listSongsRows = () async =>
      const [];
  Future<Map<String, dynamic>?> Function(String id) _getSongRow = (id) async =>
      null;

  void resolveFast({
    required List<SongSummary> summaries,
    required Map<String, SongSource> sourceBysong,
  }) {
    _listSongsRows = () async => [
      for (final summary in summaries)
        {
          'id': summary.id,
          'slug': summary.id,
          'title': summary.title,
          'version': 1,
        },
    ];
    _getSongRow = (id) async {
      final source = sourceBysong[id];
      if (source == null) return null;
      return {'id': id, 'slug': id, 'chordpro_source': source.source};
    };
  }

  void hang() {
    final listSongsCompleter = Completer<List<Map<String, dynamic>>>();
    final getSongCompleter = Completer<Map<String, dynamic>?>();
    _listSongsRows = () => listSongsCompleter.future;
    _getSongRow = (id) => getSongCompleter.future;
  }

  SupabaseSongRepository asSupabaseSongRepository() =>
      SupabaseSongRepository.testing(
        listSongsRows: () => _listSongsRows(),
        getSongRow: (id) => _getSongRow(id),
      );
}
