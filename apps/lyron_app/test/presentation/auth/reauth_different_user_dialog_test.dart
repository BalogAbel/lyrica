import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/auth/reauth_different_user_dialog.dart';
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
                  result = await showReauthDifferentUserDialog(
                    context,
                    email: 'user@example.com',
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

    // Verify the dialog shows the correct message
    final expectedMessage = AppStrings.reauthDifferentUserPendingMessage(
      email: 'user@example.com',
      count: 3,
    );
    expect(find.text(expectedMessage), findsOneWidget);

    // Tap confirm
    await tester.tap(find.byKey(const Key('reauth-different-user-confirm')));
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
                  result = await showReauthDifferentUserDialog(
                    context,
                    email: 'user@example.com',
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

    // Tap cancel
    await tester.tap(find.byKey(const Key('reauth-different-user-cancel')));
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
                  result = await showReauthDifferentUserDialog(
                    context,
                    email: 'user@example.com',
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

    // Tap outside the dialog (barrier area)
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // null dismissal → false (safe default)
    expect(result, isFalse);
  });

  testWidgets('displays correct title and email+count in message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  await showReauthDifferentUserDialog(
                    context,
                    email: 'test@example.com',
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

    expect(find.text(AppStrings.reauthDifferentUserTitle), findsOneWidget);
    expect(
      find.text(
        'Másik fiók jelentkezett be. test@example.com-nek 5 mentetlen változtatása van. A folytatás törli ezeket.',
      ),
      findsOneWidget,
    );
  });
}
