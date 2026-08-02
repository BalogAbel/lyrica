import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/reauth_resolution.dart';

void main() {
  group('ReauthOutcome', () {
    test('ReauthProceededSameUser is a sealed class outcome', () {
      const outcome = ReauthProceededSameUser();
      expect(outcome, isA<ReauthOutcome>());
    });

    test('ReauthWipedPriorAndProceeded is a sealed class outcome', () {
      const outcome = ReauthWipedPriorAndProceeded();
      expect(outcome, isA<ReauthOutcome>());
    });

    test('ReauthCancelledKeptPriorUser is a sealed class outcome', () {
      const outcome = ReauthCancelledKeptPriorUser();
      expect(outcome, isA<ReauthOutcome>());
    });
  });

  group('resolveReauth', () {
    test('same-user re-auth flushes queue without wiping', () async {
      var flushSameUserCalled = false;
      var wipePriorAndProceedCalled = false;
      var confirmDifferentUserCalled = false;

      final outcome = await resolveReauth(
        newUserId: 'u1',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 0,
        flushSameUser: () async {
          flushSameUserCalled = true;
        },
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              confirmDifferentUserCalled = true;
              return true;
            },
        cancelToPriorUser: () async {},
      );

      expect(flushSameUserCalled, isTrue);
      expect(wipePriorAndProceedCalled, isFalse);
      expect(confirmDifferentUserCalled, isFalse);
      expect(outcome, isA<ReauthProceededSameUser>());
    });

    test('no prior identity proceeds as same-user (no wipe)', () async {
      var flushSameUserCalled = false;
      var wipePriorAndProceedCalled = false;

      final outcome = await resolveReauth(
        newUserId: 'u2',
        priorUserId: null,
        priorEmail: null,
        priorPendingCount: () async => 0,
        flushSameUser: () async {
          flushSameUserCalled = true;
        },
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              return true;
            },
        cancelToPriorUser: () async {},
      );

      expect(flushSameUserCalled, isTrue);
      expect(wipePriorAndProceedCalled, isFalse);
      expect(outcome, isA<ReauthProceededSameUser>());
    });

    test(
      'different-user with pending requires confirmation before wipe',
      () async {
        bool wipePriorCalled = false;
        bool confirmCalled = false;
        bool wipePriorCalledBeforeConfirm = false;

        final outcome = await resolveReauth(
          newUserId: 'u2',
          priorUserId: 'u1',
          priorEmail: 'u1@example.com',
          priorPendingCount: () async => 2,
          flushSameUser: () async {},
          wipePriorAndProceed: () async {
            wipePriorCalled = true;
          },
          confirmDifferentUser:
              ({required String email, required int? pendingCount}) async {
                confirmCalled = true;
                // Assert wipePriorAndProceed has NOT been called yet
                wipePriorCalledBeforeConfirm = wipePriorCalled;
                expect(
                  wipePriorCalled,
                  isFalse,
                  reason:
                      'wipePriorAndProceed must not be called before confirmDifferentUser resolves',
                );
                expect(email, 'u1@example.com');
                expect(pendingCount, 2);
                return true;
              },
          cancelToPriorUser: () async {},
        );

        expect(confirmCalled, isTrue);
        expect(wipePriorCalledBeforeConfirm, isFalse);
        expect(
          wipePriorCalled,
          isTrue,
          reason:
              'wipePriorAndProceed must be called after confirm resolves true',
        );
        expect(outcome, isA<ReauthWipedPriorAndProceeded>());
      },
    );

    test('different-user cancel keeps prior user data', () async {
      var wipePriorAndProceedCalled = false;
      var cancelToPriorUserCalled = false;

      final outcome = await resolveReauth(
        newUserId: 'u2',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 3,
        flushSameUser: () async {},
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              expect(email, 'u1@example.com');
              expect(pendingCount, 3);
              return false;
            },
        cancelToPriorUser: () async {
          cancelToPriorUserCalled = true;
        },
      );

      expect(wipePriorAndProceedCalled, isFalse);
      expect(cancelToPriorUserCalled, isTrue);
      expect(outcome, isA<ReauthCancelledKeptPriorUser>());
    });

    test(
      'different-user with an unknown pending count still requires '
      'confirmation before wipe -- unknown must not behave like zero',
      () async {
        bool wipePriorCalled = false;
        bool confirmCalled = false;
        bool wipePriorCalledBeforeConfirm = false;
        int? seenPendingCount = -1;

        final outcome = await resolveReauth(
          newUserId: 'u2',
          priorUserId: 'u1',
          priorEmail: 'u1@example.com',
          priorPendingCount: () async => null,
          flushSameUser: () async {},
          wipePriorAndProceed: () async {
            wipePriorCalled = true;
          },
          confirmDifferentUser:
              ({required String email, required int? pendingCount}) async {
                confirmCalled = true;
                wipePriorCalledBeforeConfirm = wipePriorCalled;
                seenPendingCount = pendingCount;
                expect(
                  wipePriorCalled,
                  isFalse,
                  reason:
                      'wipePriorAndProceed must not be called before confirmDifferentUser resolves',
                );
                return true;
              },
          cancelToPriorUser: () async {},
        );

        expect(
          confirmCalled,
          isTrue,
          reason: 'an unknown count must still trigger confirmation',
        );
        expect(wipePriorCalledBeforeConfirm, isFalse);
        expect(seenPendingCount, isNull);
        expect(
          wipePriorCalled,
          isTrue,
          reason:
              'wipePriorAndProceed must be called after confirm resolves true',
        );
        expect(outcome, isA<ReauthWipedPriorAndProceeded>());
      },
    );

    test('different-user with no pending proceeds without prompt', () async {
      var wipePriorAndProceedCalled = false;
      var confirmDifferentUserCalled = false;

      final outcome = await resolveReauth(
        newUserId: 'u2',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 0,
        flushSameUser: () async {},
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              confirmDifferentUserCalled = true;
              return true;
            },
        cancelToPriorUser: () async {},
      );

      expect(wipePriorAndProceedCalled, isTrue);
      expect(
        confirmDifferentUserCalled,
        isFalse,
        reason: 'confirm should not be called when pending count is 0',
      );
      expect(outcome, isA<ReauthWipedPriorAndProceeded>());
    });
  });
}
