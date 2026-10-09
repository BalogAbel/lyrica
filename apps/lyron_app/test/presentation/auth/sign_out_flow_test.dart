import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  Future<Future<bool>> open(WidgetTester tester, int? pendingCount) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showUnsyncedSignOutDialog(
                context,
                pendingCount: pendingCount,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('names a known count', (tester) async {
    await open(tester, 3);
    expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);
    expect(
      find.text(AppStrings.unsyncedSignOutPendingMessage(count: 3)),
      findsOneWidget,
    );
  });

  testWidgets('says an unknown count is unknown', (tester) async {
    await open(tester, null);
    expect(
      find.text(AppStrings.unsyncedSignOutUnknownPendingMessage),
      findsOneWidget,
    );
  });

  testWidgets('confirm answers true', (tester) async {
    final result = await open(tester, 1);
    await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel and a barrier dismiss answer false', (tester) async {
    final cancelled = await open(tester, 1);
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();
    expect(await cancelled, isFalse);

    final dismissed = await open(tester, 1);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await dismissed, isFalse);
  });

  test('the count message is singular for one change', () {
    expect(
      AppStrings.unsyncedSignOutPendingMessage(count: 1),
      'You have 1 unsynced change. Signing out will permanently discard it.',
    );
    expect(
      AppStrings.unsyncedSignOutPendingMessage(count: 2),
      'You have 2 unsynced changes. Signing out will permanently discard '
      'them.',
    );
  });
}
