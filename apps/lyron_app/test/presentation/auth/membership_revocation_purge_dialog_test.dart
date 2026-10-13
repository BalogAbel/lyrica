import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/auth/membership_revocation_purge_dialog.dart';

// The membership-revocation purge dialog (ADR-035 D5.4). The dialog's English
// copy is pinned with literals, not constants, so a copy regression is
// visible (S6a FB14, acceptance criterion L1). The decision paths pin that
// the translation changed text only: confirm deletes, cancel and a barrier
// dismiss keep everything.
void main() {
  group('showMembershipRevocationPurgeDialog', () {
    // The dialog's result; null until the dialog is answered.
    bool? result;

    Future<void> openDialog(WidgetTester tester, {required int? count}) async {
      result = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showMembershipRevocationPurgeDialog(
                      context,
                      pendingCount: count,
                    );
                  },
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();
    }

    testWidgets('known count: English title and plural message', (
      tester,
    ) async {
      await openDialog(tester, count: 7);

      expect(
        find.text('Your organization membership has ended.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your organization membership has ended on this device. '
          'Continuing permanently deletes all locally stored songs and '
          'plans, including 7 unsynced changes.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a count of one uses the singular', (tester) async {
      await openDialog(tester, count: 1);

      expect(
        find.text(
          'Your organization membership has ended on this device. '
          'Continuing permanently deletes all locally stored songs and '
          'plans, including 1 unsynced change.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('unknown count states that the number is unknown', (
      tester,
    ) async {
      await openDialog(tester, count: null);

      expect(
        find.text(
          'Your organization membership has ended on this device. '
          'Continuing permanently deletes all locally stored songs and '
          'plans. The exact number of unsynced changes could not be '
          'determined, but continuing deletes them too.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('buttons read Delete and Cancel', (tester) async {
      await openDialog(tester, count: 2);

      expect(
        find.descendant(
          of: find.byKey(const Key('membership-revocation-purge-confirm')),
          matching: find.text('Delete'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('membership-revocation-purge-cancel')),
          matching: find.text('Cancel'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('confirm returns true', (tester) async {
      await openDialog(tester, count: 2);

      await tester.tap(
        find.byKey(const Key('membership-revocation-purge-confirm')),
      );
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancel returns false', (tester) async {
      await openDialog(tester, count: 2);

      await tester.tap(
        find.byKey(const Key('membership-revocation-purge-cancel')),
      );
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('barrier dismiss returns false (safe default)', (tester) async {
      await openDialog(tester, count: null);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
