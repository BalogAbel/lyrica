import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/planning_providers.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

void main() {
  group('VerifiedEmptyMembershipCleanupCoordinator', () {
    late LastKnownIdentityDatabase identityDatabase;
    late LocalDataLifecycle lifecycle;
    late VerifiedEmptyMembershipCleanupCoordinator coordinator;

    setUp(() async {
      identityDatabase = LastKnownIdentityDatabase.inMemory();
      final identityStore = DriftLastKnownIdentityStore(identityDatabase);
      lifecycle = LocalDataLifecycle(
        songCatalogStore: _NoopSongCatalogStore(),
        planningLocalStore: _NoopPlanningLocalStore(),
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
      coordinator = VerifiedEmptyMembershipCleanupCoordinator(
        localDataLifecycle: lifecycle,
        countPendingWork: ({required userId}) async => 0,
        requestConfirmation: ({required pendingCount}) async =>
            ReauthPromptResult.confirmed,
        invalidateLastKnownIdentityPersistence: () async {},
      );
    });

    tearDown(() async {
      await identityDatabase.close();
    });

    Future<void> driveToConfirmedPurge() async {
      // First (marker-only) resolution.
      await coordinator.handleVerifiedEmptyMembership(userId: 'user-1');
      // Second, cooldown-separated (cooldown is zeroed above) resolution --
      // this is the one that authorizes and runs the purge.
    }

    test(
      // YELLOW 8 (final whole-branch review): `for (final handler in
      // _handlers)` iterates the LIVE Set across awaits. A handler that
      // removes another handler mid-iteration (e.g. a provider disposing
      // while the purge is committing) must not throw
      // ConcurrentModificationError out of this fire-and-forget listener
      // after the purge already committed -- and the removed handler
      // should still run, since it was registered when the purge started.
      'a handler that removes another handler mid-iteration does not throw '
      'ConcurrentModificationError, and the snapshot handler still runs',
      () async {
        var secondHandlerCalls = 0;
        Future<void> secondHandler({required String userId}) async {
          secondHandlerCalls += 1;
        }

        Future<void> firstHandler({required String userId}) async {
          coordinator.removeHandler(secondHandler);
        }

        coordinator.addHandler(firstHandler);
        coordinator.addHandler(secondHandler);

        await driveToConfirmedPurge();

        final purged = await coordinator.handleVerifiedEmptyMembership(
          userId: 'user-1',
        );

        expect(purged, isTrue);
        expect(
          secondHandlerCalls,
          1,
          reason:
              'the handler removed mid-iteration was still part of the '
              'snapshot taken when the purge started, so it must still run '
              'exactly once',
        );
      },
    );
  });
}

class _NoopSongCatalogStore implements SongCatalogStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> deleteCatalogsForUser({required String userId}) async {}
}

class _NoopPlanningLocalStore implements PlanningLocalStore {
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

  @override
  Future<void> recordMembershipRevocationPurgeDeclined({
    required String userId,
    required MembershipRevocationPurgeDeclineReason reason,
  }) async {}
}
