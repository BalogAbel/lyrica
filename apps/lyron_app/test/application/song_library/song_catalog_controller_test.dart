import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SongCatalogController', () {
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;
    late _FakeSongRepository remoteRepository;
    late LocalDataLifecycle lifecycle;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
      remoteRepository = _FakeSongRepository();
      lifecycle = LocalDataLifecycle(
        songCatalogStore: store,
        planningLocalStore: _NoopPlanningLocalStore(),
        identityStore: _NoopLastKnownIdentityStore(),
        noteLastKnownIdentity: (_) {},
        eventsRecorder: _NoopLocalDataEventsRecorder(),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'first successful refresh creates an active cached snapshot',
      () async {
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.context,
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        );
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.online,
        );
        expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
        expect(controller.state.sessionStatus, CatalogSessionStatus.verified);
        expect(controller.state.hasCachedCatalog, isTrue);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [
            SongSummary(id: 'song-1', title: 'Alpha'),
            SongSummary(id: 'song-2', title: 'Beta'),
          ],
        );
      },
    );

    test('keeps the previous active snapshot when refresh fails', () async {
      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      await controller.refreshCatalog();
      remoteRepository.listSongsError = const SocketException('offline');

      await controller.refreshCatalog();

      expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
      expect(
        controller.state.connectionStatus,
        CatalogConnectionStatus.offlineCached,
      );
      expect(controller.state.hasCachedCatalog, isTrue);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        const [
          SongSummary(id: 'song-1', title: 'Alpha'),
          SongSummary(id: 'song-2', title: 'Beta'),
        ],
      );
    });

    test(
      'treats a backend unavailable refresh failure as offline while keeping the cached catalog readable',
      () async {
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await controller.refreshCatalog();
        remoteRepository.listSongsError = const PostgrestException(
          message: 'Service unavailable',
          code: '503',
          details: 'upstream connect error',
        );

        await controller.refreshCatalog();

        expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.offlineCached,
        );
        expect(
          controller.state.sessionStatus,
          CatalogSessionStatus.unverifiableDueToConnectivity,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
      },
    );

    test(
      'cached summaries remain available when connectivity is lost',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async =>
              CatalogSessionStatus.unverifiableDueToConnectivity,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.offlineCached,
        );
        expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
        expect(
          controller.state.sessionStatus,
          CatalogSessionStatus.unverifiableDueToConnectivity,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [SongSummary(id: 'song-1', title: 'Cached Song')],
        );
      },
    );

    test(
      'falls back to the cached organization context when connectivity loss prevents remote resolution',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async =>
              throw const SocketException('offline'),
          sessionVerifier: () async =>
              CatalogSessionStatus.unverifiableDueToConnectivity,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.context,
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        );
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.offlineCached,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
      },
    );

    test(
      // D5.4/D5.5 (docs/specs/2026-08-19-local-data-durability-contract.md,
      // ADR-035 Phase 4): a verified-empty resolution no longer purges by
      // itself -- SongCatalogController now defers entirely to the injected
      // handler's reported outcome (in production,
      // VerifiedEmptyMembershipCleanupCoordinator, gated on two confirmations
      // through LocalDataLifecycle). This test simulates a handler that has
      // already run a genuine purge (returns true) to pin the controller's
      // OWN responsibility on that outcome: reset _state to empty and let the
      // cached-fallback short-circuit stay closed. The single-confirmation
      // behaviour this test used to pin (no handler at all) was exactly the
      // F4 bug D5 exists to close, and is now covered separately by "a
      // verified empty membership resolution with no purge handler leaves
      // cached song data untouched" below.
      'verified empty membership clears cached song data and prevents cached fallback from reopening later once the handler reports a genuine purge',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );
        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-2',
            slug: 'draft-song',
            title: 'Draft Song',
            source: '{title: Draft Song}',
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        );

        late Future<String?> Function() organizationReader;
        organizationReader = () async => null;

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () => organizationReader(),
          sessionVerifier: () async => CatalogSessionStatus.verified,
          // Stands in for VerifiedEmptyMembershipCleanupCoordinator having
          // already run a genuine two-confirmation purge through
          // LocalDataLifecycle -- this test is only pinning what the
          // CONTROLLER does once told a purge happened, not the gate itself
          // (covered by local_data_lifecycle_test.dart).
          onVerifiedEmptyMembership: ({required userId}) async {
            await lifecycle.purgeSongCatalog(
              userId: userId,
              reason: PurgeReason.membershipRevokedConfirmed,
            );
            return true;
          },
        );

        await controller.refreshCatalog();

        expect(controller.state.context, isNull);
        expect(controller.state.hasCachedCatalog, isFalse);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
        expect(
          await store.readSongMutations(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
        expect(
          await store.readLatestCachedOrganizationId(userId: 'user-1'),
          isNull,
        );

        organizationReader = () async => throw const SocketException('offline');

        await controller.refreshCatalog();

        expect(controller.state.context, isNull);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.unavailable,
        );
        expect(controller.state.hasCachedCatalog, isFalse);
        expect(remoteRepository.listSongsCalls, 0);
      },
    );

    test(
      // Required test 9 (D5.4/D5.5, ADR-035 Phase 4): reads stay served
      // during and after a first (non-purging) confirmation -- the catalog
      // context must NOT be reset when the coordinator reports nothing was
      // purged (a single verified-empty resolution, or a second one still
      // short of a confirmed purge). ADR-020's read access is unchanged
      // until data is genuinely gone.
      'a verified empty membership resolution that does not purge (handler '
      'reports false) leaves cached song data and context fully intact',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => null,
          sessionVerifier: () async => CatalogSessionStatus.verified,
          // Only the marker was recorded / re-confirmed -- no purge ran.
          onVerifiedEmptyMembership: ({required userId}) async => false,
        );

        await controller.refreshCatalog();

        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          hasLength(1),
        );
      },
    );

    test(
      // RED 1 (final whole-branch review): empty -> fresh non-empty -> empty
      // must be TWO independent first confirmations, not one confirmation
      // plus a second. The middle, genuine non-empty resolution must clear
      // the D5.1 marker; a bug that skips the clear lets the trailing empty
      // count as the "second" confirmation and purge on a false premise.
      'a genuine fresh non-empty resolution between two empties clears the '
      'membership-revocation marker so the trailing empty is a first '
      'confirmation again, not a purge',
      () async {
        final identityDatabase = LastKnownIdentityDatabase.inMemory();
        addTearDown(identityDatabase.close);
        final identityStore = DriftLastKnownIdentityStore(identityDatabase);
        final gatedLifecycle = LocalDataLifecycle(
          songCatalogStore: store,
          planningLocalStore: _NoopPlanningLocalStore(),
          identityStore: identityStore,
          noteLastKnownIdentity: (_) {},
          eventsRecorder: _NoopLocalDataEventsRecorder(),
          // Cooldown is irrelevant to this repro (it is about which
          // resolution counts as first vs. second, not timing), so zero it
          // out to keep the test deterministic without a fake clock.
          membershipConfirmationCooldown: Duration.zero,
        );
        await identityStore.write(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'demo@lyron.local',
            organizationId: 'org-1',
          ),
        );

        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        Future<bool> handleVerifiedEmptyMembership({
          required String userId,
        }) async {
          final decision = await gatedLifecycle.resolveVerifiedEmptyMembership(
            userId: userId,
          );
          if (decision is! MembershipRevocationPurgeAuthorized) {
            return false;
          }
          return gatedLifecycle.maybePurgeForMembershipRevocation(
            userId: userId,
            markedAt: decision.markedAt,
            countPendingWork: () async => 0,
            requestConfirmation: ({required pendingCount}) async =>
                ReauthPromptResult.confirmed,
          );
        }

        final organizationIds = <String?>[null, 'org-1', null];
        var callIndex = 0;

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: gatedLifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => organizationIds[callIndex++],
          sessionVerifier: () async => CatalogSessionStatus.verified,
          onVerifiedEmptyMembership: handleVerifiedEmptyMembership,
          onVerifiedNonEmptyMembership: ({required userId}) =>
              gatedLifecycle.clearMembershipRevocation(userId: userId),
        );

        // T0: live RPC -> VerifiedEmpty (transient) -> marker set.
        await controller.refreshCatalog();

        // T0+30s: live RPC -> Selected('org-1') -- a genuine, fresh,
        // online, authenticated non-empty resolution. Must clear the
        // marker.
        await controller.refreshCatalog();

        // T0+90s: live RPC -> VerifiedEmpty again. If the marker was
        // correctly cleared above, this is a FIRST confirmation again, not
        // a second -- nothing may be deleted.
        await controller.refreshCatalog();

        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isNotEmpty,
          reason:
              'the genuine non-empty resolution between the two empties '
              'must have cleared the marker, so the second empty is a '
              'first confirmation again -- nothing should have been '
              'purged',
        );
      },
    );

    test(
      // The marker clear is awaited, not fire-and-forget: a dropped store
      // failure would leave the marker set with no audit record and no
      // retry, silently reinstating the empty/non-empty/empty purge
      // sequence the clear exists to break. It must still not break the
      // read path (ADR-020) -- the failure is reported, not rethrown.
      'a failing membership-revocation marker clear is reported and does '
      'not break the refresh or hide the cached catalog',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final reported = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previousOnError);

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          onVerifiedNonEmptyMembership: ({required userId}) async {
            throw StateError('simulated identity store failure');
          },
        );
        addTearDown(controller.dispose);

        await controller.refreshCatalog();

        expect(
          reported,
          hasLength(1),
          reason:
              'the clear failure must be reported, not swallowed -- it '
              'leaves the marker set',
        );
        expect(controller.state.context, isNotNull);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isNotEmpty,
        );
      },
    );

    test(
      // YELLOW 7 (final whole-branch review, D5.5 rule 4): `session` is
      // captured at the top of _refreshCatalog and used, unrevalidated, to
      // enter the purge gate. Re-read and compare identity immediately
      // before the handler call, so a resolution captured under one user
      // cannot purge a different user's data after that user signs in
      // during the awaited organization lookup.
      'does not enter the purge gate when a different user signed in while '
      'the organization lookup was in flight',
      () async {
        var handlerCalls = 0;
        AppAuthSession currentSession = const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () => currentSession,
          organizationReader: () async {
            // Simulate a different user signing in during this await --
            // exactly the race the currentness re-check must catch.
            currentSession = const AppAuthSession(
              userId: 'user-2',
              email: 'other@lyron.local',
            );
            return null;
          },
          sessionVerifier: () async => CatalogSessionStatus.verified,
          onVerifiedEmptyMembership: ({required userId}) async {
            handlerCalls++;
            return false;
          },
        );

        await controller.refreshCatalog();

        expect(
          handlerCalls,
          0,
          reason:
              'the purge gate must not run for a resolution captured under '
              'a user who is no longer the current session by the time the '
              'gate is entered',
        );
      },
    );

    test(
      // FIX 2 (re-review, D5.5 rule 4): the non-empty branch used to enter
      // the marker-clear gate with only `_isStale(generation)` guarding it,
      // which does not assert session identity. Re-read and compare
      // immediately before the clear call, mirroring the verified-empty
      // branch's YELLOW 7 fix above.
      'does not enter the marker-clear gate when a different user signed '
      'in while the organization lookup was in flight',
      () async {
        var handlerCalls = 0;
        AppAuthSession currentSession = const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () => currentSession,
          organizationReader: () async {
            // Simulate a different user signing in during this await --
            // exactly the race the currentness re-check must catch.
            currentSession = const AppAuthSession(
              userId: 'user-2',
              email: 'other@lyron.local',
            );
            return 'org-1';
          },
          sessionVerifier: () async => CatalogSessionStatus.verified,
          onVerifiedNonEmptyMembership: ({required userId}) async {
            handlerCalls++;
          },
        );

        await controller.refreshCatalog();

        expect(
          handlerCalls,
          0,
          reason:
              'the marker-clear gate must not run for a resolution '
              'captured under a user who is no longer the current session '
              'by the time the gate is entered',
        );
      },
    );

    test(
      'falls back to the cached organization context when organization resolution returns backend unavailable',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => throw const PostgrestException(
            message: 'Service unavailable',
            code: '503',
            details: 'upstream connect error',
          ),
          sessionVerifier: () async =>
              CatalogSessionStatus.unverifiableDueToConnectivity,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.context,
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        );
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.offlineCached,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
      },
    );

    test(
      'non-connectivity organization resolution failure keeps the established catalog boundary without reusing cached fallback',
      () async {
        final organizationReaderState = _MutableOrganizationReader('org-1');
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: organizationReaderState.read,
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await controller.refreshCatalog();

        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-2',
          summaries: const [SongSummary(id: 'song-2', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-2', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 11),
        );
        organizationReaderState.nextError = StateError('malformed response');

        await expectLater(controller.refreshCatalog(), completes);

        expect(
          controller.state.context,
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        );
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.online,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
        expect(remoteRepository.listSongsCalls, 1);
      },
    );

    test(
      'confirmed session expiry blocks cached authenticated reading',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final foregroundState = _TestAppForegroundState();
        var sessionVerifierCalls = 0;

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async {
            sessionVerifierCalls += 1;
            return CatalogSessionStatus.expired;
          },
          foregroundState: foregroundState,
          refreshInterval: const Duration(milliseconds: 1),
        );

        await controller.refreshCatalog();

        expect(controller.state.context, isNull);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.unavailable,
        );
        expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
        expect(controller.state.hasCachedCatalog, isFalse);
        expect(sessionVerifierCalls, 1);

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(sessionVerifierCalls, 1);
      },
    );

    test(
      'authorization failure while resolving the active organization degrades to expired access instead of throwing',
      () async {
        final foregroundState = _TestAppForegroundState();
        var organizationCalls = 0;
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async {
            organizationCalls += 1;
            throw const PostgrestException(
              message: 'permission denied',
              code: '42501',
            );
          },
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(milliseconds: 1),
        );

        await expectLater(controller.refreshCatalog(), completes);

        expect(controller.state.context, isNull);
        expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.unavailable,
        );
        expect(organizationCalls, 1);

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(organizationCalls, 1);
      },
    );

    test(
      'authorization failure while refreshing the song catalog expires the session and stops refresh retries',
      () async {
        final foregroundState = _TestAppForegroundState();
        final delayedRepository = _DelayedSongRepository();
        AppAuthSession? session;

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: delayedRepository,
          authSessionReader: () => session,
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(milliseconds: 1),
        );
        addTearDown(controller.dispose);

        session = const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        );
        controller.handleSessionAvailable();

        final refreshFuture = controller.refreshCatalog();
        await delayedRepository.listSongsStarted.future;
        expect(delayedRepository.listSongsCalls, 1);

        delayedRepository.failWith(
          const PostgrestException(message: 'permission denied', code: '403'),
        );
        await refreshFuture;

        expect(controller.state.context, isNull);
        expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.unavailable,
        );
        expect(controller.state.hasCachedCatalog, isFalse);
        expect(delayedRepository.listSongsCalls, 1);

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(delayedRepository.listSongsCalls, 1);
      },
    );

    test('explicit sign-out deletes the cached catalog', () async {
      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      await controller.refreshCatalog();
      await controller.handleExplicitSignOut();

      expect(controller.state.context, isNull);
      expect(controller.state.hasCachedCatalog, isFalse);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    });

    test(
      'explicit sign-out clears cached access even when the active context was not yet loaded',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => throw const PostgrestException(
            message: 'permission denied',
            code: '42501',
          ),
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await controller.handleExplicitSignOut();

        expect(controller.state.context, isNull);
        expect(controller.state.hasCachedCatalog, isFalse);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'explicit sign-out prevents an in-flight refresh from restoring cached authenticated access',
      () async {
        final delayedRepository = _DelayedSongRepository();
        final foregroundState = _TestAppForegroundState();
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: delayedRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
        );

        final refreshFuture = controller.refreshCatalog();
        await delayedRepository.listSongsStarted.future;

        await controller.handleExplicitSignOut();
        delayedRepository.completeWith(
          const [SongSummary(id: 'song-1', title: 'Alpha')],
          const {'song-1': SongSource(id: 'song-1', source: '{title: Alpha}')},
        );
        await refreshFuture;

        expect(controller.state.context, isNull);
        expect(controller.state.hasCachedCatalog, isFalse);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'ignores a periodic trigger while a manual refresh is already in flight',
      () {
        fakeAsync((async) {
          final delayedRepository = _DelayedSongRepository();
          final foregroundState = _TestAppForegroundState();
          final controller = SongCatalogController(
            onImplausibleEmptySnapshot:
                ({required userId, required organizationId}) async {},
            store: store,
            localDataLifecycle: lifecycle,
            remoteRepository: delayedRepository,
            authSessionReader: () => const AppAuthSession(
              userId: 'user-1',
              email: 'demo@lyron.local',
            ),
            organizationReader: () async => 'org-1',
            sessionVerifier: () async => CatalogSessionStatus.verified,
            foregroundState: foregroundState,
            refreshInterval: const Duration(minutes: 5),
          );
          addTearDown(controller.dispose);

          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();

          expect(delayedRepository.listSongsCalls, 1);

          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();

          expect(delayedRepository.listSongsCalls, 1);
          delayedRepository.completeWith(
            const [SongSummary(id: 'song-1', title: 'Alpha')],
            const {
              'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
            },
          );
          async.flushMicrotasks();

          expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
          expect(controller.state.hasCachedCatalog, isTrue);
        });
      },
    );

    test('runs periodic refresh only after the configured cadence', () {
      fakeAsync((async) {
        final foregroundState = _TestAppForegroundState();
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(minutes: 5),
        );

        async.elapse(const Duration(minutes: 4, seconds: 59));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 0);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);

        controller.dispose();
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);
      });
    });

    test('a controller wired to the real WidgetsBindingAppForegroundState '
        'still runs the periodic refresh when the binding reported a '
        'non-resumed lifecycle state before construction', () {
      // Reproduces the production seam: the binding already reports a
      // non-resumed state (e.g. hidden, as observed on web) before the
      // foreground state observer is constructed. Per
      // docs/specs/2026-08-08-web-catalog-refresh-race.md (D3), that
      // pre-settle sample must not disarm the recovery timer.
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );
      final foregroundState = WidgetsBindingAppForegroundState();
      addTearDown(foregroundState.dispose);

      fakeAsync((async) {
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () =>
              const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(minutes: 5),
        );
        addTearDown(controller.dispose);

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();

        expect(remoteRepository.listSongsCalls, 1);
      });
    });

    test(
      'runs periodic refresh only while the app stays in the foreground',
      () {
        fakeAsync((async) {
          final foregroundState = _TestAppForegroundState(isForeground: false);
          final controller = SongCatalogController(
            onImplausibleEmptySnapshot:
                ({required userId, required organizationId}) async {},
            store: store,
            localDataLifecycle: lifecycle,
            remoteRepository: remoteRepository,
            authSessionReader: () => const AppAuthSession(
              userId: 'user-1',
              email: 'demo@lyron.local',
            ),
            organizationReader: () async => 'org-1',
            sessionVerifier: () async => CatalogSessionStatus.verified,
            foregroundState: foregroundState,
            refreshInterval: const Duration(minutes: 5),
          );
          addTearDown(controller.dispose);

          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(remoteRepository.listSongsCalls, 0);

          foregroundState.setForeground(true);
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(remoteRepository.listSongsCalls, 1);

          foregroundState.setForeground(false);
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(remoteRepository.listSongsCalls, 1);
        });
      },
    );

    test('stops periodic refresh after explicit sign-out', () {
      fakeAsync((async) {
        final foregroundState = _TestAppForegroundState();
        AppAuthSession? session = const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        );
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: remoteRepository,
          authSessionReader: () => session,
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(minutes: 5),
        );
        addTearDown(controller.dispose);

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);

        session = null;
        unawaited(controller.handleExplicitSignOut());
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);
      });
    });

    test(
      'a stale in-flight refresh still prevents overlapping refresh work after explicit sign-out',
      () {
        fakeAsync((async) {
          final delayedRepository = _MultiPhaseSongRepository();
          final foregroundState = _TestAppForegroundState();
          AppAuthSession? session = const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyron.local',
          );
          final controller = SongCatalogController(
            onImplausibleEmptySnapshot:
                ({required userId, required organizationId}) async {},
            store: store,
            localDataLifecycle: lifecycle,
            remoteRepository: delayedRepository,
            authSessionReader: () => session,
            organizationReader: () async => 'org-1',
            sessionVerifier: () async => CatalogSessionStatus.verified,
            foregroundState: foregroundState,
            refreshInterval: const Duration(minutes: 5),
          );
          addTearDown(controller.dispose);

          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();
          expect(delayedRepository.listSongsCalls, 1);

          session = null;
          unawaited(controller.handleExplicitSignOut());
          async.flushMicrotasks();

          session = const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyron.local',
          );
          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();

          expect(delayedRepository.listSongsCalls, 1);

          delayedRepository.completeRequest(0);
          async.flushMicrotasks();

          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();
          expect(delayedRepository.listSongsCalls, 2);

          delayedRepository.completeRequest(1);
          async.flushMicrotasks();
        });
      },
    );

    test('a refresh dispatched with a null session is superseded by a refresh '
        'dispatched under a real session before the first settles', () async {
      AppAuthSession? session;
      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () => session,
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      final nullSessionRefresh = controller.refreshCatalog();
      session = const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      );
      final signedInRefresh = controller.refreshCatalog();

      await nullSessionRefresh;
      await signedInRefresh;

      expect(remoteRepository.listSongsCalls, 1);
      expect(
        controller.state.context,
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
      expect(controller.state.hasCachedCatalog, isTrue);
    });

    test('two refreshes under the same session identity while one is in '
        'flight still coalesce into a single remote call', () async {
      final delayedRepository = _DelayedSongRepository();
      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: delayedRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      final first = controller.refreshCatalog();
      await delayedRepository.listSongsStarted.future;
      final second = controller.refreshCatalog();

      expect(delayedRepository.listSongsCalls, 1);

      delayedRepository.completeWith(
        const [SongSummary(id: 'song-1', title: 'Alpha')],
        const {'song-1': SongSource(id: 'song-1', source: '{title: Alpha}')},
      );

      await first;
      await second;

      expect(delayedRepository.listSongsCalls, 1);
    });

    test('a burst of differing-identity triggers during one in-flight refresh '
        'queues at most one follow-up refresh', () {
      fakeAsync((async) {
        final delayedRepository = _MultiPhaseSongRepository();
        AppAuthSession? session = const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        );
        final controller = SongCatalogController(
          onImplausibleEmptySnapshot:
              ({required userId, required organizationId}) async {},
          store: store,
          localDataLifecycle: lifecycle,
          remoteRepository: delayedRepository,
          authSessionReader: () => session,
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          refreshInterval: const Duration(minutes: 5),
        );
        addTearDown(controller.dispose);

        unawaited(controller.refreshCatalog());
        async.flushMicrotasks();
        expect(delayedRepository.listSongsCalls, 1);

        session = const AppAuthSession(
          userId: 'user-2',
          email: 'other@lyron.local',
        );
        unawaited(controller.refreshCatalog());
        unawaited(controller.refreshCatalog());
        unawaited(controller.refreshCatalog());
        async.flushMicrotasks();

        // The in-flight refresh (for user-1) hasn't settled yet, so no
        // follow-up has dispatched.
        expect(delayedRepository.listSongsCalls, 1);

        delayedRepository.completeRequest(0);
        async.flushMicrotasks();

        // Exactly one follow-up refresh runs for the burst of three
        // differing-identity triggers, not three.
        expect(delayedRepository.listSongsCalls, 2);

        delayedRepository.completeRequest(1);
        async.flushMicrotasks();
      });
    });

    test('handleOfflineAuthenticated establishes context and cached summaries '
        'from a local snapshot when the session is expired, without touching '
        'the network', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 3, 25, 10),
      );
      remoteRepository.listSongsError = StateError('network unreachable');

      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () => null,
        organizationReader: () async =>
            throw StateError('must not be called offline'),
        sessionVerifier: () async =>
            throw StateError('must not be called offline'),
        lastKnownIdentityReader: () =>
            (userId: 'user-1', organizationId: 'org-1'),
      );

      controller.handleSessionExpired();
      await controller.handleOfflineAuthenticated();

      expect(
        controller.state.context,
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
      expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
      expect(controller.state.hasCachedCatalog, isTrue);
      expect(
        controller.state.connectionStatus,
        CatalogConnectionStatus.offlineCached,
      );
      expect(remoteRepository.listSongsCalls, 0);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        const [SongSummary(id: 'song-1', title: 'Cached Song')],
      );
    });

    test('handleOfflineAuthenticated is a no-op when no local snapshot exists '
        'for the last known identity', () async {
      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () => null,
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        lastKnownIdentityReader: () =>
            (userId: 'user-1', organizationId: 'org-1'),
      );

      controller.handleSessionExpired();
      await controller.handleOfflineAuthenticated();

      expect(controller.state.context, isNull);
      expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
      expect(controller.state.hasCachedCatalog, isFalse);
    });

    test('handleOfflineAuthenticated never clobbers an already-established '
        'context', () async {
      final controller = SongCatalogController(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        lastKnownIdentityReader: () =>
            (userId: 'user-1', organizationId: 'org-1'),
      );

      await controller.refreshCatalog();
      expect(controller.state.context, isNotNull);

      await controller.handleOfflineAuthenticated();

      expect(controller.state.sessionStatus, CatalogSessionStatus.verified);
      expect(
        controller.state.context,
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      );
    });
  });

  group('SongCatalogController implausible-empty snapshot handling (D4, '
      'local-data-durability-contract)', () {
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;
    late _ConfigurableSongRepository remoteRepository;
    late LocalDataLifecycle lifecycle;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
      remoteRepository = _ConfigurableSongRepository();
      lifecycle = LocalDataLifecycle(
        songCatalogStore: store,
        planningLocalStore: _NoopPlanningLocalStore(),
        identityStore: _NoopLastKnownIdentityStore(),
        noteLastKnownIdentity: (_) {},
        eventsRecorder: _NoopLocalDataEventsRecorder(),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('an empty listSongs response against a non-empty cached snapshot is '
        'rejected as implausible and leaves the cache untouched', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );
      remoteRepository.songs = const [];

      final controller = SongCatalogController(
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
      );

      await controller.refreshCatalog();

      expect(
        controller.state.refreshStatus,
        CatalogRefreshStatus.implausibleEmpty,
      );
      expect(controller.state.hasCachedCatalog, isTrue);
      expect(controller.state.connectionStatus, CatalogConnectionStatus.online);
      expect(controller.state.sessionStatus, CatalogSessionStatus.verified);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        const [SongSummary(id: 'song-1', title: 'Alpha')],
      );
    });

    test('invokes the implausible-empty callback with the refreshed identity '
        'on rejection', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );
      remoteRepository.songs = const [];
      final calls = <({String userId, String organizationId})>[];

      final controller = SongCatalogController(
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {
              calls.add((userId: userId, organizationId: organizationId));
            },
      );

      await controller.refreshCatalog();

      expect(calls, [(userId: 'user-1', organizationId: 'org-1')]);
    });

    test('a throwing implausible-empty callback does not prevent the refresh '
        'from completing', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );
      remoteRepository.songs = const [];

      final controller = SongCatalogController(
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {
              throw StateError('boom');
            },
      );

      await controller.refreshCatalog();

      expect(
        controller.state.refreshStatus,
        CatalogRefreshStatus.implausibleEmpty,
      );
    });

    test('two consecutive independent empty resolutions replace the cached '
        'snapshot with the empty result', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );
      remoteRepository.songs = const [];

      final controller = SongCatalogController(
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
      );

      await controller.refreshCatalog();
      expect(
        controller.state.refreshStatus,
        CatalogRefreshStatus.implausibleEmpty,
      );

      await controller.refreshCatalog();

      expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    });

    test('a genuinely empty catalog (never cached non-empty) refreshes '
        'normally on the very first response', () async {
      remoteRepository.songs = const [];

      final controller = SongCatalogController(
        store: store,
        localDataLifecycle: lifecycle,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {
              fail('must not be called when nothing non-empty is cached');
            },
      );

      await controller.refreshCatalog();

      expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
    });
  });
}

