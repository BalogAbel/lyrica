import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/pending_local_work_counter.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
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
    addTearDown(authRepository.dispose);
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
      // D5/Phase 4 guardrail: an unverified resolution (connectivity
      // failure) must never set the quarantine marker -- only a genuine
      // ActiveOrganizationVerifiedEmpty resolution reaches
      // resolveVerifiedEmptyMembership.
      expect(identityStore.writes.single.membershipRevokedAt, isNull);
    },
  );

  test(
    'a verifiedEmpty resolution at sign-in quarantines: it deletes nothing '
    'and records the quarantine marker on the identity row (D5, Task 4.1)',
    () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user@example.com',
          organizationId: 'org-1',
        ),
      );
      authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user@example.com',
      );
      final planningDatabase = PlanningLocalDatabase.inMemory();
      final songDatabase = SongCatalogDatabase.inMemory();
      final songStore = DriftSongCatalogStore(songDatabase);
      await songStore.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Kept Song')],
        sources: const [SongSource(id: 'song-1', source: '{title: Kept Song}')],
        refreshedAt: DateTime.utc(2026, 8, 1),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.verifiedEmpty(),
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
      await Future<void>.delayed(Duration.zero);

      // Nothing was deleted: no clear, and the previously cached song is
      // still present.
      expect(identityStore.clearCount, 0);
      expect(
        await songStore.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        hasLength(1),
      );

      // The marker was set on the identity row.
      expect(identityStore.writes, hasLength(1));
      final written = identityStore.writes.single;
      expect(written.userId, 'user-1');
      expect(written.membershipRevokedAt, isNotNull);
    },
  );

  test(
    'a NonConnectivityFailure resolution never reaches '
    'resolveVerifiedEmptyMembership and never sets the quarantine marker '
    '(D5/Phase 4 guardrail)',
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
                const ActiveOrganizationResolution.unknownNonConnectivityFailure(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.organizationId, isNull);
      expect(identityStore.writes.single.membershipRevokedAt, isNull);
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
      // See the D2-rule comment in the 'sessionExpired does not clear the
      // stored identity' test above: the controller needs its own seeded
      // identity for the null event below to land on sessionExpired rather
      // than signedOut.
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user@example.com',
          organizationId: 'org-1',
        ),
      );
      authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
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

      // D5/Phase 4 (ADR-035): a verified-empty resolution now quarantines
      // (one identity write carrying the marker) rather than purging --
      // nothing is cleared.
      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.membershipRevokedAt, isNotNull);
      expect(identityStore.clearCount, 0);
      expect(authController.state.status, AppAuthStatus.signedIn);
    },
  );

  test('verified-empty cleanup updates the controller cache with the '
      'quarantine marker, so a later null session still maps to '
      'sessionExpired, not signedOut', () async {
    // Seed the controller with a prior identity, the same way
    // 'sessionExpired does not clear the stored identity' does, so a null
    // session maps to sessionExpired only while the cache still has
    // something to protect -- isolating the coordinator's own cache write
    // as the thing under test.
    identityStore.seed(
      const LastKnownIdentity(
        userId: 'user-1',
        email: 'user@example.com',
        organizationId: 'org-1',
      ),
    );
    authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
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
          () async => const ActiveOrganizationResolution.selected('org-1'),
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
    await Future<void>.delayed(Duration.zero);

    expect(authController.lastKnownIdentity, isNotNull);

    await container
        .read(verifiedEmptyMembershipCleanupCoordinatorProvider)
        .handleVerifiedEmptyMembership(userId: 'user-1');
    await Future<void>.delayed(Duration.zero);

    // Nothing was cleared: the quarantine marker was set on the same row.
    expect(identityStore.clearCount, 0);
    // The marker must be visible to the controller's cache synchronously
    // with the durable write, not just eventually -- see the class-level
    // note on AppAuthController._identity.
    expect(authController.lastKnownIdentity, isNotNull);
    expect(authController.lastKnownIdentity?.membershipRevokedAt, isNotNull);

    authRepository.emit(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // The identity is quarantined, not gone -- there is still something to
    // protect, so a null session stays offline-authenticated rather than
    // being treated as an explicit sign-out.
    expect(authController.state.status, AppAuthStatus.sessionExpired);
  });

  test("verified-empty cleanup's marker-write failure leaves the "
      'controller cache untouched -- mirrors PR #73 review finding 2 for '
      'the quarantine write: the cache must not be updated before the '
      'durable write it mirrors has actually succeeded', () async {
    identityStore.seed(
      const LastKnownIdentity(
        userId: 'user-1',
        email: 'user@example.com',
        organizationId: 'org-1',
      ),
    );
    authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
    );
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
          () async => const ActiveOrganizationResolution.selected('org-1'),
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
    await Future<void>.delayed(Duration.zero);

    expect(authController.lastKnownIdentity, isNotNull);

    identityStore.throwOnWrite = true;
    await expectLater(
      container
          .read(verifiedEmptyMembershipCleanupCoordinatorProvider)
          .handleVerifiedEmptyMembership(userId: 'user-1'),
      throwsStateError,
    );

    // The durable write never actually committed -- the cache must not
    // have been updated either, or it would diverge from a store that
    // still (as far as this failure proves) holds the old, unquarantined
    // identity. `writes` still has exactly the one entry from the initial
    // restoreSession resolution above; the failed quarantine attempt added
    // no second entry.
    expect(identityStore.writes, hasLength(1));
    expect(authController.lastKnownIdentity, isNotNull);
    expect(authController.lastKnownIdentity?.userId, 'user-1');
    expect(authController.lastKnownIdentity?.membershipRevokedAt, isNull);
  });

  test('sessionExpired does not clear the stored identity', () async {
    authRepository.currentSession = const AppAuthSession(
      userId: 'user-1',
      email: 'user@example.com',
    );
    // Under the D2 rule, a null session only stays offline-authenticated
    // (sessionExpired) when AppAuthController's own identity cache has
    // something to protect. Seed it directly (bypassing write/clearCount
    // recording) to model an identity already persisted from a prior
    // session, and rebuild the controller wired to this store -- the
    // default from setUp has none wired at all.
    identityStore.seed(
      const LastKnownIdentity(
        userId: 'user-1',
        email: 'user@example.com',
        organizationId: 'org-1',
      ),
    );
    authController = AppAuthController(
      authRepository,
      lastKnownIdentityStore: identityStore,
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

  group('different-user reauth resolution on the live signedIn edge', () {
    // Several awaits separate the signedIn edge firing from the resolution
    // settling (identity read, membership resolution, the pending-work
    // count, and -- on the confirm path -- the dialog answer). A single
    // `delayed(Duration.zero)` is not always enough to drain them all.
    Future<void> pump([int times = 6]) async {
      for (var i = 0; i < times; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    late SongCatalogDatabase songDatabase;
    late DriftSongCatalogStore songStore;
    late PlanningLocalDatabase planningDatabase;
    late DriftPlanningLocalStore planningStore;

    setUp(() {
      songDatabase = SongCatalogDatabase.inMemory();
      songStore = DriftSongCatalogStore(songDatabase);
      planningDatabase = PlanningLocalDatabase.inMemory();
      planningStore = DriftPlanningLocalStore(planningDatabase);
    });

    tearDown(() async {
      await songDatabase.close();
      await planningDatabase.close();
    });

    Future<void> seedPriorUserData({
      String userId = 'user-1',
      String organizationId = 'org-1',
    }) async {
      await songStore.replaceActiveSnapshot(
        userId: userId,
        organizationId: organizationId,
        summaries: const [SongSummary(id: 'song-1', title: "Prior's Song")],
        sources: const [
          SongSource(id: 'song-1', source: "{title: Prior's Song}"),
        ],
        refreshedAt: DateTime.utc(2026, 7, 1),
      );
      await planningStore.replaceActiveProjection(
        userId: userId,
        organizationId: organizationId,
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            name: "Prior's Plan",
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        ],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 7, 1),
      );
    }

    Future<bool> priorSongsStillPresent({
      String userId = 'user-1',
      String organizationId = 'org-1',
    }) async {
      final songs = await songStore.readActiveSummaries(
        userId: userId,
        organizationId: organizationId,
      );
      return songs.isNotEmpty;
    }

    Future<bool> priorPlanningProjectionStillPresent({
      String userId = 'user-1',
      String organizationId = 'org-1',
    }) {
      return planningStore.hasProjection(
        userId: userId,
        organizationId: organizationId,
      );
    }

    Future<void> expectUserWideWorkRequiresConfirmation(
      Future<void> Function() seedWork,
    ) async {
      await seedPriorUserData();
      await seedWork();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      expect(
        identityStore.clearCount,
        0,
        reason: 'user-wide local work must not be wiped before confirmation',
      );
      expect(await priorSongsStillPresent(), isTrue);
      expect(await priorPlanningProjectionStillPresent(), isTrue);
      final prompt = container.read(reauthPromptControllerProvider);
      expect(prompt.pending, isNotNull);
      expect(prompt.pending!.email, 'user1@example.com');

      prompt.answer(false);
      await pump();
    }

    test(
      'non-pending planning work prevents silent wipe before confirmation',
      () async {
        await expectUserWideWorkRequiresConfirmation(() {
          return planningDatabase
              .into(planningDatabase.cachedPlanningMutations)
              .insert(
                CachedPlanningMutationsCompanion.insert(
                  userId: 'user-1',
                  organizationId: 'org-1',
                  aggregateType: 'plan',
                  aggregateId: 'accepted-plan',
                  mutationKind: PlanningMutationKind.planEdit.value,
                  syncStatus: PlanningMutationSyncStatus.accepted.value,
                  orderKey: 1,
                  updatedAt: DateTime.utc(2026, 8, 2),
                ),
              );
        });
      },
    );

    test(
      'planning work in a second organization prevents silent wipe before confirmation',
      () async {
        await expectUserWideWorkRequiresConfirmation(() {
          return planningDatabase
              .into(planningDatabase.cachedPlanningMutations)
              .insert(
                CachedPlanningMutationsCompanion.insert(
                  userId: 'user-1',
                  organizationId: 'org-2',
                  aggregateType: 'plan',
                  aggregateId: 'second-org-plan',
                  mutationKind: PlanningMutationKind.planEdit.value,
                  syncStatus: PlanningMutationSyncStatus.pending.value,
                  orderKey: 1,
                  updatedAt: DateTime.utc(2026, 8, 2),
                ),
              );
        });
      },
    );

    test(
      'song work in a second organization prevents silent wipe before confirmation',
      () async {
        await expectUserWideWorkRequiresConfirmation(() {
          return songDatabase
              .into(songDatabase.cachedCatalogSongMutations)
              .insert(
                CachedCatalogSongMutationsCompanion.insert(
                  userId: 'user-1',
                  organizationId: 'org-2',
                  songId: 'second-org-song',
                  slug: 'second-org-song',
                  title: 'Second org song',
                  source: '{title: Second org song}',
                  version: 2,
                  syncStatus: SongSyncStatus.pendingUpdate.value,
                ),
              );
        });
      },
    );

    test('outcome 1: same user flushes -- nothing wiped, no dialog', () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user1@example.com',
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
      await pump();

      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.userId, 'user-1');
      expect(identityStore.clearCount, 0);
      expect(container.read(reauthPromptControllerProvider).pending, isNull);
    });

    test('outcome 2: different user with zero pending wipes the prior user '
        'and proceeds without a dialog', () async {
      await seedPriorUserData();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      // The default (non-overridden) pendingLocalWorkCounterProvider is
      // used here deliberately: against the fresh, empty mutation tables
      // in these in-memory databases it naturally counts zero, so this
      // test also exercises the real provider wiring end to end, not
      // just a stubbed count.
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      expect(container.read(reauthPromptControllerProvider).pending, isNull);
      expect(identityStore.clearCount, 1);
      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.userId, 'user-2');
      expect(await priorSongsStillPresent(), isFalse);
      expect(await priorPlanningProjectionStillPresent(), isFalse);
      expect(authController.state.status, AppAuthStatus.signedIn);
      expect(authController.state.session?.userId, 'user-2');
    });

    test('outcome 3: different user with pending work is confirmed first; on '
        'confirm the prior catalog, planning data and identity are wiped and '
        'the new session proceeds', () async {
      await seedPriorUserData();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      String? seenUserId;
      final counter = PendingLocalWorkCounter(
        readPlanningPendingWorkCount: ({required userId}) async {
          seenUserId = userId;
          return 0;
        },
        readSongPendingWorkCount: ({required userId}) async => 3,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          pendingLocalWorkCounterProvider.overrideWithValue(counter),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      final prompt = container.read(reauthPromptControllerProvider);
      expect(prompt.pending, isNotNull);
      expect(prompt.pending!.email, 'user1@example.com');
      expect(prompt.pending!.pendingCount, 3);
      expect(seenUserId, 'user-1');
      // Nothing destroyed yet -- confirmation has not resolved.
      expect(identityStore.clearCount, 0);
      expect(await priorSongsStillPresent(), isTrue);
      expect(await priorPlanningProjectionStillPresent(), isTrue);

      prompt.answer(true);
      await pump();

      expect(identityStore.clearCount, 1);
      expect(identityStore.writes, hasLength(1));
      expect(identityStore.writes.single.userId, 'user-2');
      expect(await priorSongsStillPresent(), isFalse);
      expect(await priorPlanningProjectionStillPresent(), isFalse);
      expect(authController.state.status, AppAuthStatus.signedIn);
      expect(authController.state.session?.userId, 'user-2');
    });

    test('a wipe whose song deletion throws falls back to cancel instead of '
        'stranding the prior data while presenting as the new user -- '
        'Finding 1, PR #64 review', () async {
      await seedPriorUserData();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      final failingSongStore = _FailingDeleteSongCatalogStore(songStore)
        ..failDeleteCatalogsForUser = true;
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogStoreProvider.overrideWithValue(failingSongStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final reportedErrors = <Object>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) => reportedErrors.add(details.exception);
      addTearDown(() => FlutterError.onError = originalOnError);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      // The device must not be left presenting as the new user (user-2)
      // while the prior user's data sits stranded with no signal: the
      // failed wipe falls back to exactly the state an explicit cancel
      // produces.
      expect(authController.state.status, AppAuthStatus.sessionExpired);
      expect(authController.state.lastKnownSession?.userId, 'user-1');
      expect(authController.state.session, isNull);
      // The identity store must still name the PRIOR user so a later
      // signedIn edge retries the wipe -- not cleared, not overwritten
      // with the new user, as a half-finished wipe would otherwise do.
      expect(identityStore.clearCount, 0);
      expect(identityStore.writes, isEmpty);
      final stillStored = await identityStore.read();
      expect(stillStored?.userId, 'user-1');
      // The failure must be observable, not silently dropped in release.
      expect(reportedErrors, isNotEmpty);
      // No prompt was ever needed for this path (zero pending count):
      // confirm the failure is in the direct-wipe branch, not the
      // confirm-dialog branch.
      expect(container.read(reauthPromptControllerProvider).pending, isNull);
    });

    test('a wipe whose deletions and clear succeed but the new-identity write '
        'throws leaves the store empty and does NOT misrepresent the app as '
        'the prior user -- Finding A, 2026-08-06 remediation round', () async {
      await seedPriorUserData();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      // Zero pending count (default, real reader against empty tables, as
      // in outcome 2 above): the wipe runs directly, no confirm dialog.
      identityStore.throwOnWrite = true;
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final reportedErrors = <Object>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) => reportedErrors.add(details.exception);
      addTearDown(() => FlutterError.onError = originalOnError);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      // The deletions and the clear genuinely succeeded: the prior user's
      // local data is really gone, and the identity store was really
      // cleared.
      expect(await priorSongsStillPresent(), isFalse);
      expect(await priorPlanningProjectionStillPresent(), isFalse);
      expect(identityStore.clearCount, 1);
      // The terminal write for the NEW identity never landed (it threw),
      // and -- unlike a failure in the destructive part above -- nothing
      // here re-writes the PRIOR identity back either: the store is left
      // genuinely empty, honestly reflecting that neither identity is
      // currently persisted, rather than resurrecting a prior-user row
      // that no longer has any data behind it.
      expect(identityStore.writes, isEmpty);
      final stillStored = await identityStore.read();
      expect(stillStored, isNull);
      // The failure must still be observable, not silently dropped.
      expect(reportedErrors, isNotEmpty);
      // The live app state is untouched by this failure: it was already
      // signedIn as user-2 (the real, live backend session) before this
      // listener ran, and stays that way. The OLD behavior -- routing
      // this failure through the same fallback as a destructive-part
      // failure -- would have forced sessionExpired/user-1 here, which is
      // exactly the misleading outcome this test exists to rule out: the
      // prior user's data is actually gone, so presenting the app as
      // "offline-authenticated as user-1" would be a lie, and a cold
      // restart in this state reads a null identity and yields
      // signedOut anyway, never user-1 -- there is nothing for the
      // fallback's implied "next signedIn edge retries the wipe" to
      // detect.
      expect(authController.state.status, AppAuthStatus.signedIn);
      expect(authController.state.session?.userId, 'user-2');
      expect(container.read(reauthPromptControllerProvider).pending, isNull);
    });

    test('outcome 4: cancel signs the new session out, deletes nothing, and '
        'leaves the app offline-authenticated as the prior user', () async {
      await seedPriorUserData();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      final counter = PendingLocalWorkCounter(
        readPlanningPendingWorkCount: ({required userId}) async => 0,
        readSongPendingWorkCount: ({required userId}) async => 1,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          pendingLocalWorkCounterProvider.overrideWithValue(counter),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      final prompt = container.read(reauthPromptControllerProvider);
      expect(prompt.pending, isNotNull);

      prompt.answer(false);
      await pump();

      expect(identityStore.clearCount, 0);
      expect(identityStore.writes, isEmpty);
      expect(await priorSongsStillPresent(), isTrue);
      expect(await priorPlanningProjectionStillPresent(), isTrue);
      expect(authController.state.status, AppAuthStatus.sessionExpired);
      expect(authController.state.lastKnownSession?.userId, 'user-1');
      expect(authController.state.session, isNull);
      // The store must still hold the PRIOR user's identity, not have
      // been cleared or overwritten.
      final stillStored = await identityStore.read();
      expect(stillStored?.userId, 'user-1');
    });

    test('hazard: the prior identity is read before anything on this edge can '
        'overwrite it -- fails if a write ever precedes the read', () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      // The very first call this signedIn transition makes to the store
      // must be the read that observes the prior user -- if a write ever
      // lands first, the prior identity is gone before the different-user
      // check can see it, and this assertion catches that directly.
      expect(identityStore.callLog.first, 'read:user-1');
      // And the read must have been ACTED on correctly: a real
      // different-user wipe happened (proving the read actually returned
      // user-1, not null / an already-overwritten user-2).
      expect(identityStore.clearCount, 1);
      expect(identityStore.writes.last.userId, 'user-2');
    });

    test(
      'hazard: a failure counting prior pending work takes the confirm '
      'path, never the wipe path -- uncertainty must never authorise a wipe',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        authRepository.currentSession = const AppAuthSession(
          userId: 'user-2',
          email: 'user2@example.com',
        );
        final throwingCounter = PendingLocalWorkCounter(
          readPlanningPendingWorkCount: ({required userId}) async =>
              throw StateError('storage failure'),
          readSongPendingWorkCount: ({required userId}) async => 0,
        );
        final container = ProviderContainer(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => authController),
            lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
            songCatalogDatabaseProvider.overrideWithValue(songDatabase),
            planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
            pendingLocalWorkCounterProvider.overrideWithValue(throwingCounter),
            activeOrganizationResolutionProvider.overrideWithValue(
              () async => const ActiveOrganizationResolution.selected('org-2'),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(appAuthListenableProvider);
        await authController.restoreSession();
        await pump();

        final prompt = container.read(reauthPromptControllerProvider);
        // Uncertainty took the confirm path...
        expect(prompt.pending, isNotNull);
        // ...as an honest unknown, never a fabricated number...
        expect(prompt.pending!.pendingCount, isNull);
        // ...never the silent-wipe path.
        expect(identityStore.clearCount, 0);
        expect(identityStore.writes, isEmpty);

        prompt.answer(false);
        await pump();
      },
    );

    test('a newer signedIn edge supersedes the stale prompt without input and '
        'resolves against the still-durable prior identity', () async {
      await seedPriorUserData(userId: 'user-0', organizationId: 'org-0');
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-0',
          email: 'user0@example.com',
          organizationId: 'org-0',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-1',
        email: 'user1@example.com',
      );
      // Always nonzero regardless of which user is asked about, so
      // every different-user edge in this test takes the confirm path.
      final alwaysPendingCounter = PendingLocalWorkCounter(
        readPlanningPendingWorkCount: ({required userId}) async => 0,
        readSongPendingWorkCount: ({required userId}) async => 2,
      );
      final promptController = _RecordingReauthPromptController();
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          pendingLocalWorkCounterProvider.overrideWithValue(
            alwaysPendingCounter,
          ),
          reauthPromptControllerProvider.overrideWith((_) => promptController),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-1'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      expect(promptController.pending, isNotNull);
      expect(promptController.pending!.email, 'user0@example.com');
      final staleRequestId = promptController.pending!.requestId;

      authRepository.emit(
        const AppAuthSession(userId: 'user-2', email: 'user2@example.com'),
      );
      await pump();

      expect(promptController.results, [ReauthPromptResult.superseded]);
      expect(identityStore.clearCount, 0);
      expect(
        identityStore.writes.where((identity) => identity.userId == 'user-1'),
        isEmpty,
      );
      expect(
        await priorSongsStillPresent(userId: 'user-0', organizationId: 'org-0'),
        isTrue,
      );
      expect(
        await priorPlanningProjectionStillPresent(
          userId: 'user-0',
          organizationId: 'org-0',
        ),
        isTrue,
      );
      expect(promptController.pending?.requestId, isNot(staleRequestId));
      expect(promptController.pending?.email, 'user0@example.com');
    });

    test('supersession while the pending-work count is blocked prevents a '
        'stale zero-count wipe', () async {
      await seedPriorUserData();
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      final firstCount = Completer<int>();
      final latestCount = Completer<int>();
      var planningCalls = 0;
      final counter = PendingLocalWorkCounter(
        readPlanningPendingWorkCount: ({required userId}) {
          planningCalls += 1;
          return planningCalls == 1 ? firstCount.future : latestCount.future;
        },
        readSongPendingWorkCount: ({required userId}) async => 0,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          pendingLocalWorkCounterProvider.overrideWithValue(counter),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();
      expect(planningCalls, 1);

      authRepository.emit(
        const AppAuthSession(userId: 'user-3', email: 'user3@example.com'),
      );
      await pump(2);
      firstCount.complete(0);
      await pump();

      expect(identityStore.clearCount, 0);
      expect(identityStore.writes, isEmpty);
      expect(await priorSongsStillPresent(), isTrue);
      expect(await priorPlanningProjectionStillPresent(), isTrue);
    });

    test("resolveReauth's ReauthSuperseded outcome is consumed and logged, not "
        'silently dropped, when a resolution is superseded before it can act '
        '-- Finding 3, PR #64 review', () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
        ),
      );
      authRepository.currentSession = const AppAuthSession(
        userId: 'user-2',
        email: 'user2@example.com',
      );
      final blockedCount = Completer<int>();
      final counter = PendingLocalWorkCounter(
        readPlanningPendingWorkCount: ({required userId}) =>
            blockedCount.future,
        readSongPendingWorkCount: ({required userId}) async => 0,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          pendingLocalWorkCounterProvider.overrideWithValue(counter),
          activeOrganizationResolutionProvider.overrideWithValue(
            () async => const ActiveOrganizationResolution.selected('org-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        messages.add(message ?? '');
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      container.read(appAuthListenableProvider);
      await authController.restoreSession();
      await pump();

      // A newer signedIn edge supersedes this resolution before its
      // pending-count read (still blocked on blockedCount) can resolve.
      authRepository.emit(
        const AppAuthSession(userId: 'user-3', email: 'user3@example.com'),
      );
      await pump(2);
      blockedCount.complete(0);
      await pump();

      // resolveReauth's outcome must be consumed, not just awaited and
      // discarded: the superseded resolution's outcome is observable
      // here as a logged trace, proving the return value had a real
      // effect in production rather than only being read by tests.
      expect(
        messages.any((message) => message.contains('superseded')),
        isTrue,
        reason:
            'a superseded resolution outcome must be consumed and '
            'logged, not silently dropped',
      );
    });

    test(
      'supersession immediately before cancel prevents backend sign-out',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        authRepository.currentSession = const AppAuthSession(
          userId: 'user-2',
          email: 'user2@example.com',
        );
        final counter = PendingLocalWorkCounter(
          readPlanningPendingWorkCount: ({required userId}) async => 1,
          readSongPendingWorkCount: ({required userId}) async => 0,
        );
        final container = ProviderContainer(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => authController),
            lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
            pendingLocalWorkCounterProvider.overrideWithValue(counter),
            activeOrganizationResolutionProvider.overrideWithValue(
              () async => const ActiveOrganizationResolution.selected('org-2'),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(appAuthListenableProvider);
        await authController.restoreSession();
        await pump();
        final prompt = container.read(reauthPromptControllerProvider);
        final requestId = prompt.pending!.requestId;
        final newerEdgeObserved = Completer<void>();
        void observeNewerEdge() {
          if (authController.state.session?.userId == 'user-3' &&
              !newerEdgeObserved.isCompleted) {
            newerEdgeObserved.complete();
          }
        }

        authController.addListener(observeNewerEdge);
        addTearDown(() => authController.removeListener(observeNewerEdge));

        authRepository.emit(
          const AppAuthSession(userId: 'user-3', email: 'user3@example.com'),
        );
        await newerEdgeObserved.future;
        expect(authController.state.session?.userId, 'user-3');

        prompt.answer(false, requestId: requestId);
        await pump();

        expect(authRepository.signOutCalls, 0);
        expect(prompt.pending?.requestId, isNot(requestId));
      },
    );

    test(
      'supersession while same-user membership is blocked prevents a stale write',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        authRepository.currentSession = const AppAuthSession(
          userId: 'user-1',
          email: 'user1@example.com',
        );
        final firstMembership = Completer<ActiveOrganizationResolution>();
        final latestMembership = Completer<ActiveOrganizationResolution>();
        var membershipCalls = 0;
        final container = ProviderContainer(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => authController),
            lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
            activeOrganizationResolutionProvider.overrideWithValue(() {
              membershipCalls += 1;
              return membershipCalls == 1
                  ? firstMembership.future
                  : latestMembership.future;
            }),
          ],
        );
        addTearDown(container.dispose);

        container.read(appAuthListenableProvider);
        await authController.restoreSession();
        await pump();
        authRepository.emit(
          const AppAuthSession(userId: 'user-2', email: 'user2@example.com'),
        );
        await pump(2);
        firstMembership.complete(
          const ActiveOrganizationResolution.selected('org-1'),
        );
        await pump();

        expect(identityStore.writes, isEmpty);
      },
    );

    test(
      'supersession during the post-wipe clear prevents stale identity persistence',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        identityStore.blockNextClear();
        authRepository.currentSession = const AppAuthSession(
          userId: 'user-2',
          email: 'user2@example.com',
        );
        final latestMembership = Completer<ActiveOrganizationResolution>();
        var membershipCalls = 0;
        final counter = PendingLocalWorkCounter(
          readPlanningPendingWorkCount: ({required userId}) async => 0,
          readSongPendingWorkCount: ({required userId}) async => 0,
        );
        final container = ProviderContainer(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => authController),
            lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
            songCatalogDatabaseProvider.overrideWithValue(songDatabase),
            planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
            pendingLocalWorkCounterProvider.overrideWithValue(counter),
            activeOrganizationResolutionProvider.overrideWithValue(() {
              membershipCalls += 1;
              return membershipCalls == 1
                  ? Future.value(
                      const ActiveOrganizationResolution.selected('org-2'),
                    )
                  : latestMembership.future;
            }),
          ],
        );
        addTearDown(container.dispose);

        container.read(appAuthListenableProvider);
        await authController.restoreSession();
        await identityStore.clearStarted;

        authRepository.emit(
          const AppAuthSession(userId: 'user-3', email: 'user3@example.com'),
        );
        await pump(2);
        identityStore.releaseClear();
        await pump();

        expect(
          identityStore.writes.where((identity) => identity.userId == 'user-2'),
          isEmpty,
        );
      },
    );
  });
}

