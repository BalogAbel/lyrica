import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// SO3 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the sign-out
/// warning. Shaped like `showMembershipRevocationPurgeDialog`: a known count
/// is named, `null` says the count is unknown (never a fabricated number),
/// and a barrier dismiss is Cancel.
Future<bool> showUnsyncedSignOutDialog(
  BuildContext context, {
  required int? pendingCount,
}) async {
  final count = pendingCount;
  final message = count == null
      ? AppStrings.unsyncedSignOutUnknownPendingMessage
      : AppStrings.unsyncedSignOutPendingMessage(count: count);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStrings.unsyncedSignOutTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.songCancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.unsyncedSignOutConfirmAction),
            ),
          ],
        ),
      ) ??
      false; // barrier dismiss: delete nothing
}

/// SO1: what every sign-out control calls. Reads the command before any
/// await; the command outlives this widget (the router may replace the
/// screen while the dialog is open), and an unmounted context answers
/// "not confirmed". The command reports its own errors, so the returned
/// future never fails.
Future<SignOutOutcome> signOutWithPendingWorkGuard(
  BuildContext context,
  WidgetRef ref,
) {
  // SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): every
  // sign-out control inherits the rule. A running import writes pending work
  // behind the count.
  if (isImportRunning(ref.read(chordProImportControllerProvider))) {
    return Future.value(SignOutOutcome.cancelled);
  }
  final command = ref.read(signOutCommandProvider);
  return command.run(
    confirmDiscard: (pendingCount) async {
      if (!context.mounted) {
        return false;
      }
      return showUnsyncedSignOutDialog(context, pendingCount: pendingCount);
    },
  );
}
