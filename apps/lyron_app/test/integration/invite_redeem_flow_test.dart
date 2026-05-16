// apps/lyron_app/test/integration/invite_redeem_flow_test.dart
// Widget integration test — no real Supabase connection.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/presentation/auth/membership_gate.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

// Stub InvitationRepository that returns success
class _SuccessRepo implements InvitationRepository {
  @override
  Future<RedeemResult> redeem(String token) async =>
      const RedeemSuccess('org-id-123');
}

// Stub InvitationRepository that returns failure
class _FailRepo implements InvitationRepository {
  @override
  Future<RedeemResult> redeem(String token) async =>
      const RedeemFailure(InvitationError.notFound);
}

void main() {
  testWidgets(
    'MembershipGate shows RedeemProgressScreen when verifiedEmpty and token pending',
    (tester) async {
      final pending = PendingInviteTokenController();
      final membership = ActiveMembershipController();
      pending.capture('test-token-abc');
      membership.update(const ActiveOrganizationResolution.verifiedEmpty());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingInviteTokenControllerProvider.overrideWith((_) => pending),
            activeMembershipControllerProvider.overrideWith((_) => membership),
            redeemControllerProvider.overrideWith(
              (_) => RedeemController(_SuccessRepo()),
            ),
          ],
          child: const MaterialApp(home: MembershipGate(child: Text('Home'))),
        ),
      );

      // With pending token + verifiedEmpty → shows RedeemProgressScreen (spinner)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );

  testWidgets(
    'MembershipGate shows InviteRequiredScreen when verifiedEmpty and no token',
    (tester) async {
      final pending = PendingInviteTokenController();
      final membership = ActiveMembershipController();
      // No capture — pending.current is null
      membership.update(const ActiveOrganizationResolution.verifiedEmpty());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingInviteTokenControllerProvider.overrideWith((_) => pending),
            activeMembershipControllerProvider.overrideWith((_) => membership),
          ],
          child: const MaterialApp(home: MembershipGate(child: Text('Home'))),
        ),
      );

      expect(find.text(AppStrings.inviteRequiredTitle), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );

  testWidgets('MembershipGate shows child when membership is selected', (
    tester,
  ) async {
    final pending = PendingInviteTokenController();
    final membership = ActiveMembershipController();
    membership.update(
      const ActiveOrganizationResolution.selected('org-id-123'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingInviteTokenControllerProvider.overrideWith((_) => pending),
          activeMembershipControllerProvider.overrideWith((_) => membership),
        ],
        child: const MaterialApp(home: MembershipGate(child: Text('Home'))),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
  });
}
