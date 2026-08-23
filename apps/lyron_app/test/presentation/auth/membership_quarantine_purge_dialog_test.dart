import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/auth/membership_quarantine_purge_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  testWidgets('confirm button returns true', (tester) async {
    late bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showMembershipQuarantinePurgeDialog(
                    context,
                    pendingCount: 3,
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

    final expectedMessage =
        AppStrings.membershipQuarantinePurgePendingMessage(count: 3);
    expect(find.text(expectedMessage), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('membership-quarantine-purge-confirm')),
    );
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('cancel button returns false', (tester) async {
    late bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showMembershipQuarantinePurgeDialog(
                    context,
                    pendingCount: 2,
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

    await tester.tap(
      find.byKey(const Key('membership-quarantine-purge-cancel')),
    );
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('barrier dismiss returns false (safe default)', (tester) async {
    late bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showMembershipQuarantinePurgeDialog(
                    context,
                    pendingCount: 1,
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

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('displays the title and the pending-count message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  await showMembershipQuarantinePurgeDialog(
                    context,
                    pendingCount: 5,
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

    expect(
      find.text(AppStrings.membershipQuarantinePurgeTitle),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.membershipQuarantinePurgePendingMessage(count: 5)),
      findsOneWidget,
    );
  });

  testWidgets(
    'unknown pending count renders an honest unknown-amount message, not a '
    'fabricated number, and confirm still returns true',
    (tester) async {
      late bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showMembershipQuarantinePurgeDialog(
                      context,
                      pendingCount: null,
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

      final expectedMessage =
          AppStrings.membershipQuarantinePurgeUnknownPendingMessage;
      expect(find.text(expectedMessage), findsOneWidget);
      // No count is fabricated anywhere in the unknown-amount message.
      for (var n = 0; n <= 9; n++) {
        expect(expectedMessage.contains('$n'), isFalse);
      }

      await tester.tap(
        find.byKey(const Key('membership-quarantine-purge-confirm')),
      );
      await tester.pumpAndSettle();

      expect(result, isTrue);
    },
  );

  testWidgets(
    // The plan's guardrail: "the confirmation must have named what is
    // lost" -- the dialog copy must plainly state that confirming deletes
    // local song/plan data, in both the known-count and unknown-count
    // messages.
    'both messages plainly name what confirming deletes (local songs and '
    'plans)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showMembershipQuarantinePurgeDialog(
                      context,
                      pendingCount: 4,
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

      final knownMessage = AppStrings.membershipQuarantinePurgePendingMessage(
        count: 4,
      );
      final unknownMessage =
          AppStrings.membershipQuarantinePurgeUnknownPendingMessage;
      for (final message in [knownMessage, unknownMessage]) {
        expect(message.contains('dal'), isTrue);
        expect(message.contains('terv'), isTrue);
      }
    },
  );
}
