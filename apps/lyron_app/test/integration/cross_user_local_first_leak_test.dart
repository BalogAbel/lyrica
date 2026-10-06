// Cross-user local-first ownership
// (docs/specs/2026-10-06-cross-user-local-first-ownership.md): a user must
// never see, or lose, another user's songs or plans through a local-first
// path. Real AppAuthController, real LocalDataLifecycle, Drift in-memory
// stores and the real different-user reauth providers
// (lastKnownIdentityPersistenceProvider, reauthPromptControllerProvider,
// pendingLocalWorkCounterProvider, membershipRefreshEffectProvider). Only the
// network edges are replaced: the auth session stream, the membership RPC,
// the organization lookup and the remote fetches. The two read gates only
// pause the real Drift reads for user A, to pin an interleaving.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
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
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

const _userA = 'user-a';
const _emailA = 'a@lyron.local';
const _orgA = 'org-a';
const _userB = 'user-b';
const _emailB = 'b@lyron.local';
const _orgB = 'org-b';

const _sessionA = AppAuthSession(userId: _userA, email: _emailA);
const _sessionB = AppAuthSession(userId: _userB, email: _emailB);

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('establishment from another user\'s identity (F6)', () {
    test('B loses the session while the different-user reauth is pending; '
        'the catalog must not establish A\'s context for B', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      // Precondition: A is current (sessionExpired(A)), A's own data shows.
      expect(fixture.catalogContextUserId, _userA);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.status, AppAuthStatus.signedIn);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNotNull,
        reason: 'A has pending work, so the different-user prompt is pending',
      );
      expect((await fixture.identityStore.read())?.userId, _userA);
      expect(fixture.gateViewForCurrentUser, MembershipGateView.home);

      // A non-retryable refresh failure: the session goes to null while the
      // app did not initiate a sign-out.
      await fixture.loseSession();
      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.gateViewForCurrentUser, MembershipGateView.home);

      expect(
        fixture.catalogContextUserId,
        isNot(_userA),
        reason: 'the current user is B; A\'s catalog must not be established',
      );
      expect(await fixture.readSongTitles(), isNot(contains('A secret song')));
    }, skip: 'red until Task 2 (XU1); spec 2026-10-06 cross-user ownership');

    test('the same sequence must not establish A\'s planning context for '
        'B', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);

      await fixture.signInAs(_sessionB);
      await fixture.loseSession();
      expect(fixture.auth.state.currentUserId, _userB);

      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    }, skip: 'red until Task 2 (XU1); spec 2026-10-06 cross-user ownership');
  });

  group('contexts held for the previous user (F7)', () {
    test('planning established for A from a sessionExpired cold start does '
        'not survive B\'s sign-in when B\'s planning lookup fails', () async {
      // A has plans cached but no songs, so the catalog never establishes
      // A's context and the catalog's I3 reset never reaches planning.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);
      expect(fixture.catalogContextUserId, isNull);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.gateViewForCurrentUser, MembershipGateView.home);

      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    }, skip: 'red until Task 3 (XU2); spec 2026-10-06 cross-user ownership');

    test('with songs and plans cached, nothing of A\'s survives B\'s '
        'sign-in', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);
      expect(fixture.catalogContextUserId, _userA);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);

      expect(fixture.catalogContextUserId, isNot(_userA));
      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    });

    test('B\'s planning organization answering while A\'s reauth prompt is '
        'pending must not delete A\'s plans or pending work (F8)', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
        lookupAnswersFor: const {_userB},
      );
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, _userA);
      expect(await fixture.pendingPlanningMutationCount(_userA), 1);

      await fixture.signInAs(_sessionB);
      expect(
        fixture.container.read(reauthPromptControllerProvider).pending,
        isNotNull,
      );
      expect(fixture.planningUserId, _userB);

      expect(
        await fixture.pendingPlanningMutationCount(_userA),
        1,
        reason: 'only a confirmed different-user wipe may delete A\'s work',
      );
      expect(
        await fixture.planningStore.hasProjection(
          userId: _userA,
          organizationId: _orgA,
        ),
        isTrue,
      );
    }, skip: 'red until Task 3 (XU2); spec 2026-10-06 cross-user ownership');

    test('a planning establishment started for A does not land after B '
        'signs in', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
      );
      fixture.planningReadGate.hold();
      await fixture.coldStartAsA();
      expect(fixture.planningUserId, isNull, reason: 'held on the gate');

      await fixture.signInAs(_sessionB);
      fixture.planningReadGate.release();
      await _settle();

      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.planningUserId, isNot(_userA));
      expect(await fixture.readPlanNames(), isNot(contains('A secret plan')));
    }, skip: 'red until Task 3 (XU2); spec 2026-10-06 cross-user ownership');

    test('the active planning context held for A does not survive B\'s '
        'sign-in', () async {
      // A re-authenticates while offline: the planning lookup falls back to
      // A's cached organization, so the active planning context is A's while
      // the catalog (no songs cached) has none.
      final fixture = await _Fixture.create(
        seedSongsForA: false,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionA);
      expect(fixture.activePlanningUserId, _userA);
      await fixture.loseSession();
      expect(fixture.auth.state.currentUserId, _userA);

      await fixture.signInAs(_sessionB);
      expect(fixture.auth.state.currentUserId, _userB);

      expect(fixture.activePlanningUserId, isNot(_userA));
      final entries = await fixture.container.read(
        planningMutationEntriesProvider.future,
      );
      expect(
        entries.map((entry) => entry.aggregateId),
        isNot(contains('plan-a-edit')),
      );
    }, skip: 'red until Task 4 (XU2); spec 2026-10-06 cross-user ownership');

    test('a catalog establishment started for A does not land after B signs '
        'in', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: false,
      );
      fixture.catalogReadGate.hold();
      await fixture.coldStartAsA();
      expect(fixture.catalogContextUserId, isNull, reason: 'held on the gate');

      await fixture.signInAs(_sessionB);
      fixture.catalogReadGate.release();
      await _settle();

      expect(fixture.auth.state.currentUserId, _userB);
      expect(fixture.catalogContextUserId, isNot(_userA));
      expect(await fixture.readSongTitles(), isNot(contains('A secret song')));
    }, skip: 'red until Task 5 (XU2); spec 2026-10-06 cross-user ownership');
  });

  group('the prior user\'s own access is unchanged', () {
    test('cancelling B\'s reauth returns A\'s songs and plans', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();
      await fixture.signInAs(_sessionB);
      expect(fixture.catalogContextUserId, isNot(_userA));

      fixture.container.read(reauthPromptControllerProvider).answer(false);
      await _settle();

      expect(fixture.auth.state.status, AppAuthStatus.sessionExpired);
      expect(fixture.auth.state.currentUserId, _userA);
      expect(fixture.catalogContextUserId, _userA);
      expect(fixture.planningUserId, _userA);
      expect(await fixture.readSongTitles(), contains('A secret song'));
      expect(await fixture.readPlanNames(), contains('A secret plan'));
    });

    test('A re-authenticating keeps A\'s songs and plans', () async {
      final fixture = await _Fixture.create(
        seedSongsForA: true,
        seedPlanningForA: true,
      );
      await fixture.coldStartAsA();

      await fixture.signInAs(_sessionA);

      expect(fixture.auth.state.status, AppAuthStatus.signedIn);
      expect(fixture.catalogContextUserId, _userA);
      expect(fixture.planningUserId, _userA);
      expect(await fixture.readSongTitles(), contains('A secret song'));
      expect(await fixture.readPlanNames(), contains('A secret plan'));
    });
  });
}

