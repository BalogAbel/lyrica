// apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RedeemFn = Future<Map<String, dynamic>> Function(String token);

class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(SupabaseClient client)
    : this.testing(
        redeem: (token) async {
          final result = await client.rpc(
            'redeem_invitation',
            params: {'p_token': token},
          );
          return (result as Map).cast<String, dynamic>();
        },
      );

  @visibleForTesting
  SupabaseInvitationRepository.testing({required this._redeem});

  final RedeemFn _redeem;

  @override
  Future<RedeemResult> redeem(String token) async {
    try {
      final payload = await _redeem(token);
      final status = payload['status'];
      if (status == 'redeemed') {
        final organizationId = payload['organization_id'];
        if (organizationId is String && organizationId.isNotEmpty) {
          return RedeemSuccess(organizationId);
        }
        // A redeemed status without an organization id is not actionable.
        return const RedeemFailure(InvitationError.unknown);
      }
      return RedeemFailure(
        invitationErrorFromStatus(status is String ? status : null),
      );
    } on PostgrestException {
      // Only the unauthenticated guard still raises, and the client never
      // reaches redemption without a session.
      return const RedeemFailure(InvitationError.unknown);
    } catch (e) {
      return RedeemFailure(
        isConnectivityFailure(e)
            ? InvitationError.network
            : InvitationError.unknown,
      );
    }
  }
}
