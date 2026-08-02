import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/reauth_prompt_host.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  testWidgets('renders its child normally when no prompt is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ReauthPromptHost(child: Text('CHILD CONTENT')),
        ),
      ),
    );

    expect(find.text('CHILD CONTENT'), findsOneWidget);
  });

  testWidgets(
    'shows the dialog when the controller publishes a prompt, and feeds '
    'confirm back to the controller',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ReauthPromptHost(child: Text('CHILD CONTENT')),
          ),
        ),
      );

      final controller = container.read(reauthPromptControllerProvider);
      bool? result;
      unawaited(
        controller
            .requestConfirmation(email: 'prior@example.com', pendingCount: 4)
            .then((value) => result = value),
      );

      await tester.pumpAndSettle();

      expect(find.text(AppStrings.reauthDifferentUserTitle), findsOneWidget);
      expect(
        find.text(
          AppStrings.reauthDifferentUserPendingMessage(
            email: 'prior@example.com',
            count: 4,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('reauth-different-user-confirm')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(controller.pending, isNull);
    },
  );

  testWidgets('feeds cancel back to the controller as false', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ReauthPromptHost(child: Text('CHILD CONTENT')),
        ),
      ),
    );

    final controller = container.read(reauthPromptControllerProvider);
    bool? result;
    unawaited(
      controller
          .requestConfirmation(email: 'prior@example.com', pendingCount: 2)
          .then((value) => result = value),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reauth-different-user-cancel')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(controller.pending, isNull);
  });

  testWidgets(
    // The host must never turn a dismissal into a confirm -- a confirm
    // authorises deleting another user's local data, and the dialog itself
    // already pins that a barrier dismissal returns false.
    'a barrier dismissal counts as cancel, never as confirm',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ReauthPromptHost(child: Text('CHILD CONTENT')),
          ),
        ),
      );

      final controller = container.read(reauthPromptControllerProvider);
      bool? result;
      unawaited(
        controller
            .requestConfirmation(email: 'prior@example.com', pendingCount: 1)
            .then((value) => result = value),
      );

      await tester.pumpAndSettle();

      // Tap outside the dialog (the barrier area).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(controller.pending, isNull);
    },
  );
}
