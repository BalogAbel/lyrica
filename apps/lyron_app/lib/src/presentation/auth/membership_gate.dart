import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/redeem_progress_screen.dart';

class MembershipGate extends ConsumerWidget {
  const MembershipGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(activeMembershipControllerProvider).last;
    final pending = ref.watch(pendingInviteTokenControllerProvider).current;

    return switch (membership) {
      ActiveOrganizationSelected() => child,
      ActiveOrganizationVerifiedEmpty() => pending != null
          ? const RedeemProgressScreen()
          : const InviteRequiredScreen(),
      ActiveOrganizationUnknownConnectivityFailure() ||
      ActiveOrganizationUnknownNonConnectivityFailure() => child,
    };
  }
}