class _Fixture {
  _Fixture._({
    required this.container,
    required this.auth,
    required this.authRepository,
    required this.identityStore,
    required this.planningDatabase,
    required this.planningStore,
    required this.catalogReadGate,
    required this.planningReadGate,
  });

  final ProviderContainer container;
  final AppAuthController auth;
  final _ControllableAuthRepository authRepository;
  final DriftLastKnownIdentityStore identityStore;
  final PlanningLocalDatabase planningDatabase;
  final PlanningLocalStore planningStore;
  final _ReadGate catalogReadGate;
  final _ReadGate planningReadGate;

  /// [lookupAnswersFor] lists the users whose organization lookup (catalog
  /// and planning) answers; for everyone else it hits a dropped connection.
  static Future<_Fixture> create({
    required bool seedSongsForA,
    required bool seedPlanningForA,
    Set<String> lookupAnswersFor = const {},
  }) async {
    final catalogReadGate = _ReadGate();
    final planningReadGate = _ReadGate();
    final songDatabase = SongCatalogDatabase.inMemory();
    addTearDown(songDatabase.close);
    final songStore = _GatedSongCatalogStore(songDatabase, catalogReadGate);
    final planningDatabase = PlanningLocalDatabase.inMemory();
    addTearDown(planningDatabase.close);
    final planningStore = _GatedPlanningLocalStore(
      planningDatabase,
      planningReadGate,
    );
    final identityStore = DriftLastKnownIdentityStore.inMemory();

    if (seedSongsForA) {
      await songStore.replaceActiveSnapshot(
        userId: _userA,
        organizationId: _orgA,
        summaries: const [SongSummary(id: 'song-a', title: 'A secret song')],
        sources: const [
          SongSource(id: 'song-a', source: '{title: A secret song}'),
        ],
        refreshedAt: DateTime.utc(2026, 10, 1, 12),
      );
    }
    if (seedPlanningForA) {
      await planningStore.replaceActiveProjection(
        userId: _userA,
        organizationId: _orgA,
        plans: [
          CachedPlanRecord(
            id: 'plan-a',
            name: 'A secret plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 10, 1, 12),
          ),
        ],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 10, 1, 12),
      );
    }
    // A's unsynced work: a different-user sign-in must ask before wiping it,
    // so the reauth prompt stays pending (ADR-029 D3).
    await planningDatabase
        .into(planningDatabase.cachedPlanningMutations)
        .insert(
          CachedPlanningMutationsCompanion.insert(
            userId: _userA,
            organizationId: _orgA,
            aggregateType: 'plan',
            aggregateId: 'plan-a-edit',
            mutationKind: PlanningMutationKind.planEdit.value,
            syncStatus: PlanningMutationSyncStatus.pending.value,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 10, 1, 12),
          ),
        );
    await identityStore.write(
      const LastKnownIdentity(
        userId: _userA,
        email: _emailA,
        organizationId: _orgA,
      ),
    );

    final authRepository = _ControllableAuthRepository();
    addTearDown(authRepository.dispose);
    // Disposed by the container (appAuthControllerProvider owns it).
    final auth = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );

    final lifecycle = LocalDataLifecycle(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
      identityStore: identityStore,
      noteLastKnownIdentity: auth.noteLastKnownIdentity,
      eventsRecorder: _NoopLocalDataEventsRecorder(),
    );

    final container = ProviderContainer(
      overrides: [
        // Unroutable: any request that slips through fails as connectivity.
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('http://127.0.0.1:9', 'anon-key'),
        ),
        appAuthControllerProvider.overrideWith((_) => auth),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogStoreProvider.overrideWithValue(songStore),
        planningLocalStoreProvider.overrideWithValue(planningStore),
        lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        localDataLifecycleProvider.overrideWithValue(lifecycle),
        appForegroundStateProvider.overrideWithValue(_ForegroundState()),
        // Every user's membership RPC answers, so the gate opens ...
        activeOrganizationResolutionProvider.overrideWithValue(() async {
          return auth.state.currentUserId == _userB
              ? const ActiveOrganizationResolution.selected(_orgB)
              : const ActiveOrganizationResolution.selected(_orgA);
        }),
        // ... but the catalog and planning organization lookups only answer
        // for the users in lookupAnswersFor.
        activeOrganizationReaderProvider.overrideWithValue(() async {
          final userId = auth.state.currentUserId;
          if (userId != null && lookupAnswersFor.contains(userId)) {
            return userId == _userB ? _orgB : _orgA;
          }
          throw const SocketException('network is unreachable');
        }),
        catalogSessionVerifierProvider.overrideWithValue(
          () async => CatalogSessionStatus.unverifiableDueToConnectivity,
        ),
        supabaseSongRepositoryProvider.overrideWithValue(
          SupabaseSongRepository.testing(
            listSongsRows: () async =>
                throw const SocketException('network is unreachable'),
            getSongRow: (id) async =>
                throw const SocketException('network is unreachable'),
          ),
        ),
        planningRemoteRefreshRepositoryProvider.overrideWithValue(
          _OfflinePlanningRemoteRefreshRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Production mounts these through the router and the app shell.
    container.read(appAuthListenableProvider);
    container.read(membershipRefreshEffectProvider);
    final subscriptions = [
      container.listen(songCatalogControllerProvider, (_, _) {}),
      container.listen(planningSyncControllerProvider, (_, _) {}),
      container.listen(activeMembershipControllerProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    });

    return _Fixture._(
      container: container,
      auth: auth,
      authRepository: authRepository,
      identityStore: identityStore,
      planningDatabase: planningDatabase,
      planningStore: planningStore,
      catalogReadGate: catalogReadGate,
      planningReadGate: planningReadGate,
    );
  }

  String? get catalogContextUserId =>
      container.read(activeCatalogContextProvider)?.userId;

  String? get planningUserId =>
      container.read(planningSyncStateProvider).userId;

  String? get activePlanningUserId =>
      container.read(activePlanningContextProvider)?.userId;

  MembershipGateView get gateViewForCurrentUser => container
      .read(activeMembershipControllerProvider)
      .viewFor(hasPendingInvite: false);

  Future<List<String>> readSongTitles() async {
    final songs = await container.read(songLibraryListProvider.future);
    return songs.map((song) => song.title).toList();
  }

  Future<List<String>> readPlanNames() async {
    try {
      final plans = await container.read(planningPlanListProvider.future);
      return plans.map((plan) => plan.name).toList();
    } on StateError {
      // "Planning local data is unavailable": nothing is shown.
      return const [];
    }
  }

  Future<int> pendingPlanningMutationCount(String userId) async {
    final rows = await (planningDatabase.select(
      planningDatabase.cachedPlanningMutations,
    )..where((table) => table.userId.equals(userId))).get();
    return rows.length;
  }

  Future<void> coldStartAsA() async {
    await auth.restoreSession();
    await _settle();
    expect(auth.state.status, AppAuthStatus.sessionExpired);
    expect(auth.state.currentUserId, _userA);
  }

  Future<void> signInAs(AppAuthSession session) async {
    authRepository.emit(session);
    await _settle();
  }

  Future<void> loseSession() async {
    authRepository.emit(null);
    await _settle();
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await pumpEventQueue(times: 50);
  }
}