class _ConfigurableSongRepository implements SongRepository {
  List<SongSummary> songs = const [SongSummary(id: 'song-1', title: 'Alpha')];
  Map<String, SongSource> sources = const {
    'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
  };
  int listSongsCalls = 0;

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    return songs;
  }

  @override
  Future<SongSource> getSongSource(String id) async => sources[id]!;
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository()
    : _songs = const [
        SongSummary(id: 'song-1', title: 'Alpha'),
        SongSummary(id: 'song-2', title: 'Beta'),
      ],
      _sources = const {
        'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
        'song-2': SongSource(id: 'song-2', source: '{title: Beta}'),
      };

  final List<SongSummary> _songs;
  final Map<String, SongSource> _sources;

  int listSongsCalls = 0;
  Object? listSongsError;
  final Map<String, Object> sourceErrors = <String, Object>{};

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    final error = listSongsError;
    if (error != null) {
      throw error;
    }

    return _songs;
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final error = sourceErrors[id];
    if (error != null) {
      throw error;
    }

    return _sources[id]!;
  }
}

class _MutableOrganizationReader {
  _MutableOrganizationReader(String organizationId)
    : _organizationId = organizationId;

  String _organizationId;
  Object? nextError;

  Future<String?> read() async {
    final error = nextError;
    if (error != null) {
      throw error;
    }

    return _organizationId;
  }

