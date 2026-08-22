import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Persistent banner shown while the current user's local data is in D5's
/// read-only quarantine (docs/specs/2026-08-19-local-data-durability-contract.md):
/// the first verified-empty-membership resolution has recorded
/// `membershipRevokedAt` on the identity row, but nothing has been deleted
/// -- cached songs and plans stay fully readable, only new local writes are
/// refused (see `MembershipQuarantinedException` in
/// `application/storage/local_data_lifecycle.dart`).
///
/// Follows the exact shape of `ReauthBanner`
/// (`presentation/auth/reauth_banner.dart`): a plain declarative widget
/// watching a provider, no imperative host, no `ref.watch` triggering a
/// rebuild wider than its own scope. The auth controller is resolved
/// defensively for the same reason `ReauthBanner` does: this widget must not
/// crash a host screen in a test that renders it without an initialized
/// `appAuthControllerProvider`.
class MembershipQuarantineBanner extends StatelessWidget {
  const MembershipQuarantineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(appAuthControllerProvider);
    } catch (_) {
      return const SizedBox.shrink(
        key: ValueKey('membership-quarantine-banner-empty'),
      );
    }
    return const _MembershipQuarantineBannerBody();
  }
}

class _MembershipQuarantineBannerBody extends ConsumerWidget {
  const _MembershipQuarantineBannerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-read from the identity store whenever
    // membershipQuarantineRevisionProvider bumps (every identity write/
    // clear the app makes) -- see that provider's doc for why this is
    // deliberately NOT driven by AppAuthController's own ChangeNotifier.
    final membershipRevokedAt = ref.watch(membershipRevokedAtProvider).value;

    if (membershipRevokedAt == null) {
      return const SizedBox.shrink(
        key: ValueKey('membership-quarantine-banner-empty'),
      );
    }

    return Container(
      key: const ValueKey('membership-quarantine-banner'),
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.membershipQuarantineMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
