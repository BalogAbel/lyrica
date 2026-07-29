import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/planning/widgets/retryable_error_state.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  testWidgets('shows the message and the retry action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetryableErrorState(message: 'Could not load', onRetry: () {}),
        ),
      ),
    );

    expect(find.text('Could not load'), findsOneWidget);
    expect(find.text(AppStrings.retryAction), findsOneWidget);
  });

  testWidgets('calls onRetry exactly once when tapped', (tester) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetryableErrorState(
            message: 'Could not load',
            onRetry: () => retries += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(retries, 1);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(retries, 2);
  });
}