class _RecordingLastKnownIdentityStore implements LastKnownIdentityStore {
  LastKnownIdentity? _current;
  final List<LastKnownIdentity> writes = <LastKnownIdentity>[];
  int clearCount = 0;
  Completer<void>? _clearStarted;
  Completer<void>? _clearGate;

  /// Finding A (2026-08-06 remediation round): makes the NEXT [write] throw
  /// instead of applying, to model a storage failure that hits only the
  /// terminal identity write -- after a wipe's deletions and
  /// [identityStore.clear] have already succeeded. Thrown before touching
  /// [writes]/[_current], so a throwing write leaves both exactly as [clear]
  /// left them (empty), never recorded as if it had applied.
  bool throwOnWrite = false;

  /// Makes the NEXT [clear] throw instead of applying, to model a storage
  /// failure on a verified-empty-membership purge -- see PR #73 review
  /// finding 2. Thrown before touching [clearCount]/[_current], so a
  /// throwing clear leaves both exactly as they were, never recorded as if
  /// it had applied.
  bool throwOnClear = false;

  Future<void> get clearStarted => _clearStarted!.future;

  void blockNextClear() {
    _clearStarted = Completer<void>();
    _clearGate = Completer<void>();
  }

  void releaseClear() => _clearGate!.complete();

