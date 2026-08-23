import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
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
  // A controllable stand-in for D5.3's monotonic clock -- tests advance
  // this directly instead of sleeping for a real 60 seconds. Never wired to
  // wall-clock time, matching the constraint the cooldown itself has to
  // satisfy.
  late Duration monotonicElapsed;

  setUp(() {
    songCatalogStore = _RecordingSongCatalogStore();
    planningLocalStore = _RecordingPlanningLocalStore();
    identityStore = _RecordingLastKnownIdentityStore();
    eventsRecorder = _RecordingLocalDataEventsRecorder();
    notedIdentities = <LastKnownIdentity?>[];
    monotonicElapsed = Duration.zero;
    lifecycle = LocalDataLifecycle(
      songCatalogStore: songCatalogStore,
      planningLocalStore: planningLocalStore,
      identityStore: identityStore,
      noteLastKnownIdentity: notedIdentities.add,
      eventsRecorder: eventsRecorder,
      monotonicNow: () => monotonicElapsed,
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
    // D5.5 rule 5 / closeout finding 4: clearIdentity with a non-null
    // userId now checks ownership first (reads, then clears only if the
    // stored row belongs to that userId), which is why every test that
    // supplies a userId now seeds a matching row first. The old
    // "no internal identity read" behaviour was exactly the bug closeout
    // finding 4 describes -- see local_data_lifecycle.dart's clearIdentity
    // doc for why that invariant was deliberately dropped, not preserved.
    test('clears, notes null, and records the caller-supplied userId on the '
        'audit row, when the stored row is owned by that userId', () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-3',
          email: 'user3@example.com',
          organizationId: 'org-3',
        ),
      );

      await lifecycle.clearIdentity(
        reason: PurgeReason.accountDeleted,
        userId: 'user-3',
      );

      expect(identityStore.callLog, ['read', 'clear']);
      expect(notedIdentities, [null]);
      expect(eventsRecorder.purgeCalls, hasLength(1));
      final recorded = eventsRecorder.purgeCalls.single;
      expect(recorded.target, PurgeTarget.identity);
      expect(recorded.reason, PurgeReason.accountDeleted);
      expect(recorded.userId, 'user-3');
      expect(recorded.rowsAffected, isNull);
    });

    test(
      'a userId that does not own the stored row -- no write of any kind',
      () async {
        identityStore.seed(
          const LastKnownIdentity(
            userId: 'owner',
            email: 'owner@example.com',
            organizationId: 'org-3',
          ),
        );

        await lifecycle.clearIdentity(
          reason: PurgeReason.accountDeleted,
          userId: 'someone-else',
        );

        expect(identityStore.callLog, ['read']);
        expect(notedIdentities, isEmpty);
        expect(eventsRecorder.purgeCalls, isEmpty);
      },
    );

    test('a userId with no stored row at all -- no write of any kind', () async {
      await lifecycle.clearIdentity(
        reason: PurgeReason.accountDeleted,
        userId: 'user-3',
      );

      expect(identityStore.callLog, ['read']);
      expect(notedIdentities, isEmpty);
      expect(eventsRecorder.purgeCalls, isEmpty);
    });

    test('when the caller has no userId to supply, clears unconditionally '
        'and records a null userId (explicit sign-out; no owner to check '
        'against)', () async {
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
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-4',
          email: 'user4@example.com',
          organizationId: 'org-4',
        ),
      );
      identityStore.throwOnClear = true;

      await expectLater(
        () => lifecycle.clearIdentity(
          reason: PurgeReason.membershipRevokedConfirmed,
          userId: 'user-4',
        ),
        throwsA(isA<StateError>()),
      );

      expect(identityStore.callLog, ['read', 'clear']);
      expect(notedIdentities, isEmpty);
      expect(eventsRecorder.purgeCalls, isEmpty);
    });

    test('when the audit recorder throws, the clear and the note already '
        'committed are NOT undone or reported as a failure -- the method '
        'completes without throwing', () async {
      identityStore.seed(
        const LastKnownIdentity(
          userId: 'user-5',
          email: 'user5@example.com',
          organizationId: 'org-5',
        ),
      );
      eventsRecorder.throwOnRecord = true;

      await lifecycle.clearIdentity(
        reason: PurgeReason.userSignOut,
        userId: 'user-5',
      );

      expect(identityStore.callLog, ['read', 'clear']);
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

  // D5 (docs/specs/2026-08-19-local-data-durability-contract.md) Step 1
  // (docs/plans/2026-08-19-local-data-durability-contract.md, Task 4.1):
  // the required negative tests. Every one of these asserts NOTHING is
  // deleted -- Step 1 adds no new deletion at all, membership revocation
  // purges nothing after Step 1, and these tests exist to make sure that
  // stays true even as Step 2 later wires a real purge onto
  // MembershipRevocationPurgeAuthorized.
  group('resolveVerifiedEmptyMembership', () {
    test(
      '1. one verifiedEmpty resolution -> nothing deleted, marker recorded, '
      'catalog and planning still fully readable',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
        );

        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );

        expect(decision, isA<MembershipRevocationMarkerRecorded>());
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.read(), completion(isNotNull));
        expect(
          eventsRecorder.membershipRevocationMarkedCalls,
          ['u1'],
        );
        expect(eventsRecorder.purgeCalls, isEmpty);
      },
    );

    test(
      '2. a second verifiedEmpty inside the cooldown -> nothing deleted, '
      'marker unchanged',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
        );
        await lifecycle.resolveVerifiedEmptyMembership(userId: 'u1');
        final markedAt = identityStore.membershipRevokedAt;

        monotonicElapsed = const Duration(seconds: 59);
        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );

        expect(
          decision,
          equals(
            const MembershipRevocationIgnored(
              MembershipRevocationIgnoredReason.insideCooldown,
            ),
          ),
        );
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.membershipRevokedAt, markedAt);
        // Only the first confirmation's marked-edge is audited -- the
        // inside-cooldown no-op writes no audit record of its own.
        expect(eventsRecorder.membershipRevocationMarkedCalls, ['u1']);
      },
    );

    test(
      '3. advancing the WALL clock past the cooldown does not satisfy it '
      '(the injected monotonic source has not advanced)',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
        );
        await lifecycle.resolveVerifiedEmptyMembership(userId: 'u1');
        // monotonicElapsed is deliberately left at Duration.zero -- only
        // wall-clock time (which this store's DateTime.now() calls still
        // advance through) has "passed".

        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );

        expect(
          decision,
          equals(
            const MembershipRevocationIgnored(
              MembershipRevocationIgnoredReason.insideCooldown,
            ),
          ),
        );
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
      },
    );

    test(
      '4. marker set, then a fresh non-empty resolution clears it, then a '
      'verifiedEmpty -> nothing deleted (this is a first confirmation '
      'again, not a second)',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
        );
        await lifecycle.resolveVerifiedEmptyMembership(userId: 'u1');

        await lifecycle.clearMembershipRevocation(userId: 'u1');

        // Even past the cooldown, the very next verifiedEmpty is a FIRST
        // confirmation, not a second -- the marker was genuinely cleared.
        monotonicElapsed = const Duration(seconds: 120);
        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );

        expect(decision, isA<MembershipRevocationMarkerRecorded>());
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(
          eventsRecorder.membershipRevocationClearedCalls,
          ['u1'],
        );
      },
    );

    test(
      '5. marker set for user A, user B signs in -> B\'s row carries no '
      'marker; a verifiedEmpty for B is B\'s first confirmation',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'A', email: 'a@x', organizationId: null),
        );
        await lifecycle.resolveVerifiedEmptyMembership(userId: 'A');

        await lifecycle.writeIdentity(
          const LastKnownIdentity(userId: 'B', email: 'b@x', organizationId: null),
        );

        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'B',
        );

        expect(decision, isA<MembershipRevocationMarkerRecorded>());
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
      },
    );

    test(
      '6. a resolution for a user who does not own the stored row -> no '
      'write of any kind',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'owner', email: 'o@x', organizationId: null),
        );

        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'someone-else',
        );

        expect(
          decision,
          equals(
            const MembershipRevocationIgnored(
              MembershipRevocationIgnoredReason.notThisUser,
            ),
          ),
        );
        expect(identityStore.writes, isEmpty);
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(eventsRecorder.membershipRevocationMarkedCalls, isEmpty);
        expect(eventsRecorder.membershipRevocationClearedCalls, isEmpty);
      },
    );

    test('6b. a resolution with no stored row at all -> ignored as noRow', () async {
      final decision = await lifecycle.resolveVerifiedEmptyMembership(
        userId: 'nobody-yet',
      );

      expect(
        decision,
        equals(
          const MembershipRevocationIgnored(
            MembershipRevocationIgnoredReason.noRow,
          ),
        ),
      );
      expect(songCatalogStore.deleteCalls, isEmpty);
      expect(planningLocalStore.deleteCalls, isEmpty);
    });

    test(
      '8. the marker survives a process restart (a new LocalDataLifecycle '
      'over the same store) and does not by itself become a second '
      'confirmation',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
        );
        await lifecycle.resolveVerifiedEmptyMembership(userId: 'u1');

        // A fresh LocalDataLifecycle over the SAME identityStore -- models
        // a process restart. Its own in-process tracking starts empty, so
        // it did not record the marker itself.
        final restarted = LocalDataLifecycle(
          songCatalogStore: songCatalogStore,
          planningLocalStore: planningLocalStore,
          identityStore: identityStore,
          noteLastKnownIdentity: notedIdentities.add,
          eventsRecorder: eventsRecorder,
          monotonicNow: () => Duration.zero,
        );

        // Per D5.3, a resolution from a separate launch is an independent
        // event -- no cooldown check applies, so this is the genuine
        // second, cooldown-independent confirmation.
        final decision = await restarted.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );

        expect(decision, isA<MembershipRevocationPurgeAuthorized>());
        // Step 1: even the second, cooldown-independent confirmation
        // deletes nothing yet -- Step 2 wires the actual purge onto this
        // outcome.
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.callLog, isNot(contains('clear')));
      },
    );

    test(
      'a second confirmation past the cooldown, in the SAME process, '
      'authorizes a purge decision but Step 1 deletes nothing',
      () async {
        identityStore.seed(
          const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
        );
        final first = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );
        expect(first, isA<MembershipRevocationMarkerRecorded>());

        monotonicElapsed = const Duration(seconds: 60);
        final decision = await lifecycle.resolveVerifiedEmptyMembership(
          userId: 'u1',
        );

        expect(decision, isA<MembershipRevocationPurgeAuthorized>());
        expect(songCatalogStore.deleteCalls, isEmpty);
        expect(planningLocalStore.deleteCalls, isEmpty);
        expect(identityStore.writes, isEmpty);
      },
    );
  });

  group('clearMembershipRevocation', () {
    test('7. offline/connectivity-failure/unknown-failure/expired-session '
        'resolutions never call this -- clearing only ever runs for a '
        'genuinely owned, marked row, and is a no-op with no audit record '
        'otherwise', () async {
      identityStore.seed(
        const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
      );
      // No marker was ever set -- an ordinary sign-in must not write a
      // spurious audit row.
      await lifecycle.clearMembershipRevocation(userId: 'u1');

      expect(eventsRecorder.membershipRevocationClearedCalls, isEmpty);
      expect(songCatalogStore.deleteCalls, isEmpty);
      expect(planningLocalStore.deleteCalls, isEmpty);
    });

    test('clears a genuinely set marker and writes exactly one audit '
        'record', () async {
      identityStore.seed(
        const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
      );
      await lifecycle.resolveVerifiedEmptyMembership(userId: 'u1');

      await lifecycle.clearMembershipRevocation(userId: 'u1');

      expect(identityStore.membershipRevokedAt, isNull);
      expect(eventsRecorder.membershipRevocationClearedCalls, ['u1']);
    });

    test('a userId that does not own the marked row -> no clear, no audit '
        'record', () async {
      identityStore.seed(
        const LastKnownIdentity(userId: 'owner', email: 'o@x', organizationId: null),
      );
      await lifecycle.resolveVerifiedEmptyMembership(userId: 'owner');

      await lifecycle.clearMembershipRevocation(userId: 'someone-else');

      expect(identityStore.membershipRevokedAt, isNotNull);
      expect(eventsRecorder.membershipRevocationClearedCalls, isEmpty);
    });
  });

  test('every PurgeReason value works through a destructive method', () async {
    for (final reason in PurgeReason.values) {
      eventsRecorder.purgeCalls.clear();
      await lifecycle.purgeSongCatalog(userId: 'user-x', reason: reason);
      expect(eventsRecorder.purgeCalls.single.reason, reason);
    }
  });
}

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
  DateTime? _membershipRevokedAt;
  final List<LastKnownIdentity> writes = <LastKnownIdentity>[];
  final List<String> callLog = <String>[];
  bool throwOnClear = false;

  void seed(LastKnownIdentity identity, {DateTime? membershipRevokedAt}) {
    _current = identity;
    _membershipRevokedAt = membershipRevokedAt;
  }

  DateTime? get membershipRevokedAt => _membershipRevokedAt;

  @override
  Future<LastKnownIdentity?> read() async {
    callLog.add('read');
    return _current;
  }

  @override
  Future<void> write(LastKnownIdentity identity) async {
    callLog.add('write');
    writes.add(identity);
    // Mirrors DriftLastKnownIdentityStore.write()'s marker contract: the
    // marker survives a same-user write, and is reset for a different user
    // (or when no row previously existed).
    if (_current?.userId != identity.userId) {
      _membershipRevokedAt = null;
    }
    _current = identity;
  }

  @override
  Future<void> clear() async {
    callLog.add('clear');
    if (throwOnClear) {
      throw StateError('simulated clear failure');
    }
    _current = null;
    _membershipRevokedAt = null;
  }

  @override
  Future<EmptyMembershipResolutionOutcome> resolveEmptyMembership({
    required String userId,
  }) async {
    callLog.add('resolveEmptyMembership:$userId');
    final current = _current;
    if (current == null || current.userId != userId) {
      return const EmptyMembershipResolutionIgnored();
    }
    final existingMarker = _membershipRevokedAt;
    if (existingMarker != null) {
      return EmptyMembershipResolutionSecondConfirmationAvailable(
        markedAt: existingMarker,
      );
    }
    final markedAt = DateTime.now().toUtc();
    _membershipRevokedAt = markedAt;
    return EmptyMembershipResolutionMarkerRecorded(markedAt: markedAt);
  }

  @override
  Future<bool> clearMembershipRevocation({required String userId}) async {
    callLog.add('clearMembershipRevocation:$userId');
    final current = _current;
    if (current == null ||
        current.userId != userId ||
        _membershipRevokedAt == null) {
      return false;
    }
    _membershipRevokedAt = null;
    return true;
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

class _RecordingLocalDataEventsRecorder implements LocalDataEventsRecorder {
  final List<_RecordedPurgeCall> purgeCalls = <_RecordedPurgeCall>[];
  final List<String> membershipRevocationMarkedCalls = <String>[];
  final List<String> membershipRevocationClearedCalls = <String>[];
  bool throwOnRecord = false;
  bool throwOnMembershipRevocationMarked = false;
  bool throwOnMembershipRevocationCleared = false;

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
  Future<void> recordMembershipRevocationMarked({
    required String userId,
  }) async {
    if (throwOnMembershipRevocationMarked) {
      throw StateError('simulated recordMembershipRevocationMarked failure');
    }
    membershipRevocationMarkedCalls.add(userId);
  }

  @override
  Future<void> recordMembershipRevocationCleared({
    required String userId,
  }) async {
    if (throwOnMembershipRevocationCleared) {
      throw StateError('simulated recordMembershipRevocationCleared failure');
    }
    membershipRevocationClearedCalls.add(userId);
  }
}
