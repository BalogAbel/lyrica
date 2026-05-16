// apps/lyron_app/test/application/auth/redeem_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';

class _FakeInv implements InvitationRepository {
  _FakeInv(this._result);
  final RedeemResult _result;
  String? lastToken;

  @override
  Future<RedeemResult> redeem(String token) async {
    lastToken = token;
    return _result;
  }
}

void main() {
  test('success transitions idle -> inFlight -> success', () async {
    final repo = _FakeInv(const RedeemSuccess('org-1'));
    final c = RedeemController(repo);
    final transitions = <RedeemState>[];
    c.addListener(() => transitions.add(c.state));

    await c.redeem('tok');

    expect(c.state, isA<RedeemStateSuccess>());
    expect((c.state as RedeemStateSuccess).organizationId, 'org-1');
    expect(transitions.length, greaterThanOrEqualTo(2));
  });

  test('failure surfaces invitation error', () async {
    final repo = _FakeInv(const RedeemFailure(InvitationError.expired));
    final c = RedeemController(repo);

    await c.redeem('tok');

    expect((c.state as RedeemStateFailure).error, InvitationError.expired);
  });
}
