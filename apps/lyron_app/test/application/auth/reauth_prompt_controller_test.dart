import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';

void main() {
  test('requesting a confirmation publishes a pending prompt', () {
    final controller = ReauthPromptController();
    expect(controller.pending, isNull);

    unawaited(
      controller.requestConfirmation(
        email: 'prior@example.com',
        pendingCount: 4,
      ),
    );

    expect(
      (controller.pending as ReauthDifferentUserPrompt?)?.email,
      'prior@example.com',
    );
    expect((controller.pending as ReauthDifferentUserPrompt?)?.pendingCount, 4);
    expect(controller.pending?.requestId, isNotNull);
  });

  test('requesting a confirmation with an unknown (null) pending count '
      'publishes it as unknown, not as a number', () {
    final controller = ReauthPromptController();

    unawaited(
      controller.requestConfirmation(
        email: 'prior@example.com',
        pendingCount: null,
      ),
    );

    expect(
      (controller.pending as ReauthDifferentUserPrompt?)?.email,
      'prior@example.com',
    );
    expect(
      (controller.pending as ReauthDifferentUserPrompt?)?.pendingCount,
      isNull,
    );
  });

  test('answer completes the returned future and clears the prompt', () async {
    final controller = ReauthPromptController();
    final future = controller.requestConfirmation(
      email: 'prior@example.com',
      pendingCount: 2,
    );

    final requestId = controller.pending!.requestId;
    controller.answer(true, requestId: requestId);

    expect(await future, ReauthPromptResult.confirmed);
    expect(controller.pending, isNull);
  });

  test('answer(false) completes the future as cancelled', () async {
    final controller = ReauthPromptController();
    final future = controller.requestConfirmation(
      email: 'prior@example.com',
      pendingCount: 1,
    );

    controller.answer(false, requestId: controller.pending!.requestId);

    expect(await future, ReauthPromptResult.cancelled);
  });

  test(
    'successive prompts receive distinct stable request identities',
    () async {
      final controller = ReauthPromptController();
      final first = controller.requestConfirmation(
        email: 'first@example.com',
        pendingCount: 1,
      );
      final firstId = controller.pending!.requestId;

      expect(controller.pending!.requestId, firstId);
      controller.answer(false, requestId: firstId);
      expect(await first, ReauthPromptResult.cancelled);

      final second = controller.requestConfirmation(
        email: 'second@example.com',
        pendingCount: 2,
      );
      final secondId = controller.pending!.requestId;

      expect(secondId, isNot(firstId));
      expect(controller.pending!.requestId, secondId);
      controller.answer(true, requestId: secondId);
      expect(await second, ReauthPromptResult.confirmed);
    },
  );

  test('supersedePending synchronously clears the old request', () {
    final controller = ReauthPromptController();
    unawaited(
      controller.requestConfirmation(email: 'old@example.com', pendingCount: 3),
    );

    controller.supersedePending();

    expect(controller.pending, isNull);
  });

  test('supersedePending completes the old request as superseded', () async {
    final controller = ReauthPromptController();
    ReauthPromptResult? result;
    controller
        .requestConfirmation(email: 'old@example.com', pendingCount: 3)
        .then((value) => result = value);

    controller.supersedePending();

    await Future<void>.delayed(Duration.zero);
    expect(result, ReauthPromptResult.superseded);
  });

  test('an obsolete request identity cannot answer a newer prompt', () async {
    final controller = ReauthPromptController();
    final first = controller.requestConfirmation(
      email: 'old@example.com',
      pendingCount: 3,
    );
    final oldRequestId = controller.pending!.requestId;
    controller.answer(false, requestId: oldRequestId);
    await first;

    ReauthPromptResult? newerResult;
    controller
        .requestConfirmation(email: 'new@example.com', pendingCount: 1)
        .then((value) => newerResult = value);
    final newRequestId = controller.pending!.requestId;

    controller.answer(true, requestId: oldRequestId);

    expect(controller.pending?.requestId, newRequestId);
    expect(newerResult, isNull);
  });

  test(
    // D2/Task 4: two prompts cannot be pending at once. This slice rejects
    // the second request rather than queueing it -- resolveReauth only ever
    // awaits one confirmDifferentUser call per signedIn transition before
    // doing anything else, so a second concurrent request means two
    // different-user resolutions racing, which never happens by design.
    // Throwing turns that into a loud bug instead of silently queueing or
    // dropping a confirmation that guards data deletion.
    'a second requestConfirmation while one is pending throws, '
    'leaving the first prompt untouched',
    () async {
      final controller = ReauthPromptController();
      final first = controller.requestConfirmation(
        email: 'prior@example.com',
        pendingCount: 3,
      );

      expect(
        () => controller.requestConfirmation(
          email: 'someone-else@example.com',
          pendingCount: 9,
        ),
        throwsStateError,
      );

      expect(
        (controller.pending as ReauthDifferentUserPrompt?)?.email,
        'prior@example.com',
      );
      expect(
        (controller.pending as ReauthDifferentUserPrompt?)?.pendingCount,
        3,
      );

      controller.answer(true, requestId: controller.pending!.requestId);
      expect(await first, ReauthPromptResult.confirmed);
    },
  );

  test('dispose completes a pending request as superseded instead of leaving '
      'it hanging forever (N5, PR #64 review)', () async {
    final controller = ReauthPromptController();
    final future = controller.requestConfirmation(
      email: 'prior@example.com',
      pendingCount: 2,
    );

    controller.dispose();

    await expectLater(future, completion(ReauthPromptResult.superseded));
    expect(controller.pending, isNull);
  });

  test('notifies listeners on request and on answer', () {
    final controller = ReauthPromptController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    unawaited(
      controller.requestConfirmation(email: 'a@example.com', pendingCount: 1),
    );
    expect(notifications, 1);

    controller.answer(true, requestId: controller.pending!.requestId);
    expect(notifications, 2);
  });
}
