import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

void main() {
  late _RecordingSongCatalogStore songCatalogStore;
  late _RecordingPlanningLocalStore planningLocalStore;
  late _RecordingLastKnownIdentityStore identityStore;
  late _RecordingLocalDataEventsRecorder eventsRecorder;
  late List<LastKnownIdentity?> notedIdentities;
  late LocalDataLifecycle lifecycle;

  setUp(() {
    songCatalogStore = _RecordingSongCatalogStore();
    planningLocalStore = _RecordingPlanningLocalStore();
    identityStore = _RecordingLastKnownIdentityStore();
    eventsRecorder = _RecordingLocalDataEventsRecorder();
    notedIdentities = <LastKnownIdentity?>[];
    lifecycle = LocalDataLifecycle(
      songCatalogStore: songCatalogStore,
      planningLocalStore: planningLocalStore,
      identityStore: identityStore,
      noteLastKnownIdentity: notedIdentities.add,
      eventsRecorder: eventsRecorder,
    );
  });

  group('purgeSongCatalog', () {
    test(
      'deletes for the userId then records exactly one audit event',
      () async {
        await lifecycle.purgeSongCatalog(
          userId: 'user-1',
          reason: PurgeReason.userSignOut,
        );

        expect(songCatalogStore.deleteCalls, ['user-1']);
        expect(eventsRecorder.purgeCalls, hasLength(1));
        final recorded = eventsRecorder.purgeCalls.single;
        expect(recorded.target, PurgeTarget.songCatalog);
        expect(recorded.reason, PurgeReason.userSignOut);
        expect(recorded.userId, 'user-1');
        expect(recorded.rowsAffected, isNull);
      },
    );

    test('when the store throws, the exception propagates and no audit event '
        'is recorded', () async {
      songCatalogStore.throwOnDelete = true;

      await expectLater(
        () => lifecycle.purgeSongCatalog(
          userId: 'user-1',
          reason: PurgeReason.accountDeleted,
        ),
        throwsA(isA<StateError>()),
      );

      expect(eventsRecorder.purgeCalls, isEmpty);
    });

    test('when the audit recorder throws, the deletion that already committed '
        'is NOT reported as a failure -- the method completes without '
        'throwing', () async {
      eventsRecorder.throwOnRecord = true;

      await lifecycle.purgeSongCatalog(
        userId: 'user-1',
        reason: PurgeReason.userSignOut,
      );

      expect(songCatalogStore.deleteCalls, ['user-1']);
    });
  });

  group('purgePlanningData', () {
    test('deletes for the userId (passing shouldContinue through) then records '
        'exactly one audit event', () async {
      bool shouldContinue() => true;

      await lifecycle.purgePlanningData(
        userId: 'user-2',
        reason: PurgeReason.differentUserSignIn,
        shouldContinue: shouldContinue,
      );

      expect(planningLocalStore.deleteCalls, hasLength(1));
      expect(planningLocalStore.deleteCalls.single.userId, 'user-2');
      expect(
        planningLocalStore.deleteCalls.single.shouldContinue,
        same(shouldContinue),
      );
      expect(eventsRecorder.purgeCalls, hasLength(1));
      final recorded = eventsRecorder.purgeCalls.single;
      expect(recorded.target, PurgeTarget.planningData);
      expect(recorded.reason, PurgeReason.differentUserSignIn);
      expect(recorded.userId, 'user-2');
      expect(recorded.rowsAffected, isNull);
    });

    test('when the store throws, the exception propagates and no audit event '
        'is recorded', () async {
      planningLocalStore.throwOnDelete = true;

      await expectLater(
        () => lifecycle.purgePlanningData(
          userId: 'user-2',
          reason: PurgeReason.membershipRevokedConfirmed,
        ),
        throwsA(isA<StateError>()),
      );

      expect(eventsRecorder.purgeCalls, isEmpty);
    });

    test('a PlanningProjectionAbortedException from the store propagates '
        'unchanged and uncaught', () async {
      planningLocalStore.abortOnDelete = true;

      await expectLater(
        () => lifecycle.purgePlanningData(
          userId: 'user-2',
          reason: PurgeReason.userSignOut,
        ),
        throwsA(isA<PlanningProjectionAbortedException>()),
      );

      expect(eventsRecorder.purgeCalls, isEmpty);
    });

    test('when the audit recorder throws, the deletion that already committed '
        'is NOT reported as a failure -- the method completes without '
        'throwing', () async {
      eventsRecorder.throwOnRecord = true;

      await lifecycle.purgePlanningData(
        userId: 'user-2',
        reason: PurgeReason.userSignOut,
      );

      expect(planningLocalStore.deleteCalls, hasLength(1));
    });
  });

  group('clearIdentity', () {
    test('clears, notes null, and records the caller-supplied userId on the '
        'audit row -- no internal identity read', () async {
      await lifecycle.clearIdentity(
        reason: PurgeReason.accountDeleted,
        userId: 'user-3',
      );

      expect(identityStore.callLog, ['clear']);
      expect(notedIdentities, [null]);
      expect(eventsRecorder.purgeCalls, hasLength(1));
      final recorded = eventsRecorder.purgeCalls.single;
      expect(recorded.target, PurgeTarget.identity);
      expect(recorded.reason, PurgeReason.accountDeleted);
      expect(recorded.userId, 'user-3');
      expect(recorded.rowsAffected, isNull);
    });

    test('when the caller has no userId to supply, records a null userId '
        '(does not read the identity store to derive one)', () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-3',
          email: 'user3@example.com',
          organizationId: 'org-3',
        ),
      );

      await lifecycle.clearIdentity(reason: PurgeReason.userSignOut);

      expect(identityStore.callLog, ['clear']);
      expect(eventsRecorder.purgeCalls, hasLength(1));
      expect(eventsRecorder.purgeCalls.single.userId, isNull);
    });

    test('when clear throws, the exception propagates and neither note nor '
        'record happen', () async {
      identityStore.throwOnClear = true;

      await expectLater(
        () => lifecycle.clearIdentity(
          reason: PurgeReason.membershipRevokedConfirmed,
          userId: 'user-4',
        ),
        throwsA(isA<StateError>()),
      );

      expect(identityStore.callLog, ['clear']);
      expect(notedIdentities, isEmpty);
      expect(eventsRecorder.purgeCalls, isEmpty);
    });

    test('when the audit recorder throws, the clear and the note already '
        'committed are NOT undone or reported as a failure -- the method '
        'completes without throwing', () async {
      eventsRecorder.throwOnRecord = true;

      await lifecycle.clearIdentity(
        reason: PurgeReason.userSignOut,
        userId: 'user-5',
      );

      expect(identityStore.callLog, ['clear']);
      expect(notedIdentities, [null]);
    });
  });

  group('writeIdentity', () {
    test('writes then notes, without writing any audit record', () async {
      const identity = LastKnownIdentity(
        userId: 'user-5',
        email: 'e5@x',
        organizationId: 'org-5',
      );

      await lifecycle.writeIdentity(identity);

      expect(identityStore.callLog, ['write']);
      expect(identityStore.writes, [identity]);
      expect(notedIdentities, [identity]);
      expect(eventsRecorder.purgeCalls, isEmpty);
    });
  });

  test('every PurgeReason value works through a destructive method', () async {
    for (final reason in PurgeReason.values) {
      eventsRecorder.purgeCalls.clear();
      await lifecycle.purgeSongCatalog(userId: 'user-x', reason: reason);
      expect(eventsRecorder.purgeCalls.single.reason, reason);
    }
  });

  group('clearMembershipRevocation (Task 4.3)', () {
    test(
      'a quarantined identity has its marker cleared, the write notes the '
      'controller cache, and a clear audit event is recorded',
      () async {
        identityStore.seed(
          LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
            membershipRevokedAt: DateTime.utc(2026, 8, 1),
          ),
        );

        await lifecycle.clearMembershipRevocation(userId: 'user-1');

        expect(identityStore.writes, hasLength(1));
        final written = identityStore.writes.single;
        expect(written.userId, 'user-1');
        expect(written.email, 'user1@example.com');
        expect(written.organizationId, 'org-1');
        expect(written.membershipRevokedAt, isNull);
        expect(notedIdentities, [written]);

        expect(eventsRecorder.quarantineCalls, hasLength(1));
        final recorded = eventsRecorder.quarantineCalls.single;
        expect(recorded.target, PurgeTarget.identity);
        expect(recorded.reason, 'membershipRevokedCleared');
        expect(recorded.userId, 'user-1');
      },
    );

    test(
      'an identity whose marker is already null is a no-op -- no write, no '
      'audit event',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );

        await lifecycle.clearMembershipRevocation(userId: 'user-1');

        expect(identityStore.writes, isEmpty);
        expect(notedIdentities, isEmpty);
        expect(eventsRecorder.quarantineCalls, isEmpty);
      },
    );

    test('no identity row at all is a no-op', () async {
      await lifecycle.clearMembershipRevocation(userId: 'user-1');

      expect(identityStore.writes, isEmpty);
      expect(eventsRecorder.quarantineCalls, isEmpty);
    });

    test(
      "a different user's identity row is left untouched (defensive) -- a "
      'mismatched row is treated as nothing to clear',
      () async {
        identityStore.seed(
          LastKnownIdentity(
            userId: 'someone-else',
            email: 'someone-else@example.com',
            organizationId: 'org-9',
            membershipRevokedAt: DateTime.utc(2026, 8, 1),
          ),
        );

        await lifecycle.clearMembershipRevocation(userId: 'user-1');

        expect(identityStore.writes, isEmpty);
        expect(eventsRecorder.quarantineCalls, isEmpty);
      },
    );
  });

  group('recordMembershipRevocationCleared (Task 4.3)', () {
    test(
      'records the clear audit event without touching the identity store',
      () async {
        await lifecycle.recordMembershipRevocationCleared(userId: 'user-1');

        expect(identityStore.callLog, isEmpty);
        expect(identityStore.writes, isEmpty);
        expect(notedIdentities, isEmpty);
        expect(eventsRecorder.quarantineCalls, hasLength(1));
        final recorded = eventsRecorder.quarantineCalls.single;
        expect(recorded.target, PurgeTarget.identity);
        expect(recorded.reason, 'membershipRevokedCleared');
        expect(recorded.userId, 'user-1');
      },
    );

    test(
      'when the audit recorder throws, the failure is swallowed '
      '(best-effort) -- the method completes without throwing',
      () async {
        eventsRecorder.throwOnQuarantineRecord = true;

        await lifecycle.recordMembershipRevocationCleared(userId: 'user-1');
      },
    );
  });

  group(
    'clearMembershipRevocation serializes against other identity mutations '
    'for the same userId (review fix, Task 4.3)',
    () {
      test(
        'a clearMembershipRevocation call issued while a second-resolution '
        'confirmed purge is in flight for the same userId waits for the '
        'purge and does NOT resurrect the row it just deleted',
        () async {
          identityStore.seed(
            LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
              membershipRevokedAt: DateTime.utc(2026, 8, 1),
            ),
          );
          final pendingCount = Completer<int?>();

          // Second, independent verified-empty resolution: matchesCaller is
          // true and a marker is already present, so this takes the
          // confirmed-purge branch -- blocked on countPendingWork, i.e.
          // genuinely in flight and still holding user-1's mutation slot.
          final resolveFuture = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: () => pendingCount.future,
            requestConfirmation: _neverCalledRequestConfirmation,
          );

          // Issued while the purge above is still blocked -- before the
          // fix, this would race straight to its own read (seeing the
          // still-quarantined row) instead of waiting its turn.
          final clearFuture = lifecycle.clearMembershipRevocation(
            userId: 'user-1',
          );

          pendingCount.complete(0); // zero pending work -> purges directly

          expect(
            await resolveFuture,
            MembershipRevocationResolution.purgedConfirmed,
          );
          await clearFuture;

          // The purge's clearIdentity() ran, and clearMembershipRevocation
          // -- having waited its turn -- found nothing left to clear: no
          // resurrecting write, and the row is still gone.
          expect(identityStore.writes, isEmpty);
          expect(await identityStore.read(), isNull);
        },
      );

      test(
        'a writeIdentity call issued right after clearMembershipRevocation '
        'for the same userId waits for the clear to finish, so the newer '
        "write's data is never clobbered by the clear's stale read",
        () async {
          identityStore.seed(
            LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
              membershipRevokedAt: DateTime.utc(2026, 8, 1),
            ),
          );
          identityStore.blockNextRead();

          final clearFuture = lifecycle.clearMembershipRevocation(
            userId: 'user-1',
          );
          // Confirm the clear is genuinely parked inside its own read, not
          // merely about to run it, before issuing the concurrent write.
          await identityStore.readStarted;

          final writeFuture = lifecycle.writeIdentity(
            const LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-2',
              membershipRevokedAt: null,
            ),
          );

          // The write must not have run yet: it is queued behind the
          // still-blocked clear for the SAME userId.
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          expect(identityStore.writes, isEmpty);

          identityStore.releaseRead();
          await clearFuture;
          await writeFuture;

          // clearMembershipRevocation's own (now-stale-by-comparison) write
          // landed first, then writeIdentity's fresher intent landed
          // second and is what the store ends up holding -- the newer
          // write was not clobbered by the clear's stale read.
          expect(identityStore.writes, hasLength(2));
          expect(identityStore.writes[0].organizationId, 'org-1');
          expect(identityStore.writes[0].membershipRevokedAt, isNull);
          expect(identityStore.writes[1].organizationId, 'org-2');
          final finalIdentity = await identityStore.read();
          expect(finalIdentity?.organizationId, 'org-2');
          expect(finalIdentity?.membershipRevokedAt, isNull);
        },
      );

      test(
        'a clearIdentity(userId: ...) call issued while a '
        'clearMembershipRevocation read is still in flight for the same '
        'userId waits its turn instead of clearing out of order (review '
        'fix, clearIdentity was the one mutator left unguarded)',
        () async {
          identityStore.seed(
            LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
              membershipRevokedAt: DateTime.utc(2026, 8, 1),
            ),
          );
          identityStore.blockNextRead();

          final clearMarkerFuture = lifecycle.clearMembershipRevocation(
            userId: 'user-1',
          );
          await identityStore.readStarted;

          // Issued while clearMembershipRevocation's read is still blocked
          // -- before this fix, clearIdentity did not read at all and
          // would have run its clear() immediately, ahead of the
          // in-flight read/write pair above.
          final clearIdentityFuture = lifecycle.clearIdentity(
            reason: PurgeReason.differentUserSignIn,
            userId: 'user-1',
          );

          // Nothing has happened against the store yet: both calls are
          // queued behind the still-blocked read.
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          expect(identityStore.callLog, isEmpty);

          identityStore.releaseRead();
          await clearMarkerFuture;
          await clearIdentityFuture;

          // Strict order: clearMembershipRevocation's read then write ran
          // to completion FIRST, and only then did clearIdentity's clear()
          // run -- never interleaved, never reordered ahead of them.
          expect(identityStore.callLog, ['read', 'write', 'clear']);
          expect(await identityStore.read(), isNull);
        },
      );

      test(
        "resolveVerifiedEmptyMembership's confirmed-purge branch (which "
        'calls the internal, unlocked clearIdentity variant while still '
        "holding this userId's mutation slot) completes without "
        'self-deadlocking',
        () async {
          identityStore.seed(
            const LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
            ),
          );
          final first = await lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );
          expect(first, MembershipRevocationResolution.quarantined);

          // Second, independent resolution -> confirmed-purge branch,
          // which internally calls _clearIdentityUnlocked from inside the
          // slot this very call already holds. A regression back to the
          // public, slot-acquiring clearIdentity here would hang forever
          // instead of completing -- flutter_test's default test timeout
          // would fail this test if that happened, so completing at all is
          // the assertion that matters, tightened with an explicit short
          // timeout for a fast, clear failure instead of a 30s hang.
          final second = await lifecycle
              .resolveVerifiedEmptyMembership(
                userId: 'user-1',
                email: 'user1@example.com',
                countPendingWork: () async => 0,
                requestConfirmation: _neverCalledRequestConfirmation,
              )
              .timeout(const Duration(seconds: 5));

          expect(second, MembershipRevocationResolution.purgedConfirmed);
          expect(identityStore.callLog, contains('clear'));
        },
      );
    },
  );

  group('resolveVerifiedEmptyMembership (D5, Task 4.1)', () {
    test(
      'first resolution quarantines: sets membershipRevokedAt, records a '
      'quarantine event, and deletes nothing',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );

        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        expect(identityStore.writes, hasLength(1));
        final written = identityStore.writes.single;
        expect(written.userId, 'user-1');
        expect(written.email, 'user1@example.com');
        expect(written.organizationId, 'org-1');
        expect(written.membershipRevokedAt, isNotNull);
        expect(notedIdentities, [written]);

        expect(eventsRecorder.quarantineCalls, hasLength(1));
        final recorded = eventsRecorder.quarantineCalls.single;
        expect(recorded.target, PurgeTarget.identity);
        expect(recorded.reason, 'membershipRevokedFirstResolution');
        expect(recorded.userId, 'user-1');

        // Deletes nothing (D5's core guarantee).
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.callLog, isNot(contains('clear')));
      },
    );

    test(
      // Guardrail: the purge must be impossible to reach with one
      // confirmation, regardless of pending-work state. Even though a
      // *second* resolution with zero pending work purges outright (see the
      // Task 4.2 group below), a *single* resolution never does -- it always
      // quarantines and never even asks `countPendingWork`.
      'a single verified-empty resolution never purges even when pending '
      'work is (hypothetically) zero -- one confirmation is never enough',
      () async {
        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.callLog, isNot(contains('clear')));
      },
    );

    test(
      'a mismatched stored identity (different userId) is treated as no '
      'prior marker -- defensive branch -- and the new row gets the '
      "caller's own passed-in email, never the mismatched row's email",
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'someone-else',
            email: 'someone-else@example.com',
            organizationId: 'org-9',
            membershipRevokedAt: null,
          ),
        );

        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        expect(identityStore.writes, hasLength(1));
        // The bug this guards against: durably attaching the OTHER
        // (mismatched) user's real email to the new row for `userId`.
        expect(identityStore.writes.single.email, 'user1@example.com');
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
      },
    );

    test(
      'no prior identity row at all (fresh device / first-ever sign-in) '
      "writes the caller's passed-in email, not a blank one",
      () async {
        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        expect(identityStore.writes, hasLength(1));
        final written = identityStore.writes.single;
        expect(written.userId, 'user-1');
        expect(written.email, 'user1@example.com');
        expect(written.organizationId, isNull);
        expect(written.membershipRevokedAt, isNotNull);
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
      },
    );

    test(
      'when the audit recorder throws, the marker write already committed '
      'is NOT reported as a failure -- the method completes and still '
      'returns quarantined',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        eventsRecorder.throwOnQuarantineRecord = true;

        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        expect(identityStore.writes, hasLength(1));
      },
    );
  });

  group('resolveVerifiedEmptyMembership: confirmed purge (D5, Task 4.2)', () {
    test(
      'two consecutive fresh online empty resolutions with no pending work '
      'purge via membershipRevokedConfirmed and write the audit row '
      '(Acceptance 5)',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );

        final first = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );
        expect(first, MembershipRevocationResolution.quarantined);

        var countCalls = 0;
        final second = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: () async {
            countCalls++;
            return 0;
          },
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(second, MembershipRevocationResolution.purgedConfirmed);
        expect(countCalls, 1);
        expect(songCatalogStore.deleteCalls, ['user-1']);
        expect(planningLocalStore.deleteCalls, hasLength(1));
        expect(planningLocalStore.deleteCalls.single.userId, 'user-1');
        expect(identityStore.callLog, contains('clear'));

        final purgeReasons = eventsRecorder.purgeCalls
            .map((call) => call.reason)
            .toSet();
        expect(purgeReasons, {PurgeReason.membershipRevokedConfirmed});
        final purgeTargets = eventsRecorder.purgeCalls
            .map((call) => call.target)
            .toSet();
        expect(purgeTargets, {
          PurgeTarget.songCatalog,
          PurgeTarget.planningData,
          PurgeTarget.identity,
        });
        for (final call in eventsRecorder.purgeCalls) {
          expect(call.userId, 'user-1');
        }
      },
    );

    test(
      'pending work present on the second resolution waits for user '
      'confirmation instead of purging outright (Acceptance 5)',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        var confirmationRequested = false;
        int? seenPendingCount;
        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: () async => 3,
          requestConfirmation: (pendingCount) async {
            confirmationRequested = true;
            seenPendingCount = pendingCount;
            return false;
          },
        );

        expect(confirmationRequested, isTrue);
        expect(seenPendingCount, 3);
        expect(result, MembershipRevocationResolution.confirmationDeclined);
        // Nothing destroyed while awaiting/declining confirmation.
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.callLog, isNot(contains('clear')));
      },
    );

    test(
      'a confirmed answer after nonzero pending work runs the same purge '
      'triple as the zero-pending path',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: () async => 2,
          requestConfirmation: (pendingCount) async => true,
        );

        expect(result, MembershipRevocationResolution.purgedConfirmed);
        expect(songCatalogStore.deleteCalls, ['user-1']);
        expect(planningLocalStore.deleteCalls, hasLength(1));
        expect(identityStore.callLog, contains('clear'));
      },
    );

    test(
      // D5: an unreadable pending count (null) must be treated exactly like
      // a nonzero one -- it asks for confirmation, never treated as "safe
      // to skip".
      'an unreadable pending count (null) on the second resolution requests '
      'confirmation rather than purging outright',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        var confirmationRequested = false;
        int? seenPendingCount = -1; // sentinel, overwritten if called
        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: () async => null,
          requestConfirmation: (pendingCount) async {
            confirmationRequested = true;
            seenPendingCount = pendingCount;
            return false;
          },
        );

        expect(confirmationRequested, isTrue);
        expect(seenPendingCount, isNull);
        expect(result, MembershipRevocationResolution.confirmationDeclined);
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(identityStore.callLog, isNot(contains('clear')));
      },
    );

    test(
      // Guardrail: the second-resolution detection must come from the
      // persisted marker, not from any in-memory state held by the
      // LocalDataLifecycle instance itself -- simulated here by resolving
      // the first call through one LocalDataLifecycle instance and the
      // second through a brand new one, both wired to the SAME underlying
      // stores (standing in for "same on-disk database after a process
      // restart").
      'a second resolution reaching the gate after a simulated store '
      'reopen (fresh LocalDataLifecycle instance, same underlying stores) '
      'still detects the persisted marker and completes the purge',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );

        final first = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );
        expect(first, MembershipRevocationResolution.quarantined);

        // A fresh instance -- no in-memory state carried over -- wired to
        // the exact same store doubles, standing in for "the app restarted
        // and reopened the same on-disk database".
        final reopenedLifecycle = LocalDataLifecycle(
          songCatalogStore: songCatalogStore,
          planningLocalStore: planningLocalStore,
          identityStore: identityStore,
          noteLastKnownIdentity: notedIdentities.add,
          eventsRecorder: eventsRecorder,
        );

        final second = await reopenedLifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: () async => 0,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(second, MembershipRevocationResolution.purgedConfirmed);
        expect(songCatalogStore.deleteCalls, ['user-1']);
        expect(identityStore.callLog, contains('clear'));
      },
    );

    test(
      // Guardrail: a differentUserSignIn between the two resolutions fully
      // clears the identity row (existing, untouched behaviour) -- the
      // NEXT verified-empty resolution, now for a genuinely different
      // situation, must look like a fresh first resolution, never
      // accidentally count as the original user's second confirmation.
      'a differentUserSignIn clearing the identity row between two '
      "resolutions resets the gate -- the next user's resolution is a "
      'fresh first resolution, not a second confirmation',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        final first = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );
        expect(first, MembershipRevocationResolution.quarantined);

        // A different user signs in: the real flow clears the row via
        // LocalDataLifecycle.clearIdentity(reason: differentUserSignIn)
        // before ever writing the new user's identity.
        await lifecycle.clearIdentity(
          reason: PurgeReason.differentUserSignIn,
          userId: 'user-1',
        );

        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-2',
          email: 'user2@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        // Still nothing purged for user-2 -- this was its first
        // resolution, not a second confirmation carried over from user-1.
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
      },
    );

    test(
      'a differentUserSignIn clear followed by the SAME user resolving '
      'verified-empty again also starts over as a fresh first resolution',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'user-1',
            email: 'user1@example.com',
            organizationId: 'org-1',
          ),
        );
        await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        await lifecycle.clearIdentity(
          reason: PurgeReason.differentUserSignIn,
          userId: 'user-1',
        );

        final result = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'user-1',
          email: 'user1@example.com',
          countPendingWork: _neverCalledCountPendingWork,
          requestConfirmation: _neverCalledRequestConfirmation,
        );

        expect(result, MembershipRevocationResolution.quarantined);
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
      },
    );
  });

  group(
    'resolveVerifiedEmptyMembership: concurrent-caller coalescing '
    '(follow-up fix, post-6853b08 review)',
    () {
      test(
        // Bug: auth_providers.dart's persistIdentity AND
        // VerifiedEmptyMembershipCleanupCoordinator (reached from BOTH
        // SongCatalogController and ActivePlanningContextController) can
        // all call resolveVerifiedEmptyMembership for the SAME userId on
        // the SAME signedIn transition, with no serialization between them.
        // Without coalescing, two calls that both read the identity row
        // before either has written its marker both take the
        // first-resolution branch and both write -- one real event
        // producing two writes.
        'two concurrent calls for the same userId coalesce: only one '
        'marker write happens and both callers see the same result',
        () async {
          identityStore.seed(
            const LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
            ),
          );

          final first = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );
          final second = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );

          // Coalescing means the second caller is handed the exact same
          // Future as the first, not a second independent execution.
          expect(identical(first, second), isTrue);

          final results = await Future.wait([first, second]);
          expect(results, [
            MembershipRevocationResolution.quarantined,
            MembershipRevocationResolution.quarantined,
          ]);
          expect(identityStore.writes, hasLength(1));
          expect(eventsRecorder.quarantineCalls, hasLength(1));
        },
      );

      test(
        'concurrent calls at the confirmation-needed second-resolution '
        'stage invoke requestConfirmation exactly once, never twice -- '
        'this is what would otherwise throw ReauthPromptController\'s '
        '"already pending" StateError',
        () async {
          identityStore.seed(
            LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
              membershipRevokedAt: DateTime.utc(2026, 8, 20),
            ),
          );
          var confirmationCalls = 0;
          Future<bool> requestConfirmation(int? pendingCount) async {
            confirmationCalls++;
            return true;
          }

          final first = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: () async => 2,
            requestConfirmation: requestConfirmation,
          );
          final second = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: () async => 2,
            requestConfirmation: requestConfirmation,
          );

          final results = await Future.wait([first, second]);

          expect(confirmationCalls, 1);
          expect(results, [
            MembershipRevocationResolution.purgedConfirmed,
            MembershipRevocationResolution.purgedConfirmed,
          ]);
        },
      );

      test(
        // Verifies the StateError risk against the REAL
        // ReauthPromptController, not just a stub -- proves the
        // "at most one prompt pending" invariant is never hit by
        // concurrent callers of this gate.
        'a real ReauthPromptController used as requestConfirmation across '
        'concurrent calls for the same userId never throws',
        () async {
          identityStore.seed(
            LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
              membershipRevokedAt: DateTime.utc(2026, 8, 20),
            ),
          );
          final promptController = ReauthPromptController();
          Future<bool> requestConfirmation(int? pendingCount) async {
            final result = await promptController
                .requestMembershipQuarantinePurgeConfirmation(
                  userId: 'user-1',
                  pendingCount: pendingCount,
                );
            return result == ReauthPromptResult.confirmed;
          }

          final first = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: () async => 2,
            requestConfirmation: requestConfirmation,
          );
          final second = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: () async => 2,
            requestConfirmation: requestConfirmation,
          );

          await Future<void>.delayed(Duration.zero);
          expect(promptController.pending, isNotNull);
          promptController.answer(
            true,
            requestId: promptController.pending!.requestId,
          );

          final results = await Future.wait([first, second]);
          expect(results, [
            MembershipRevocationResolution.purgedConfirmed,
            MembershipRevocationResolution.purgedConfirmed,
          ]);
        },
      );

      test(
        // Coalescing must not become permanent queueing/memoization: once
        // the in-flight execution completes, a LATER, genuinely separate
        // call must run its own fresh pass against the now-current marker.
        'after a coalesced pair completes, a later independent call for '
        'the same userId runs its own fresh execution (not blocked or '
        'memoized) and correctly sees the second resolution',
        () async {
          identityStore.seed(
            const LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
            ),
          );

          final first = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );
          final second = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );
          await Future.wait([first, second]);

          final third = await lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: () async => 0,
            requestConfirmation: _neverCalledRequestConfirmation,
          );

          expect(third, MembershipRevocationResolution.purgedConfirmed);
          expect(songCatalogStore.deleteCalls, ['user-1']);
        },
      );

      test(
        // The in-flight map entry's cleanup runs via an unawaited
        // `resolution.whenComplete(...)` chain. `.whenComplete()`'s OWN
        // returned Future rethrows `resolution`'s error, and being
        // unawaited, that rethrow must not surface as a second, separate
        // unhandled exception in the zone alongside the one every real
        // caller of resolveVerifiedEmptyMembership already awaits/catches
        // on `resolution` itself.
        'a rejected resolution does not leak a second, unhandled exception '
        'via the in-flight cleanup chain',
        () async {
          identityStore.seed(
            LastKnownIdentity(
              userId: 'user-1',
              email: 'user1@example.com',
              organizationId: 'org-1',
              membershipRevokedAt: DateTime.utc(2026, 8, 20),
            ),
          );
          identityStore.throwOnClear = true;

          final uncaught = <Object>[];
          await runZonedGuarded(() async {
            await expectLater(
              lifecycle.resolveVerifiedEmptyMembership(
                userId: 'user-1',
                email: 'user1@example.com',
                countPendingWork: () async => 0,
                requestConfirmation: _neverCalledRequestConfirmation,
              ),
              throwsA(isA<StateError>()),
            );
            // Give the unawaited in-flight cleanup chain a turn to
            // (mis)behave before the zone closes.
            await Future<void>.delayed(Duration.zero);
          }, (error, stack) => uncaught.add(error));

          expect(uncaught, isEmpty);
        },
      );

      test(
        'concurrent calls for DIFFERENT userIds are keyed independently '
        'and do not coalesce with each other',
        () async {
          final first = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-1',
            email: 'user1@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );
          final second = lifecycle.resolveVerifiedEmptyMembership(
            userId: 'user-2',
            email: 'user2@example.com',
            countPendingWork: _neverCalledCountPendingWork,
            requestConfirmation: _neverCalledRequestConfirmation,
          );

          expect(identical(first, second), isFalse);

          final results = await Future.wait([first, second]);
          expect(results, [
            MembershipRevocationResolution.quarantined,
            MembershipRevocationResolution.quarantined,
          ]);
        },
      );
    },
  );
}

