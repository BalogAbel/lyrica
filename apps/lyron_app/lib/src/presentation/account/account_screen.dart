import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';

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
            onTap: () => unawaited(signOutWithPendingWorkGuard(context, ref)),
          ),
          ListTile(
            title: const Text(AppStrings.localDataEventsAction),
            onTap: () => context.push(AppRoutes.localDataEvents.path),
          ),
          ListTile(
            title: const Text(AppStrings.deleteAccountAction),
            onTap: _isDeleting
                ? null
                : () async {
                    // Captured before the first await (FB9): the screen can
                    // unmount while the dialog or the RPC runs, and the
                    // messenger belongs to the app.
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    // SO8 (docs/specs/2026-10-07-sign-out-pending-work-guard.md):
                    // delete only the user this dialog asked; a user switch
                    // while it is open (a sign-in in another tab) must not
                    // delete the new user's account.
                    final askedUserId = controller.state.currentUserId;
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
                    // The user's own Cancel or barrier dismiss: nothing to say.
                    if (confirmed != true) return;
                    // FB9: the refusal deletes nothing and says so, instead
                    // of leaving the user to wonder.
                    if (controller.state.currentUserId != askedUserId) {
                      _showMessage(
                        messenger,
                        AppStrings.deleteAccountSupersededMessage,
                      );
                      return;
                    }
                    // The screen can be replaced while the dialog is open (a
                    // router redirect). The user confirmed and is still the
                    // same user, so the deletion proceeds; only the spinner
                    // is skipped.
                    if (mounted) setState(() => _isDeleting = true);
                    try {
                      await controller.deleteAccount();
                    } catch (error, stackTrace) {
                      // FB9 (docs/specs/2026-10-12-sync-and-account-feedback.md):
                      // the message makes no claim about local data: a
                      // session lost while the RPC runs is mapped to
                      // signedOut by the controller (a documented residual).
                      // It comes first, so nothing in the report can
                      // prevent it.
                      _showMessage(
                        messenger,
                        AppStrings.deleteAccountFailedMessage,
                      );
                      // An offline user is a condition, not a defect. A
                      // static context and nothing else attached (ADR-036).
                      if (!isConnectivityFailure(error)) {
                        FlutterError.reportError(
                          FlutterErrorDetails(
                            exception: error,
                            stack: stackTrace,
                            library: 'AccountScreen',
                            context: ErrorDescription(
                              'deleting the account failed',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isDeleting = false);
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

/// Shows [message] through the app's messenger, captured by the caller before
/// its first await. A missing or unmounted messenger shows nothing rather than
/// throwing out of an error handler.
void _showMessage(ScaffoldMessengerState? messenger, String message) {
  if (messenger == null || !messenger.mounted) {
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
