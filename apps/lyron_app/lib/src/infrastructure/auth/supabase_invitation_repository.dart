// apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Redeem = Future<String> Function(String token);

class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(SupabaseClient client)
    : this.testing(
        redeem: (token) async {
          final result = await client.rpc(
            'redeem_invitation',
            params: {'p_token': token},
          );
          return result as String;
        },
      );

  @visibleForTesting
  SupabaseInvitationRepository.testing({required _Redeem redeem})
    : _redeem = redeem;

  final _Redeem _redeem;

  @override
  Future<RedeemResult> redeem(String token) async {
    try {
      final orgId = await _redeem(token);
      return RedeemSuccess(orgId);
    } on Exception catch (e) {
      final message = e.toString();
      InvitationError mapped;
      if (message.contains('invitation_not_found')) {
        mapped = InvitationError.notFound;
      } else if (message.contains('invitation_expired')) {
        mapped = InvitationError.expired;
      } else if (message.contains('invitation_already_redeemed')) {
        mapped = InvitationError.alreadyRedeemed;
      } else if (message.contains('already_member')) {
        mapped = InvitationError.alreadyMember;
      } else {
        mapped = InvitationError.unknown;
      }
      return RedeemFailure(mapped);
    }
  }
}