/// Pauses the real Drift reads for user A while held.
class _ReadGate {
  Completer<void>? _held;

  void hold() => _held = Completer<void>();

  void release() {
    _held?.complete();
    _held = null;
  }

  Future<void> passFor(String userId) async {
    final held = _held;
    if (held != null && userId == _userA) {
      await held.future;
    }
  }
}

class _GatedSongCatalogStore extends DriftSongCatalogStore {
  _GatedSongCatalogStore(super.database, this._gate);

  final _ReadGate _gate;

  @override
  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  }) async {
    await _gate.passFor(userId);
    return super.readActiveSummaries(
      userId: userId,
      organizationId: organizationId,
    );
  }
}

class _GatedPlanningLocalStore extends DriftPlanningLocalStore {
  _GatedPlanningLocalStore(super.database, this._gate);

  final _ReadGate _gate;

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async {
    await _gate.passFor(userId);
    return super.hasProjection(userId: userId, organizationId: organizationId);
  }
}

class _ControllableAuthRepository implements AuthRepository {
  final _sessions = StreamController<AppAuthSession?>.broadcast();

  void emit(AppAuthSession? session) => _sessions.add(session);

  void dispose() => _sessions.close();

  // Cold start offline: the persisted session cannot be restored.
  @override
  Future<AppAuthSession?> restoreSession() async => null;

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

class _OfflinePlanningRemoteRefreshRepository
    implements PlanningRemoteRefreshRepository {
  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    throw const SocketException('network is unreachable');
  }
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
