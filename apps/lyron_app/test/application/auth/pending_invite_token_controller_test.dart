// apps/lyron_app/test/application/auth/pending_invite_token_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';

void main() {
  test('captures and clears token', () {
    final c = PendingInviteTokenController();
    expect(c.current, isNull);

    c.capture('abc');
    expect(c.current?.token, 'abc');

    c.clear();
    expect(c.current, isNull);
  });

  test('capture replaces the previous token', () {
    final c = PendingInviteTokenController();
    c.capture('one');
    c.capture('two');
    expect(c.current?.token, 'two');
  });
}
