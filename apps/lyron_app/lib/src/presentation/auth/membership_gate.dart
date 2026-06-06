import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/redeem_progress_screen.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class MembershipGate extends ConsumerWidget {
  const MembershipGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(activeMembershipControllerProvider).last;
    final pending = ref.watch(pendingInviteTokenControllerProvider).current;

    return switch (membership) {
      ActiveOrganizationSelected() => child,
      ActiveOrganizationVerifiedEmpty() =>
        pending != null
            ? const RedeemProgressScreen()
            : const InviteRequiredScreen(),
      ActiveOrganizationUnknownConnectivityFailure() => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(AppStrings.membershipConnectivityFailureMessage),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final reader = ref.read(membershipResolutionProvider);
                    final resolution = await reader();
                    ref
                        .read(activeMembershipControllerProvider)
                        .update(resolution);
                  },
                  child: const Text(AppStrings.retryAction),
                ),
              ],
            ),
          ),
        ),
      ),
      ActiveOrganizationUnknownNonConnectivityFailure() => const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(AppStrings.membershipNonConnectivityFailureMessage),
          ),
        ),
      ),
    };
  }
}
