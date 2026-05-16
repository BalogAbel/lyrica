import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.accountTitle)),
      body: ListView(
        children: [
          ListTile(
            title: const Text(AppStrings.signOutAction),
            onTap: () => controller.signOut(),
          ),
          ListTile(
            title: const Text(AppStrings.deleteAccountAction),
            onTap: _isDeleting
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text(AppStrings.deleteAccountConfirmTitle),
                        content: const Text(
                          AppStrings.deleteAccountConfirmMessage,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(AppStrings.cancelAction),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text(
                              AppStrings.deleteAccountConfirmAction,
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      setState(() => _isDeleting = true);
                      try {
                        await controller.deleteAccount();
                      } finally {
                        if (mounted) setState(() => _isDeleting = false);
                      }
                    }
                  },
            trailing: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
