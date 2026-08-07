import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
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
      ReauthPromptResult? result;
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

      expect(result, ReauthPromptResult.confirmed);
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
    ReauthPromptResult? result;
    unawaited(
      controller
          .requestConfirmation(email: 'prior@example.com', pendingCount: 2)
          .then((value) => result = value),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reauth-different-user-cancel')));
    await tester.pumpAndSettle();

    expect(result, ReauthPromptResult.cancelled);
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
      ReauthPromptResult? result;
      unawaited(
        controller
            .requestConfirmation(email: 'prior@example.com', pendingCount: 1)
            .then((value) => result = value),
      );

      await tester.pumpAndSettle();

      // Tap outside the dialog (the barrier area).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, ReauthPromptResult.cancelled);
      expect(controller.pending, isNull);
    },
  );

  testWidgets(
    'a prompt published before host attachment appears exactly once across rebuilds',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(reauthPromptControllerProvider);
      unawaited(
        controller.requestConfirmation(
          email: 'preexisting@example.com',
          pendingCount: 5,
        ),
      );

      Widget app(String child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReauthPromptHost(child: Text(child))),
      );

      await tester.pumpWidget(app('FIRST BUILD'));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.reauthDifferentUserTitle, skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpWidget(app('SECOND BUILD'));
      await tester.pump();

      expect(
        find.text(AppStrings.reauthDifferentUserTitle, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('an obsolete dialog cannot complete a newer request', (
    tester,
  ) async {
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
    unawaited(
      controller.requestConfirmation(
        email: 'obsolete@example.com',
        pendingCount: 1,
      ),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop(false);
    controller.answer(false, requestId: controller.pending!.requestId);

    ReauthPromptResult? newerResult;
    controller
        .requestConfirmation(email: 'newer@example.com', pendingCount: 2)
        .then((value) => newerResult = value);
    final newerRequestId = controller.pending!.requestId;

    await tester.pump();

    expect(controller.pending?.requestId, newerRequestId);
    expect(newerResult, isNull);
  });

  testWidgets(
    'supersedePending closes an open dialog, leaving none on screen',
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
      ReauthPromptResult? result;
      unawaited(
        controller
            .requestConfirmation(email: 'prior@example.com', pendingCount: 3)
            .then((value) => result = value),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      controller.supersedePending();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(result, ReauthPromptResult.superseded);
    },
  );

  testWidgets('a request after a superseded prompt shows exactly one dialog', (
    tester,
  ) async {
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
    unawaited(
      controller.requestConfirmation(
        email: 'first@example.com',
        pendingCount: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    controller.supersedePending();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    ReauthPromptResult? secondResult;
    unawaited(
      controller
          .requestConfirmation(email: 'second@example.com', pendingCount: 2)
          .then((value) => secondResult = value),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        AppStrings.reauthDifferentUserPendingMessage(
          email: 'second@example.com',
          count: 2,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('reauth-different-user-confirm')));
    await tester.pumpAndSettle();
    expect(secondResult, ReauthPromptResult.confirmed);
  });

  testWidgets(
    'answering with a stale request id after supersession does not affect '
    'the new prompt',
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
      unawaited(
        controller.requestConfirmation(
          email: 'first@example.com',
          pendingCount: 1,
        ),
      );
      await tester.pumpAndSettle();
      final staleRequestId = controller.pending!.requestId;

      controller.supersedePending();
      await tester.pumpAndSettle();

      ReauthPromptResult? secondResult;
      unawaited(
        controller
            .requestConfirmation(email: 'second@example.com', pendingCount: 2)
            .then((value) => secondResult = value),
      );
      await tester.pumpAndSettle();
      final freshRequestId = controller.pending!.requestId;

      controller.answer(true, requestId: staleRequestId);
      await tester.pumpAndSettle();

      expect(secondResult, isNull);
      expect(controller.pending?.requestId, freshRequestId);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );
}
