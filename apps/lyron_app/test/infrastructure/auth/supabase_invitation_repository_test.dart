// apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';

void main() {
  test('redeem returns success for a redeemed status', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{
        'status': 'redeemed',
        'organization_id': '00000000-0000-0000-0000-0000000000aa',
      },
    );
    final result = await repo.redeem('tok');
    expect(result, isA<RedeemSuccess>());
    expect(
      (result as RedeemSuccess).organizationId,
      '00000000-0000-0000-0000-0000000000aa',
    );
  });

  test('redeem maps a failure status to InvitationError', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{
        'status': 'email_mismatch',
        'organization_id': null,
      },
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.emailMismatch);
  });

  test('redeem maps rate limiting to its own error', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{
        'status': 'rate_limited',
        'organization_id': null,
      },
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.rateLimited);
  });

  test('redeem fails safely when the payload is malformed', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => <String, dynamic>{'status': 'redeemed'},
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.unknown);
  });

  test('redeem maps a connectivity failure to InvitationError.network', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => throw const SocketException('offline'),
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.network);
  });
}