  /// Log of every store call in the order it happened, e.g. `read:user-1`,
  /// `write:user-2`, `clear`. Used to prove the prior identity is read
  /// before it can be overwritten -- an assertion on the outcome alone
  /// ("was there a wipe") can't distinguish "read first, correctly" from
  /// "read second, by luck of the current implementation".
  final List<String> callLog = <String>[];

  /// Seeds the store's current value directly (bypassing [write], so it
  /// does not show up in [writes] or [callLog]) -- models a
  /// LastKnownIdentity row already persisted from a PRIOR app session,
  /// before the transition under test begins.
  void seed(LastKnownIdentity identity) {
    _current = identity;
  }

  @override
  Future<LastKnownIdentity?> read() async {
    callLog.add('read:${_current?.userId}');
    return _current;
  }

  @override
  Future<void> write(LastKnownIdentity identity) async {
    if (throwOnWrite) {
      throw StateError('storage failure: write');
    }
    callLog.add('write:${identity.userId}');
    writes.add(identity);
    _current = identity;
  }

  @override
  Future<void> clear() async {
    if (throwOnClear) {
      throw StateError('storage failure: clear');
    }
    final started = _clearStarted;
    final gate = _clearGate;
    if (started != null && gate != null) {
      started.complete();
      await gate.future;
      _clearStarted = null;
      _clearGate = null;
    }
    callLog.add('clear');
    clearCount += 1;
    _current = null;
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? currentSession;
  int signOutCalls = 0;

  void dispose() {
    _controller.close();
  }

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
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  @override
  Future<void> deleteAccount() async {}

  void emit(AppAuthSession? session) => _controller.add(session);
}

class _RecordingReauthPromptController extends ReauthPromptController {
  final List<ReauthPromptResult> results = <ReauthPromptResult>[];

