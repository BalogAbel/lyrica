import 'dart:async';

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

        authRepository.emit(
          const AppAuthSession(userId: 'user-3', email: 'user3@example.com'),
        );
        prompt.answer(false, requestId: requestId);
        await pump();

        expect(authRepository.signOutCalls, 0);
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
    callLog.add('write:${identity.userId}');
    writes.add(identity);
    _current = identity;
  }

  @override
  Future<void> clear() async {
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
