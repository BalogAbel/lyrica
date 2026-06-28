import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class ReauthBanner extends ConsumerWidget {
  const ReauthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      appAuthControllerProvider.select((c) => c.state.status),
    );

    if (status != AppAuthStatus.sessionExpired) {
      return const SizedBox.shrink(key: ValueKey('reauth-banner-empty'));
    }

    return Container(
      key: const ValueKey('reauth-banner'),
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.reauthRequiredMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('reauth-banner-action'),
            onPressed: () {
              final from = GoRouterState.of(context).uri.toString();
              context.go(
                Uri(
                  path: AppRoutes.signIn.path,
                  queryParameters: {'from': from},
                ).toString(),
              );
            },
            child: const Text(AppStrings.reauthSignInAction),
          ),
        ],
      ),
    );
  }
}
