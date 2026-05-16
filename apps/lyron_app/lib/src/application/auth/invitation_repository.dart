// apps/lyron_app/lib/src/application/auth/invitation_repository.dart
import 'package:lyron_app/src/domain/auth/redeem_result.dart';

abstract interface class InvitationRepository {
  Future<RedeemResult> redeem(String token);
}
