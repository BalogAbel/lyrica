import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/current_user_ownership.dart';

void main() {
  test('allows everyone before the first observation', () {
    final ownership = CurrentUserOwnership();

    expect(ownership.userId, isNull);
    expect(ownership.allows('user-a'), isTrue);
    expect(ownership.allows('user-b'), isTrue);
  });

  test('the first observation is not a change and allows only that user', () {
    final ownership = CurrentUserOwnership();

    expect(ownership.observe('user-a'), isFalse);
    expect(ownership.userId, 'user-a');
    expect(ownership.allows('user-a'), isTrue);
    expect(ownership.allows('user-b'), isFalse);
  });

  test('observing the same user again is not a change', () {
    final ownership = CurrentUserOwnership()..observe('user-a');

    expect(ownership.observe('user-a'), isFalse);
    expect(ownership.allows('user-a'), isTrue);
  });

  test('observing a different user is a change and moves ownership', () {
    final ownership = CurrentUserOwnership()..observe('user-a');

    expect(ownership.observe('user-b'), isTrue);
    expect(ownership.allows('user-b'), isTrue);
    expect(ownership.allows('user-a'), isFalse);

    // A cancelled reauth returns to the prior user: also a change.
    expect(ownership.observe('user-a'), isTrue);
    expect(ownership.allows('user-a'), isTrue);
    expect(ownership.allows('user-b'), isFalse);
  });
}
