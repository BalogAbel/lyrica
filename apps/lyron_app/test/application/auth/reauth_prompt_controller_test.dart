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

    expect(controller.pending?.email, 'prior@example.com');
    expect(controller.pending?.pendingCount, 4);
  });

  test('answer completes the returned future and clears the prompt', () async {
    final controller = ReauthPromptController();
    final future = controller.requestConfirmation(
      email: 'prior@example.com',
      pendingCount: 2,
    );

    controller.answer(true);

    expect(await future, isTrue);
    expect(controller.pending, isNull);
  });

  test('answer(false) completes the future with false', () async {
    final controller = ReauthPromptController();
    final future = controller.requestConfirmation(
      email: 'prior@example.com',
      pendingCount: 1,
    );

    controller.answer(false);

    expect(await future, isFalse);
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

      expect(controller.pending?.email, 'prior@example.com');
      expect(controller.pending?.pendingCount, 3);

      controller.answer(true);
      expect(await first, isTrue);
    },
  );

  test('notifies listeners on request and on answer', () {
    final controller = ReauthPromptController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    unawaited(
      controller.requestConfirmation(email: 'a@example.com', pendingCount: 1),
    );
    expect(notifications, 1);

    controller.answer(true);
    expect(notifications, 2);
  });
}
