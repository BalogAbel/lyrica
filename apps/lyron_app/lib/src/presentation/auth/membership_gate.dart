import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/reauth_banner.dart';
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
      MembershipGateView.connectivityFailure => _FailureView(
        message: AppStrings.membershipConnectivityFailureMessage,
        onRetry: () => unawaited(_retry(ref)),
        onSignIn: membership.isSessionExpired
            ? () => goToReauthSignIn(context)
            : null,
      ),
      MembershipGateView.nonConnectivityFailure => _FailureView(
        message: AppStrings.membershipNonConnectivityFailureMessage,
        onSignIn: membership.isSessionExpired
            ? () => goToReauthSignIn(context)
            : null,
      ),
    };
  }

  Future<void> _retry(WidgetRef ref) => ref.read(membershipRetryProvider)();
}

/// A failure screen. With no live session (sessionExpired) the app's
/// re-auth banner sits behind this gate, so the way to a session has to be
/// here: [onSignIn] is non-null only then.
class _FailureView extends StatelessWidget {
  const _FailureView({required this.message, this.onRetry, this.onSignIn});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('membership-gate-retry'),
                  onPressed: onRetry,
                  child: const Text(AppStrings.retryAction),
                ),
              ],
              if (onSignIn != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey('membership-gate-sign-in'),
                  onPressed: onSignIn,
                  child: const Text(AppStrings.reauthSignInAction),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
