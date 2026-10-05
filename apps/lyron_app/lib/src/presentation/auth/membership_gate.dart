import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/redeem_progress_screen.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Renders the SG1 decision (docs/specs/2026-10-05-offline-first-startup
/// -gate.md). The decision reads local state only, so this widget never
/// waits for the network before showing the home route.
class MembershipGate extends ConsumerWidget {
  const MembershipGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(activeMembershipControllerProvider);
    final pending = ref.watch(pendingInviteTokenControllerProvider).current;

    return switch (membership.viewFor(hasPendingInvite: pending != null)) {
      MembershipGateView.home => child,
      MembershipGateView.redeem => const RedeemProgressScreen(),
      MembershipGateView.inviteRequired => const InviteRequiredScreen(),
      // Text only, like the bootstrap screen: an indeterminate spinner would
      // keep pumpAndSettle from ever settling in widget tests.
      MembershipGateView.resolving => const Scaffold(
        body: SafeArea(
          child: Center(child: Text(AppStrings.membershipResolvingMessage)),
        ),
      ),
      MembershipGateView.connectivityFailure => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(AppStrings.membershipConnectivityFailureMessage),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('membership-gate-retry'),
                  onPressed: () => unawaited(_retry(ref)),
                  child: const Text(AppStrings.retryAction),
                ),
              ],
            ),
          ),
        ),
      ),
      MembershipGateView.nonConnectivityFailure => const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(AppStrings.membershipNonConnectivityFailureMessage),
          ),
        ),
      ),
    };
  }

  Future<void> _retry(WidgetRef ref) async {
    final controller = ref.read(activeMembershipControllerProvider);
    final reader = ref.read(membershipResolutionProvider);
    final userId = controller.currentUserId;
    if (userId != null) {
      controller.beginResolution(userId: userId);
    }
    final resolution = await reader();
    controller.update(resolution, userId: userId);
  }
}
