import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/planning/active_planning_context_controller.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

void main() {
  group('ActivePlanningContextController', () {
    late AppAuthSession? session;
    late String? organizationId;
    late String? latestCachedOrganizationId;
    late bool shouldThrowOnOrganizationRead;

    setUp(() {
      session = const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      );
      organizationId = 'org-1';
      latestCachedOrganizationId = null;
      shouldThrowOnOrganizationRead = false;
    });

    test(
      'resolves the signed-in active organization into planning context',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      'falls back to the latest cached organization when active organization lookup fails',
      () async {
        shouldThrowOnOrganizationRead = true;
        latestCachedOrganizationId = 'cached-org';
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh(allowCachedFallback: true);

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'cached-org',
          ),
        );
      },
    );

    test(
      'keeps the established planning boundary when connectivity lookup fails after a verified org was already selected',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh();
        shouldThrowOnOrganizationRead = true;
        latestCachedOrganizationId = 'cached-org';

        await controller.refresh(allowCachedFallback: true);

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      'does not reuse a cached organization for non-connectivity lookup failures',
      () async {
        latestCachedOrganizationId = 'cached-org';
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            throw StateError('membership lookup failed');
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh(allowCachedFallback: true);

        expect(controller.state, isNull);
      },
    );

    test(
      // D5.4/D5.5 (docs/specs/2026-08-19-local-data-durability-contract.md,
      // ADR-035 Phase 4): a verified-empty resolution no longer clears
      // _state by itself -- the controller now defers entirely to the
      // injected handler's reported outcome (in production,
      // VerifiedEmptyMembershipCleanupCoordinator, gated on two
      // confirmations through LocalDataLifecycle). The handler here
      // simulates a genuine purge having already run (returns true) so this
      // test keeps pinning the controller's OWN responsibility once told
      // that happened.
      'keeps cached fallback blocked after verified empty membership clears the planning boundary',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw const SocketException('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
          onVerifiedEmptyMembership: ({required userId}) async => true,
        );

        await controller.refresh();
        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        organizationId = null;
        await controller.refresh(allowCachedFallback: true);

        expect(controller.state, isNull);

        shouldThrowOnOrganizationRead = true;
        latestCachedOrganizationId = 'cached-org';

        await controller.refresh(allowCachedFallback: true);

        expect(controller.state, isNull);
      },
    );

    test(
      // Required test 9 (D5.4/D5.5, ADR-035 Phase 4): reads stay served
      // when nothing was purged -- ADR-020's read access is unchanged until
      // data is genuinely gone.
      'a verified empty membership resolution that does not purge (handler '
      'reports false, or no handler at all) leaves the planning context '
      'fully intact',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async => organizationId,
          latestOrganizationReader: ({required userId}) async =>
              latestCachedOrganizationId,
          onVerifiedEmptyMembership: ({required userId}) async => false,
        );

        await controller.refresh();
        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        organizationId = null;
        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      // RED 2 (final whole-branch review), mirroring SongCatalogController's
      // RED 1 fix: empty -> fresh non-empty -> empty must be two
      // independent first confirmations, not a confirmation plus a purge.
      'a genuine fresh non-empty resolution between two empties clears the '
      'membership-revocation marker so the trailing empty is a first '
      'confirmation again, not a purge',
      () async {
        final identityDatabase = LastKnownIdentityDatabase.inMemory();
        addTearDown(identityDatabase.close);
        final identityStore = DriftLastKnownIdentityStore(identityDatabase);
        final gatedLifecycle = LocalDataLifecycle(
          songCatalogStore: _FakeSongCatalogStore(),
          planningLocalStore: _FakePlanningLocalStore(),
          identityStore: identityStore,
          noteLastKnownIdentity: (_) {},
          eventsRecorder: const _NoopLocalDataEventsRecorder(),
          membershipConfirmationCooldown: Duration.zero,
        );
        await identityStore.write(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'demo@lyron.local',
            organizationId: 'org-1',
          ),
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

        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async => organizationIds[callIndex++],
          latestOrganizationReader: ({required userId}) async =>
              latestCachedOrganizationId,
          onVerifiedEmptyMembership: handleVerifiedEmptyMembership,
          onVerifiedNonEmptyMembership: ({required userId}) =>
              gatedLifecycle.clearMembershipRevocation(userId: userId),
        );

        // T0: verified empty -> marker set.
        await controller.refresh();
        // T0+30s: a genuine, fresh, non-empty resolution -- must clear the
        // marker.
        await controller.refresh();
        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
        // T0+90s: verified empty again. If the marker was correctly
        // cleared above, this is a first confirmation again -- nothing may
        // be purged, so the planning boundary set just above must survive.
        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          reason:
              'the genuine non-empty resolution between the two empties '
              'must have cleared the marker, so the second empty is a '
              'first confirmation again -- nothing should have been '
              'purged',
        );
      },
    );

    test(
      // YELLOW 5 (final whole-branch review): the purge gate call must sit
      // OUTSIDE the organization-lookup try/catch -- a throw from the
      // handler must propagate, not be swallowed and misclassified as an
      // organization-lookup failure (which would silently clear or keep the
      // planning context instead).
      'a throwing verified-empty-membership handler propagates instead of '
      'being swallowed as an organization-lookup failure',
      () async {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async => null,
          latestOrganizationReader: ({required userId}) async =>
              latestCachedOrganizationId,
          onVerifiedEmptyMembership: ({required userId}) async {
            throw StateError('purge gate exploded');
          },
        );

        await expectLater(
          () => controller.refresh(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      // YELLOW 6 (final whole-branch review, D5.5 rule 4): `session` is
      // captured before the awaited organization lookup and must be
      // re-read and compared before the purge gate runs, so a resolution
      // captured under user A cannot purge user B's data after B signs in
      // during the await.
      'does not enter the purge gate when a different user signed in while '
      'the organization lookup was in flight',
      () async {
        var handlerCalls = 0;
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            // Simulate a different user signing in during this await --
            // exactly the race the currentness re-check must catch.
            session = const AppAuthSession(
              userId: 'user-2',
              email: 'other@lyron.local',
            );
            return null;
          },
          latestOrganizationReader: ({required userId}) async =>
              latestCachedOrganizationId,
          onVerifiedEmptyMembership: ({required userId}) async {
            handlerCalls++;
            return false;
          },
        );

        await controller.refresh();

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

    test('clears state when no signed-in session is available', () async {
      final controller = ActivePlanningContextController(
        authSessionReader: () => session,
        organizationReader: () async => organizationId,
        latestOrganizationReader: ({required userId}) async {
          return latestCachedOrganizationId;
        },
      );
      await controller.refresh();
      session = null;

      await controller.refresh();

      expect(controller.state, isNull);
    });

    test(
      'keeps the established context when a later organization lookup fails',
      () async {
        latestCachedOrganizationId = 'cached-org';
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async {
            if (shouldThrowOnOrganizationRead) {
              throw StateError('offline');
            }
            return organizationId;
          },
          latestOrganizationReader: ({required userId}) async {
            expect(userId, 'user-1');
            return latestCachedOrganizationId;
          },
        );

        await controller.refresh();
        shouldThrowOnOrganizationRead = true;

        await controller.refresh();

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
      },
    );

    test(
      'adopts active organization changes from the catalog context signal',
      () {
        final controller = ActivePlanningContextController(
          authSessionReader: () => session,
          organizationReader: () async => organizationId,
          latestOrganizationReader: ({required userId}) async {
            return latestCachedOrganizationId;
          },
        );

        controller.syncToCatalogContext(
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2'),
        );

        expect(
          controller.state,
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
        );
      },
    );
  });
}

// Minimal fakes for LocalDataLifecycle's non-identity dependencies -- these
// tests only exercise the membership-revocation marker on the real,
// Drift-backed identity store, so the two data stores just need to not
// throw if a purge genuinely runs (the RED 2 test's whole point is that,
// once fixed, the trailing empty resolution must NOT reach them at all).
class _FakeSongCatalogStore implements SongCatalogStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> deleteCatalogsForUser({required String userId}) async {}
}

class _FakePlanningLocalStore implements PlanningLocalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {}
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  const _NoopLocalDataEventsRecorder();

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
}
