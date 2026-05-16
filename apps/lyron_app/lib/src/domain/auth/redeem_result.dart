import 'package:lyron_app/src/domain/auth/invitation_error.dart';

sealed class RedeemResult {
  const RedeemResult();
}

class RedeemSuccess extends RedeemResult {
  const RedeemSuccess(this.organizationId);
  final String organizationId;
}

class RedeemFailure extends RedeemResult {
  const RedeemFailure(this.error);
  final InvitationError error;
}
