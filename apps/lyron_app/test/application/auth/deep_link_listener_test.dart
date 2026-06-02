// apps/lyron_app/test/application/auth/deep_link_listener_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/deep_link_listener.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';

void main() {
  test('captures token from /invite?token=X', () async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final pending = PendingInviteTokenController();
    final listener = DeepLinkListener(
      stream: controller.stream,
      pendingTokens: pending,
    );

    listener.start();
    controller.add(Uri.parse('https://app.lyron.example/invite?token=ABC'));

    await Future<void>.delayed(Duration.zero);

    expect(pending.current?.token, 'ABC');

    await listener.dispose();
  });

  test('ignores unrelated paths', () async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final pending = PendingInviteTokenController();
    final listener = DeepLinkListener(
      stream: controller.stream,
      pendingTokens: pending,
    );
    listener.start();
    controller.add(Uri.parse('https://app.lyron.example/other'));
    await Future<void>.delayed(Duration.zero);
    expect(pending.current, isNull);
    await listener.dispose();
  });

  test('captures token from https://lyron.pages.dev/invite', () async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final pending = PendingInviteTokenController();
    final listener = DeepLinkListener(
      stream: controller.stream,
      pendingTokens: pending,
    );

    listener.start();
    controller.add(Uri.parse('https://lyron.pages.dev/invite?token=PAGESDEV'));

    await Future<void>.delayed(Duration.zero);

    expect(pending.current?.token, 'PAGESDEV');

    await listener.dispose();
  });
}