Future<int?> _neverCalledCountPendingWork() =>
    throw StateError(
      'countPendingWork should not be called on a first resolution',
    );

Future<bool> _neverCalledRequestConfirmation(int? pendingCount) => throw StateError(
  'requestConfirmation should not be called when pending work is zero '
  'or the resolution never reached the confirmation gate',
);

class _RecordingSongCatalogStore implements SongCatalogStore {
  final List<String> deleteCalls = <String>[];
  bool throwOnDelete = false;

  @override
  Future<void> deleteCatalogsForUser({required String userId}) async {
    if (throwOnDelete) {
      throw StateError('simulated deleteCatalogsForUser failure');
    }
    deleteCalls.add(userId);
  }

  @override
  Future<void> deleteCatalog({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<EmptySnapshotResolution> resolveEmptySnapshot({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceActiveSnapshot({
    required String userId,
    required String organizationId,
    required List<SongSummary> summaries,
    required List<SongSource> sources,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<List<SongSummary>> readActiveSummaries({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<SongSummary?> readActiveSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => throw UnimplementedError();

  @override
  Future<SongSummary?> readActiveSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<SongSource?> readActiveSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<String?> readLatestCachedOrganizationId({required String userId}) =>
      throw UnimplementedError();

  @override
  Future<void> saveSongMutation(SongCatalogMutationDraft mutation) =>
      throw UnimplementedError();

  @override
  Future<bool> hasUnsyncedSongMutations({required String userId}) =>
      throw UnimplementedError();

  @override
  Future<List<CachedCatalogSongMutation>> readSongMutations({
    required String userId,
    required String organizationId,
    List<SongSyncStatus>? syncStatuses,
  }) => throw UnimplementedError();

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySongId({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<CachedCatalogSongMutation?> readSongMutationBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => throw UnimplementedError();

  @override
  Future<bool> hasVisibleSongSlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) => throw UnimplementedError();

  @override
  Future<String> allocateAvailableSongSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongSummary summary,
    required SongSource source,
    int? expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<int?> markSongCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) => throw UnimplementedError();

  @override
  Future<int?> saveSongMutationStatus({
    required String userId,
    required String organizationId,
    required String songId,
    required String syncStatus,
    String? syncErrorContext,
    int? expectedRevision,
  }) => throw UnimplementedError();
}

class _PlanningDeleteCall {
  const _PlanningDeleteCall({required this.userId, this.shouldContinue});

  final String userId;
  final bool Function()? shouldContinue;
}

class _RecordingPlanningLocalStore implements PlanningLocalStore {
  final List<_PlanningDeleteCall> deleteCalls = <_PlanningDeleteCall>[];
  bool throwOnDelete = false;
  bool abortOnDelete = false;

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {
    if (abortOnDelete) {
      throw const PlanningProjectionAbortedException();
    }
    if (throwOnDelete) {
      throw StateError('simulated deletePlanningDataForUser failure');
    }
    deleteCalls.add(
      _PlanningDeleteCall(userId: userId, shouldContinue: shouldContinue),
    );
  }

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) => throw UnimplementedError();

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) => throw UnimplementedError();

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) => throw UnimplementedError();

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) => throw UnimplementedError();

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<String?> readLatestCachedOrganizationId({required String userId}) =>
      throw UnimplementedError();

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) => throw UnimplementedError();

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) => throw UnimplementedError();
}

class _RecordingLastKnownIdentityStore implements LastKnownIdentityStore {
  LastKnownIdentity? _current;
  final List<LastKnownIdentity> writes = <LastKnownIdentity>[];
  final List<String> callLog = <String>[];
  bool throwOnClear = false;
  Completer<void>? _readStarted;
  Completer<void>? _readGate;

  void seed(LastKnownIdentity identity) {
    _current = identity;
  }

  /// Makes the NEXT [read] block after logging the call (so the caller is
  /// genuinely awaiting inside `_identityStore.read()`) until [releaseRead]
  /// is called. Used to prove, observably, that a concurrent per-userId
  /// mutation genuinely waits for an in-flight one to finish rather than
  /// merely happening to run in order by luck of scheduling.
  void blockNextRead() {
    _readStarted = Completer<void>();
    _readGate = Completer<void>();
  }

  /// Completes once the blocked [read] call has actually started (i.e. is
  /// parked awaiting the gate) -- lets a test know it is safe to assert
  /// "nothing else has run yet" without a race against the read itself not
  /// having started.
  Future<void> get readStarted => _readStarted!.future;

  void releaseRead() => _readGate!.complete();

  @override
  Future<LastKnownIdentity?> read() async {
    final started = _readStarted;
    final gate = _readGate;
    if (started != null && gate != null) {
      started.complete();
      await gate.future;
      _readStarted = null;
      _readGate = null;
    }
    callLog.add('read');
    return _current;
  }

  @override
  Future<void> write(LastKnownIdentity identity) async {
    callLog.add('write');
    writes.add(identity);
    _current = identity;
  }

  @override
  Future<void> clear() async {
    callLog.add('clear');
    if (throwOnClear) {
      throw StateError('simulated clear failure');
    }
    _current = null;
  }
}

class _RecordedPurgeCall {
  const _RecordedPurgeCall({
    required this.target,
    required this.reason,
    this.userId,
    this.rowsAffected,
  });

  final PurgeTarget target;
  final PurgeReason reason;
  final String? userId;
  final int? rowsAffected;
}

class _RecordedQuarantineCall {
  const _RecordedQuarantineCall({
    required this.target,
    required this.reason,
    this.userId,
  });

  final PurgeTarget target;
  final String reason;
  final String? userId;
}

class _RecordingLocalDataEventsRecorder implements LocalDataEventsRecorder {
  final List<_RecordedPurgeCall> purgeCalls = <_RecordedPurgeCall>[];
  final List<_RecordedQuarantineCall> quarantineCalls =
      <_RecordedQuarantineCall>[];
  bool throwOnRecord = false;
  bool throwOnQuarantineRecord = false;

  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {
    if (throwOnRecord) {
      throw StateError('simulated recordPurge failure');
    }
    purgeCalls.add(
      _RecordedPurgeCall(
        target: target,
        reason: reason,
        userId: userId,
        rowsAffected: rowsAffected,
      ),
    );
  }

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
  Future<void> recordQuarantine({
    required PurgeTarget target,
    required String reason,
    String? userId,
  }) async {
    if (throwOnQuarantineRecord) {
      throw StateError('simulated recordQuarantine failure');
    }
    quarantineCalls.add(
      _RecordedQuarantineCall(target: target, reason: reason, userId: userId),
    );
  }
}
