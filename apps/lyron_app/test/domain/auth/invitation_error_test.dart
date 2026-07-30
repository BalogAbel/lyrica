// apps/lyron_app/test/domain/auth/invitation_error_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';

void main() {
  test('maps every redemption status to an InvitationError', () {
    expect(invitationErrorFromStatus('not_found'), InvitationError.notFound);
    expect(invitationErrorFromStatus('expired'), InvitationError.expired);
    expect(
      invitationErrorFromStatus('already_redeemed'),
      InvitationError.alreadyRedeemed,
    );
    expect(
      invitationErrorFromStatus('already_member'),
      InvitationError.alreadyMember,
    );
    expect(
      invitationErrorFromStatus('email_mismatch'),
      InvitationError.emailMismatch,
    );
    expect(
      invitationErrorFromStatus('rate_limited'),
      InvitationError.rateLimited,
    );
  });

  test('maps an unknown or missing status to unknown', () {
    expect(
      invitationErrorFromStatus('something_else'),
      InvitationError.unknown,
    );
    expect(invitationErrorFromStatus(null), InvitationError.unknown);
  });
}
