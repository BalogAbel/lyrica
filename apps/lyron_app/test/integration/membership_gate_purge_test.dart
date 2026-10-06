// SG2 (docs/specs/2026-10-05-offline-first-startup-gate.md): with a known
// organization, a fresh verifiedEmpty keeps the home route until the ADR-035
// D5 purge has genuinely run; then the gate shows InviteRequiredScreen. The
// second D5 confirmation comes from a catalog refresh here, not from the
// gate's own resolution, which is exactly the case the purge handler covers.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

const _userId = 'user-1';
const _organizationId = 'org-1';
const _email = 'demo@lyron.local';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('a live verifiedEmpty keeps the home route until the D5 purge runs, '
      'then the gate shows InviteRequired (SG2)', () async {
    final songDatabase = SongCatalogDatabase.inMemory();
    final songStore = DriftSongCatalogStore(songDatabase);
    addTearDown(songDatabase.close);
    await songStore.replaceActiveSnapshot(
      userId: _userId,
      organizationId: _organizationId,
      summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
      refreshedAt: DateTime.utc(2026, 10, 1, 12),
    );

    final planningDatabase = PlanningLocalDatabase.inMemory();
    final planningStore = DriftPlanningLocalStore(planningDatabase);
    addTearDown(planningDatabase.close);

    final identityStore = DriftLastKnownIdentityStore.inMemory();
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userId,
        email: _email,
        organizationId: _organizationId,
      ),
    );

    final authRepository = _SignedInAuthRepository();
    addTearDown(authRepository.dispose);
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
    await authController.restoreSession();

    var monotonicElapsed = Duration.zero;
    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: authController.noteLastKnownIdentity,
      eventsRecorder: _NoopLocalDataEventsRecorder(),
      monotonicNow: () => monotonicElapsed,
    );
    final coordinator = VerifiedEmptyMembershipCleanupCoordinator(
      localDataLifecycle: lifecycle,
      countPendingWork: ({required userId}) async => 0,
      requestConfirmation: ({required pendingCount}) async => throw StateError(
        'zero pending work must skip the confirmation dialog',
      ),
      invalidateLastKnownIdentityPersistence: () async {},
    );

    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('http://127.0.0.1:54321', 'anon-key'),
        ),
        appAuthControllerProvider.overrideWith((_) => authController),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        verifiedEmptyMembershipCleanupCoordinatorProvider.overrideWithValue(
          coordinator,
        ),
        appForegroundStateProvider.overrideWithValue(_ForegroundState()),
        activeOrganizationResolutionProvider.overrideWithValue(
          () async => const ActiveOrganizationResolution.verifiedEmpty(),
        ),
        activeOrganizationReaderProvider.overrideWithValue(() async => null),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.verified,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async => throw StateError('not reached'),
            getSongRow: (id) async => throw StateError('not reached'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(
      songCatalogControllerProvider,
      (_, _) {},
    );
    addTearDown(keepAlive.close);

    // The sign-in edge resolution: a fresh verifiedEmpty for a user whose
    // identity still names org-1.
    container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final gate = container.read(activeMembershipControllerProvider);
    expect(gate.last, isA<ActiveOrganizationVerifiedEmpty>());
    expect(gate.viewFor(hasPendingInvite: false), MembershipGateView.home);

    // First counted confirmation (catalog refresh): marker only.
    final catalog = container.read(songCatalogControllerProvider);
    await catalog.refreshCatalog();
    expect(gate.viewFor(hasPendingInvite: false), MembershipGateView.home);

    // Second confirmation after the D5.3 cooldown: the purge runs.
    monotonicElapsed += const Duration(seconds: 61);
    await catalog.refreshCatalog();
    await pumpEventQueue();

    expect(await identityStore.read(), isNull);
    expect(
      gate.viewFor(hasPendingInvite: false),
      MembershipGateView.inviteRequired,
    );
  });

  test('the purge handler records verifiedEmpty even when the gate still '
      'held an older selected result (SG2)', () async {
    // Same as above, but the gate's own resolution answered `selected`
    // before the revocation; only the purge handler can move it.
    final songDatabase = SongCatalogDatabase.inMemory();
    final songStore = DriftSongCatalogStore(songDatabase);
    addTearDown(songDatabase.close);
    await songStore.replaceActiveSnapshot(
      userId: _userId,
      organizationId: _organizationId,
      summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Cached Song}')],
      refreshedAt: DateTime.utc(2026, 10, 1, 12),
    );
    final planningDatabase = PlanningLocalDatabase.inMemory();
    final planningStore = DriftPlanningLocalStore(planningDatabase);
    addTearDown(planningDatabase.close);
    final identityStore = DriftLastKnownIdentityStore.inMemory();
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userId,
        email: _email,
        organizationId: _organizationId,
      ),
    );
    final authRepository = _SignedInAuthRepository();
    addTearDown(authRepository.dispose);
    final authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
    await authController.restoreSession();
    var monotonicElapsed = Duration.zero;
    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: authController.noteLastKnownIdentity,
      eventsRecorder: _NoopLocalDataEventsRecorder(),
      monotonicNow: () => monotonicElapsed,
    );
    final coordinator = VerifiedEmptyMembershipCleanupCoordinator(
      localDataLifecycle: lifecycle,
      countPendingWork: ({required userId}) async => 0,
      requestConfirmation: ({required pendingCount}) async => throw StateError(
        'zero pending work must skip the confirmation dialog',
      ),
      invalidateLastKnownIdentityPersistence: () async {},
    );
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('http://127.0.0.1:54321', 'anon-key'),
        ),
        appAuthControllerProvider.overrideWith((_) => authController),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        verifiedEmptyMembershipCleanupCoordinatorProvider.overrideWithValue(
          coordinator,
        ),
        appForegroundStateProvider.overrideWithValue(_ForegroundState()),
        activeOrganizationResolutionProvider.overrideWithValue(
          () async =>
              const ActiveOrganizationResolution.selected(_organizationId),
        ),
        activeOrganizationReaderProvider.overrideWithValue(() async => null),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.verified,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async => throw StateError('not reached'),
            getSongRow: (id) async => throw StateError('not reached'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(
      songCatalogControllerProvider,
      (_, _) {},
    );
    addTearDown(keepAlive.close);

    container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final gate = container.read(activeMembershipControllerProvider);
    expect(gate.last, isA<ActiveOrganizationSelected>());

    final catalog = container.read(songCatalogControllerProvider);
    await catalog.refreshCatalog();
    monotonicElapsed += const Duration(seconds: 61);
    await catalog.refreshCatalog();
    await pumpEventQueue();

    expect(gate.last, isA<ActiveOrganizationVerifiedEmpty>());
    expect(
      gate.viewFor(hasPendingInvite: false),
      MembershipGateView.inviteRequired,
    );
  });
}

class _SignedInAuthRepository implements AuthRepository {
  final _sessions = StreamController<AppAuthSession?>.broadcast();

  void dispose() => _sessions.close();

  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: _userId, email: _email);

  @override
  Stream<AppAuthSession?> watchSession() => _sessions.stream;

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

class _ForegroundState implements AppForegroundState {
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => _changes.stream;
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