  @override
  Future<ReauthPromptResult> requestConfirmation({
    required String email,
    required int? pendingCount,
  }) {
    final future = super.requestConfirmation(
      email: email,
      pendingCount: pendingCount,
    );
    unawaited(future.then(results.add));
    return future;
  }
}

/// Forwards every call to a real [DriftSongCatalogStore] except
/// [deleteCatalogsForUser], which can be made to fail on demand -- models a
/// storage failure partway through `wipePriorAndProceed` (Finding 1, PR #64
/// review) without hand-rolling every other method on the interface. The
/// failure surfaces as a rejected Future (the method is `async`), matching
/// how a real Drift query failure would actually propagate, rather than a
/// synchronous throw that would prevent the concurrent planning deletion
/// from ever starting.
class _FailingDeleteSongCatalogStore implements SongCatalogStore {
  _FailingDeleteSongCatalogStore(this._inner);

  final SongCatalogStore _inner;
  bool failDeleteCatalogsForUser = false;

  @override
  Future<void> deleteCatalogsForUser({required String userId}) async {
    if (failDeleteCatalogsForUser) {
      throw StateError('storage failure: deleteCatalogsForUser');
    }
    return _inner.deleteCatalogsForUser(userId: userId);
  }

  @override
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  }) => _inner.replaceActiveSnapshot(
    userId: userId,
    organizationId: organizationId,
    summaries: summaries,
    sources: sources,
    refreshedAt: refreshedAt,
  );

  @override
  Future<EmptySnapshotResolution> resolveEmptySnapshot({
    required String userId,
    required String organizationId,
  }) => _inner.resolveEmptySnapshot(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  }) => _inner.readActiveSummaries(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<SongSummary?> readActiveSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => _inner.readActiveSummaryBySlug(
    userId: userId,
    organizationId: organizationId,
    songSlug: songSlug,
  );

  @override
  Future<SongSummary?> readActiveSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _inner.readActiveSummaryById(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _inner.readActiveSource(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<String?> readLatestCachedOrganizationId({required String userId}) =>
      _inner.readLatestCachedOrganizationId(userId: userId);

  @override
  Future<void> saveSongMutation(SongCatalogMutationDraft mutation) =>
      _inner.saveSongMutation(mutation);

  @override
  Future<bool> hasUnsyncedSongMutations({required String userId}) =>
      _inner.hasUnsyncedSongMutations(userId: userId);

  @override
  Future<List<CachedCatalogSongMutation>> readSongMutations({
    required String userId,
    required String organizationId,
    List<SongSyncStatus>? syncStatuses,
  }) => _inner.readSongMutations(
    userId: userId,
    organizationId: organizationId,
    syncStatuses: syncStatuses,
  );

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySongId({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _inner.readSongMutationBySongId(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => _inner.readSongMutationBySlug(
    userId: userId,
    organizationId: organizationId,
    songSlug: songSlug,
  );

  @override
  Future<bool> hasVisibleSongSlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => _inner.hasVisibleSongSlug(
    userId: userId,
    organizationId: organizationId,
    songSlug: songSlug,
  );

  @override
  Future<String> allocateAvailableSongSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) => _inner.allocateAvailableSongSlug(
    userId: userId,
    organizationId: organizationId,
    title: title,
  );

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) => _inner.deleteSong(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
  );

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
    int? expectedRevision,
  }) => _inner.reconcileSyncedSong(
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
  }) => _inner.clearSongMutation(
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
  }) => _inner.markSongCreateSending(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    expectedRevision: expectedRevision,
  );

  @override
  Future<int?> saveSongMutationStatus({
    required String userId,
    required String organizationId,
    required String songId,
    required String syncStatus,
    String? syncErrorContext,
    int? expectedRevision,
  }) => _inner.saveSongMutationStatus(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    syncStatus: syncStatus,
    syncErrorContext: syncErrorContext,
    expectedRevision: expectedRevision,
  );

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) => _inner.resolveCancelledSongCreate(
    userId: userId,
    organizationId: organizationId,
    songId: songId,
    created: created,
    acceptedVersion: acceptedVersion,
  );

  @override
  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  }) => _inner.deleteCatalog(userId: userId, organizationId: organizationId);
}
