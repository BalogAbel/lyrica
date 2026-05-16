// apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';

void main() {
  test('redeem returns success when RPC returns an organization id', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => '00000000-0000-0000-0000-0000000000aa',
    );
    final result = await repo.redeem('tok');
    expect(result, isA<RedeemSuccess>());
    expect((result as RedeemSuccess).organizationId,
        '00000000-0000-0000-0000-0000000000aa');
  });

  test('redeem maps SQL error messages to InvitationError', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async {
        throw Exception('invitation_expired');
      },
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.expired);
  });
}
