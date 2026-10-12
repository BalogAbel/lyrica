import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/drift_test_setup.dart';

const _session = AppAuthSession(userId: 'user-1', email: 'demo@lyron.local');

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._session);

  final AppAuthSession? _session;
  final _sessions = StreamController<AppAuthSession?>.broadcast();

  void dispose() => _sessions.close();

  void emit(AppAuthSession? session) => _sessions.add(session);

  @override
  Future<AppAuthSession?> restoreSession() async => _session;

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

/// Every request hangs: the network stays silent.
class _HangingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

class _Harness {
  _Harness(
    this.container,
    this.authController,
    this.repository,
    this.identityStore,
  );

  final DriftLastKnownIdentityStore identityStore;
  final ProviderContainer container;
  final AppAuthController authController;
  final _FakeAuthRepository repository;
}

Future<_Harness> _harness({
  required AppAuthSession? session,
  required ActiveOrganizationResolutionReader resolution,
  LastKnownIdentity? identity,
  ({String userId, String organizationId})? cachedSnapshot,
  List<Override> extraOverrides = const [],
}) async {
  final identityStore = DriftLastKnownIdentityStore.inMemory();
  if (identity != null) {
    await identityStore.write(identity);
  }
  final repository = _FakeAuthRepository(session);
  addTearDown(repository.dispose);
  final authController = AppAuthController(
    repository,
    lastKnownIdentityStore: identityStore,
  );
  await authController.restoreSession();

  final songDatabase = SongCatalogDatabase.inMemory();
  final planningDatabase = PlanningLocalDatabase.inMemory();
  addTearDown(songDatabase.close);
  addTearDown(planningDatabase.close);
  if (cachedSnapshot != null) {
    await DriftSongCatalogStore(songDatabase).replaceActiveSnapshot(
      userId: cachedSnapshot.userId,
      organizationId: cachedSnapshot.organizationId,
      summaries: const [],
      sources: const [],
      refreshedAt: DateTime.utc(2026, 10, 1),
    );
  }

  final container = ProviderContainer(
    overrides: [
      appAuthControllerProvider.overrideWith((_) => authController),
      lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
      songCatalogDatabaseProvider.overrideWithValue(songDatabase),
      planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
      activeOrganizationResolutionProvider.overrideWithValue(resolution),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  return _Harness(container, authController, repository, identityStore);
}

class _SucceedingInvitations implements InvitationRepository {
  @override
  Future<RedeemResult> redeem(String token) async =>
      const RedeemSuccess('org-1');
}

Future<ActiveOrganizationResolution> _never() =>
    Completer<ActiveOrganizationResolution>().future;

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test(
    'a known organization opens the gate with no network answer (SG1)',
    () async {
      final harness = await _harness(
        session: _session,
        identity: const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
        resolution: _never,
      );
      harness.container.read(membershipRefreshEffectProvider);
      await pumpEventQueue();

      final controller = harness.container.read(
        activeMembershipControllerProvider,
      );
      expect(
        controller.viewFor(hasPendingInvite: false),
        MembershipGateView.home,
      );
      expect(controller.allowsAuthenticatedRoutes, isTrue);
    },
  );

  test('another user\'s identity is not a known organization (SG1)', () async {
    final harness = await _harness(
      session: _session,
      identity: const LastKnownIdentity(
        userId: 'user-2',
        email: 'other@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();

    expect(
      harness.container
          .read(activeMembershipControllerProvider)
          .viewFor(hasPendingInvite: false),
      MembershipGateView.resolving,
    );
  });

  test('without a known organization the gate loads, then opens on the '
      'answer (SG4, G-C)', () async {
    final answer = Completer<ActiveOrganizationResolution>();
    final harness = await _harness(
      session: _session,
      resolution: () => answer.future,
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();

    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.resolving,
    );

    answer.complete(const ActiveOrganizationResolution.selected('org-1'));
    await pumpEventQueue();

    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
  });

  test(
    'sessionExpired with a known organization opens the gate (G-B)',
    () async {
      final harness = await _harness(
        session: null,
        identity: const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
        resolution: _never,
      );
      expect(harness.authController.state.status, AppAuthStatus.sessionExpired);

      expect(
        harness.container
            .read(activeMembershipControllerProvider)
            .viewFor(hasPendingInvite: false),
        MembershipGateView.home,
      );
    },
  );

  test('an identity change notifies the gate', () async {
    final harness = await _harness(
      session: _session,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
    );
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    await harness.container
        .read(localDataLifecycleProvider)
        .clearIdentity(reason: PurgeReason.userSignOut);

    expect(notifications, greaterThan(0));
    expect(
      controller.viewFor(hasPendingInvite: false),
      isNot(MembershipGateView.home),
    );
  });

  test('an explicit sign-out forgets the live resolution (SG3)', () async {
    final harness = await _harness(
      session: _session,
      resolution: () async =>
          const ActiveOrganizationResolution.selected('org-1'),
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    expect(controller.last, isA<ActiveOrganizationSelected>());

    await harness.authController.signOut();
    await pumpEventQueue();

    expect(controller.last, isNull);
  });

  test(
    'the initial signedIn edge starts exactly one resolution (F1)',
    () async {
      var calls = 0;
      final harness = await _harness(
        session: _session,
        resolution: () async {
          calls++;
          return const ActiveOrganizationResolution.selected('org-1');
        },
      );
      harness.container.read(membershipRefreshEffectProvider);
      await pumpEventQueue();

      expect(calls, 1);
    },
  );

  test('a direct session switch A to B resolves B, once (F1)', () async {
    final answers = <Completer<ActiveOrganizationResolution>>[];
    final harness = await _harness(
      session: _session,
      resolution: () {
        final answer = Completer<ActiveOrganizationResolution>();
        answers.add(answer);
        return answer.future;
      },
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    answers.single.complete(const ActiveOrganizationResolution.selected('a'));
    await pumpEventQueue();
    expect(controller.last, const ActiveOrganizationResolution.selected('a'));

    harness.repository.emit(
      const AppAuthSession(userId: 'user-2', email: 'other@lyron.local'),
    );
    await pumpEventQueue();

    expect(harness.authController.state.currentUserId, 'user-2');
    expect(answers, hasLength(2), reason: 'one resolution for B, not zero');
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.resolving,
    );

    answers.last.complete(const ActiveOrganizationResolution.selected('b'));
    await pumpEventQueue();

    expect(answers, hasLength(2));
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
    expect(controller.last, const ActiveOrganizationResolution.selected('b'));
  });

  test('sessionExpired without a known organization: Retry reads the local '
      'cache and never calls the network (F2)', () async {
    var calls = 0;
    final harness = await _harness(
      session: null,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: null,
      ),
      cachedSnapshot: (userId: 'user-1', organizationId: 'org-x'),
      resolution: () async {
        calls++;
        return const ActiveOrganizationResolution.unknownNonConnectivityFailure();
      },
    );
    expect(harness.authController.state.status, AppAuthStatus.sessionExpired);
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.connectivityFailure,
    );

    await harness.container.read(membershipRetryProvider)();

    expect(calls, 0, reason: 'sessionExpired has no live session to ask with');
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
    expect(
      controller.last,
      const ActiveOrganizationResolution.selected('org-x'),
    );
  });

  test('sessionExpired without a cached organization: Retry stays on the '
      'connectivity failure and never calls the network (F2)', () async {
    var calls = 0;
    final harness = await _harness(
      session: null,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: null,
      ),
      resolution: () async {
        calls++;
        return const ActiveOrganizationResolution.selected('org-1');
      },
    );

    await harness.container.read(membershipRetryProvider)();

    expect(calls, 0);
    expect(
      harness.container
          .read(activeMembershipControllerProvider)
          .viewFor(hasPendingInvite: false),
      MembershipGateView.connectivityFailure,
    );
  });

  test('signedIn: Retry still asks the network (F2)', () async {
    var calls = 0;
    final harness = await _harness(
      session: _session,
      resolution: () async {
        calls++;
        return const ActiveOrganizationResolution.selected('org-1');
      },
    );

    await harness.container.read(membershipRetryProvider)();

    expect(calls, 1);
    expect(
      harness.container
          .read(activeMembershipControllerProvider)
          .viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
  });
  test('a late pre-redeem verifiedEmpty never overrides the resolution the '
      'redemption started (C3)', () async {
    final answers = <Completer<ActiveOrganizationResolution>>[];
    final harness = await _harness(
      session: _session,
      resolution: () {
        final answer = Completer<ActiveOrganizationResolution>();
        answers.add(answer);
        return answer.future;
      },
      extraOverrides: [
        invitationRepositoryProvider.overrideWithValue(
          _SucceedingInvitations(),
        ),
      ],
    );
    harness.container.read(membershipRefreshEffectProvider);
    await pumpEventQueue();
    final controller = harness.container.read(
      activeMembershipControllerProvider,
    );
    final pending = harness.container.read(pendingInviteTokenControllerProvider)
      ..capture('invite-token');
    expect(answers, hasLength(1), reason: 'r1, still in flight');

    // What RedeemEffect.tryConsumePending does.
    await harness.container
        .read(redeemControllerProvider)
        .redeem('invite-token');
    pending.clear();
    await pumpEventQueue();
    expect(answers, hasLength(2), reason: 'the redemption started r2');

    // r1 was asked before the redemption: its verifiedEmpty is stale.
    answers.first.complete(const ActiveOrganizationResolution.verifiedEmpty());
    await pumpEventQueue();

    expect(controller.last, isNull);
    expect(
      controller.viewFor(hasPendingInvite: pending.current != null),
      MembershipGateView.resolving,
    );

    answers.last.complete(const ActiveOrganizationResolution.selected('org-1'));
    await pumpEventQueue();
    expect(
      controller.viewFor(hasPendingInvite: false),
      MembershipGateView.home,
    );
  });

  test(
    'capabilitySnapshotStoreProvider is the Drift identity store (SG6)',
    () async {
      final harness = await _harness(
        session: _session,
        identity: const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
        resolution: _never,
      );

      final store = harness.container.read(capabilitySnapshotStoreProvider);

      expect(store, isA<DriftLastKnownIdentityStore>());
    },
  );

  Future<_Harness> resolverHarness(AppAuthSession session) async {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: _HangingHttpClient(),
    );
    // Never dispose the client: dispose completes the hung requests.
    addTearDown(client.auth.stopAutoRefresh);
    late final _Harness harness;
    harness = await _harness(
      session: session,
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
      resolution: _never,
      extraOverrides: [
        supabaseClientProvider.overrideWithValue(client),
        capabilitySnapshotStoreProvider.overrideWith(
          (_) => harness.identityStore,
        ),
      ],
    );
    await harness.identityStore.writeCapabilityCodes(
      userId: 'user-1',
      organizationId: 'org-1',
      codes: {Capability.editSongs.code},
    );
    return harness;
  }

  test('the real capability resolver answers from the stored set for the '
      'signed-in user (SG6)', () async {
    final harness = await resolverHarness(_session);
    final resolver = harness.container.read(capabilityResolverProvider);

    final capabilities = await resolver
        .capabilitiesFor('org-1')
        .timeout(const Duration(seconds: 5));

    expect(capabilities, {Capability.editSongs});
    expect(resolver.hasCapabilitySync('org-1', Capability.editSongs), isTrue);
  });

  test('the real capability resolver ignores another user\'s stored set '
      '(SG6, XU)', () async {
    final harness = await resolverHarness(
      const AppAuthSession(userId: 'user-2', email: 'other@lyron.local'),
    );
    final resolver = harness.container.read(capabilityResolverProvider);

    var answered = false;
    unawaited(resolver.capabilitiesFor('org-1').then((_) => answered = true));
    await pumpEventQueue();

    expect(answered, isFalse);
    expect(resolver.hasCapabilitySync('org-1', Capability.editSongs), isNull);
  });
}
