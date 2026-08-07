import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
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

    test('ReauthSuperseded is a sealed class outcome', () {
      const outcome = ReauthSuperseded();
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
          return true;
        },
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
          return true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              confirmDifferentUserCalled = true;
              return ReauthPromptResult.confirmed;
            },
        cancelToPriorUser: () async => true,
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
          return true;
        },
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
          return true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              return ReauthPromptResult.confirmed;
            },
        cancelToPriorUser: () async => true,
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
          flushSameUser: () async => true,
          wipePriorAndProceed: () async {
            wipePriorCalled = true;
            return true;
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
                return ReauthPromptResult.confirmed;
              },
          cancelToPriorUser: () async => true,
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
        flushSameUser: () async => true,
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
          return true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              expect(email, 'u1@example.com');
              expect(pendingCount, 3);
              return ReauthPromptResult.cancelled;
            },
        cancelToPriorUser: () async {
          cancelToPriorUserCalled = true;
          return true;
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
          flushSameUser: () async => true,
          wipePriorAndProceed: () async {
            wipePriorCalled = true;
            return true;
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
                return ReauthPromptResult.confirmed;
              },
          cancelToPriorUser: () async => true,
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
        flushSameUser: () async => true,
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
          return true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              confirmDifferentUserCalled = true;
              return ReauthPromptResult.confirmed;
            },
        cancelToPriorUser: () async => true,
      );

      expect(wipePriorAndProceedCalled, isTrue);
      expect(
        confirmDifferentUserCalled,
        isFalse,
        reason: 'confirm should not be called when pending count is 0',
      );
      expect(outcome, isA<ReauthWipedPriorAndProceeded>());
    });

    test('superseded prompt invokes neither wipe nor cancel', () async {
      var wipePriorAndProceedCalled = false;
      var cancelToPriorUserCalled = false;

      final outcome = await resolveReauth(
        newUserId: 'u2',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 1,
        flushSameUser: () async => true,
        wipePriorAndProceed: () async {
          wipePriorAndProceedCalled = true;
          return true;
        },
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async {
              return ReauthPromptResult.superseded;
            },
        cancelToPriorUser: () async {
          cancelToPriorUserCalled = true;
          return true;
        },
      );

      expect(wipePriorAndProceedCalled, isFalse);
      expect(cancelToPriorUserCalled, isFalse);
      expect(outcome, isA<ReauthSuperseded>());
    });

    test('a side-effect callback reporting it did not run (false) resolves '
        'as superseded, at each of the three call sites', () async {
      // Pins the fix itself: flushSameUser/wipePriorAndProceed/
      // cancelToPriorUser are typed Future<bool> Function() concretely, so
      // a callback that returns false because a last-moment currentness
      // guard stopped it must be reported as ReauthSuperseded rather than
      // the coordinator claiming the effect happened.
      final sameUserOutcome = await resolveReauth(
        newUserId: 'u1',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 0,
        flushSameUser: () async => false,
        wipePriorAndProceed: () async => true,
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async =>
                ReauthPromptResult.confirmed,
        cancelToPriorUser: () async => true,
      );
      expect(sameUserOutcome, isA<ReauthSuperseded>());

      final wipeOutcome = await resolveReauth(
        newUserId: 'u2',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 0,
        flushSameUser: () async => true,
        wipePriorAndProceed: () async => false,
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async =>
                ReauthPromptResult.confirmed,
        cancelToPriorUser: () async => true,
      );
      expect(wipeOutcome, isA<ReauthSuperseded>());

      final cancelOutcome = await resolveReauth(
        newUserId: 'u2',
        priorUserId: 'u1',
        priorEmail: 'u1@example.com',
        priorPendingCount: () async => 1,
        flushSameUser: () async => true,
        wipePriorAndProceed: () async => true,
        confirmDifferentUser:
            ({required String email, required int? pendingCount}) async =>
                ReauthPromptResult.cancelled,
        cancelToPriorUser: () async => false,
      );
      expect(cancelOutcome, isA<ReauthSuperseded>());
    });
  });
}
