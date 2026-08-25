import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late LastKnownIdentityDatabase database;
  late DriftLastKnownIdentityStore store;

  setUp(() {
    database = LastKnownIdentityDatabase.inMemory();
    store = DriftLastKnownIdentityStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('empty read returns null', () async {
    expect(await store.read(), isNull);
  });

  test('write then read returns the identity', () async {
    await store.write(
      const LastKnownIdentity(
        userId: 'u1',
        email: 'e@x',
        organizationId: 'org1',
      ),
    );

    final got = await store.read();

    expect(got?.userId, 'u1');
    expect(got?.email, 'e@x');
    expect(got?.organizationId, 'org1');
  });

  test('clear removes the identity', () async {
    await store.write(
      const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
    );

    await store.clear();

    expect(await store.read(), isNull);
  });

  group('resolveEmptyMembership', () {
    test('no stored row -> ignored, writes nothing', () async {
      final outcome = await store.resolveEmptyMembership(userId: 'u1');

      expect(outcome, isA<EmptyMembershipResolutionIgnored>());
      expect(await store.read(), isNull);
    });

    test(
      'stored row owned by a different user -> ignored, row untouched',
      () async {
        await store.write(
          const LastKnownIdentity(
            userId: 'owner',
            email: 'e@x',
            organizationId: null,
          ),
        );

        final outcome = await store.resolveEmptyMembership(
          userId: 'someone-else',
        );

        expect(outcome, isA<EmptyMembershipResolutionIgnored>());
        final second = await store.resolveEmptyMembership(userId: 'owner');
        // The owner's first call is still a first confirmation -- proves the
        // other user's call recorded nothing.
        expect(second, isA<EmptyMembershipResolutionMarkerRecorded>());
      },
    );

    test('owned row with no marker -> records the marker', () async {
      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        ),
      );

      final outcome = await store.resolveEmptyMembership(userId: 'u1');

      expect(outcome, isA<EmptyMembershipResolutionMarkerRecorded>());
      final markedAt =
          (outcome as EmptyMembershipResolutionMarkerRecorded).markedAt;
      expect(markedAt.isUtc, isTrue);
    });

    test('owned row with an existing marker -> reports second confirmation '
        'available, does not clear or move the marker', () async {
      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        ),
      );
      final first =
          await store.resolveEmptyMembership(userId: 'u1')
              as EmptyMembershipResolutionMarkerRecorded;

      final second = await store.resolveEmptyMembership(userId: 'u1');

      expect(
        second,
        isA<EmptyMembershipResolutionSecondConfirmationAvailable>(),
      );
      final secondMarkedAt =
          (second as EmptyMembershipResolutionSecondConfirmationAvailable)
              .markedAt;
      // The store round-trips through a sqlite integer column with
      // second precision -- compare with second granularity rather than
      // exact equality, which would be sensitive to microseconds that
      // storage never preserves.
      expect(
        secondMarkedAt.toUtc().difference(first.markedAt.toUtc()).inSeconds,
        0,
      );

      // A third call still reports the same unresolved marker -- proves
      // the second call did not clear or move it.
      final third = await store.resolveEmptyMembership(userId: 'u1');
      expect(
        third,
        isA<EmptyMembershipResolutionSecondConfirmationAvailable>(),
      );
      expect(
        (third as EmptyMembershipResolutionSecondConfirmationAvailable).markedAt
            .toUtc()
            .difference(first.markedAt.toUtc())
            .inSeconds,
        0,
      );
    });
  });

  group('clearMembershipRevocation', () {
    test('no stored row -> returns false', () async {
      expect(await store.clearMembershipRevocation(userId: 'u1'), isFalse);
    });

    test(
      'stored row owned by a different user -> returns false, marker untouched',
      () async {
        await store.write(
          const LastKnownIdentity(
            userId: 'owner',
            email: 'e@x',
            organizationId: null,
          ),
        );
        await store.resolveEmptyMembership(userId: 'owner');

        expect(
          await store.clearMembershipRevocation(userId: 'someone-else'),
          isFalse,
        );

        // The owner's marker is still present -- a second resolution reports
        // "second confirmation available", not a fresh first confirmation.
        final outcome = await store.resolveEmptyMembership(userId: 'owner');
        expect(
          outcome,
          isA<EmptyMembershipResolutionSecondConfirmationAvailable>(),
        );
      },
    );

    test(
      'owned row with no marker -> returns false (no spurious clear)',
      () async {
        await store.write(
          const LastKnownIdentity(
            userId: 'u1',
            email: 'e@x',
            organizationId: null,
          ),
        );

        expect(await store.clearMembershipRevocation(userId: 'u1'), isFalse);
      },
    );

    test('owned row with a marker -> clears it, returns true', () async {
      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        ),
      );
      await store.resolveEmptyMembership(userId: 'u1');

      expect(await store.clearMembershipRevocation(userId: 'u1'), isTrue);

      final outcome = await store.resolveEmptyMembership(userId: 'u1');
      expect(outcome, isA<EmptyMembershipResolutionMarkerRecorded>());
    });
  });

  group('write() and the membership-revocation marker', () {
    test('a same-user write preserves an existing marker', () async {
      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        ),
      );
      await store.resolveEmptyMembership(userId: 'u1');

      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: 'org1',
        ),
      );

      final outcome = await store.resolveEmptyMembership(userId: 'u1');
      expect(
        outcome,
        isA<EmptyMembershipResolutionSecondConfirmationAvailable>(),
      );
    });

    test('a different-user write starts with no marker, even if the prior '
        'user had one set', () async {
      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        ),
      );
      await store.resolveEmptyMembership(userId: 'u1');

      await store.write(
        const LastKnownIdentity(
          userId: 'u2',
          email: 'f@x',
          organizationId: null,
        ),
      );

      final outcome = await store.resolveEmptyMembership(userId: 'u2');
      expect(outcome, isA<EmptyMembershipResolutionMarkerRecorded>());
    });

    test('a write with no prior row starts with no marker', () async {
      await store.write(
        const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        ),
      );

      final outcome = await store.resolveEmptyMembership(userId: 'u1');
      expect(outcome, isA<EmptyMembershipResolutionMarkerRecorded>());
    });
  });
}