  void setOrganizationId(String organizationId) {
    _organizationId = organizationId;
  }
}

class _DelayedSongRepository implements SongRepository {
  final Completer<void> listSongsStarted = Completer<void>();
  final Completer<List<SongSummary>> _songsCompleter =
      Completer<List<SongSummary>>();
  Map<String, SongSource> _sources = const {};
  int listSongsCalls = 0;

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    if (!listSongsStarted.isCompleted) {
      listSongsStarted.complete();
    }

    return _songsCompleter.future;
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final songs = await _songsCompleter.future;
    assert(songs.any((song) => song.id == id));
    return _sources[id]!;
  }

  void completeWith(List<SongSummary> songs, Map<String, SongSource> sources) {
    _sources = sources;
    if (!_songsCompleter.isCompleted) {
      _songsCompleter.complete(songs);
    }
  }

  void failWith(Object error) {
    if (!_songsCompleter.isCompleted) {
      _songsCompleter.completeError(error);
    }
  }
}

class _MultiPhaseSongRepository implements SongRepository {
  int listSongsCalls = 0;
  final List<Completer<List<SongSummary>>> _songRequests =
      <Completer<List<SongSummary>>>[];
  Map<String, SongSource> _sources = const {
    'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
  };

  @override
  Future<List<SongSummary>> listSongs() {
    listSongsCalls += 1;
    final completer = Completer<List<SongSummary>>();
    _songRequests.add(completer);
    return completer.future;
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    return _sources[id]!;
  }

  void completeRequest(
    int requestIndex, {
    List<SongSummary> songs = const [SongSummary(id: 'song-1', title: 'Alpha')],
    Map<String, SongSource> sources = const {
      'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
    },
  }) {
    _sources = sources;
    final completer = _songRequests[requestIndex];
    if (!completer.isCompleted) {
      completer.complete(songs);
    }
  }
}

// Trivial LocalDataLifecycle deps for tests that only exercise the song
// catalog purge path -- these are never called by SongCatalogController, so
// the noSuchMethod forwarding is unreachable in practice.
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

class _TestAppForegroundState implements AppForegroundState {
  _TestAppForegroundState({this._isForeground = true});

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isForeground;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> watchForeground() => _controller.stream;

  void setForeground(bool value) {
    _isForeground = value;
    _controller.add(value);
  }
}
