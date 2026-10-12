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
///
/// FB7 (docs/specs/2026-10-12-sync-and-account-feedback.md): the one place
/// that tells the user what happened. A refused, failed or superseded
/// sign-out shows one snackbar through the app's [ScaffoldMessenger]; the
/// user's own Cancel, a completed sign-out and a double tap show nothing. The
/// callers ignore the outcome and do not change.
Future<SignOutOutcome> signOutWithPendingWorkGuard(
  BuildContext context,
  WidgetRef ref,
) async {
  // Captured before the first await (SO1): the screen that took the tap can
  // unmount while the dialog or the sequence runs, but the messenger belongs
  // to the app and survives it.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final outcome = await _run(context, ref);
  final message = signOutFeedbackMessage(outcome);
  if (message != null && messenger != null && messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  return outcome;
}

/// FB7: the snackbar text for [outcome], or null when the outcome needs none
/// (`signedOut`: the screen changes; `cancelled`: the user's own choice;
/// `alreadyRunning`: a double tap, the first tap's feedback is on its way).
String? signOutFeedbackMessage(SignOutOutcome outcome) => switch (outcome) {
  SignOutOutcome.signedOut => null,
  SignOutOutcome.cancelled => null,
  SignOutOutcome.alreadyRunning => null,
  SignOutOutcome.blockedByImport => AppStrings.signOutBlockedByImportMessage,
  SignOutOutcome.failed => AppStrings.signOutFailedMessage,
  SignOutOutcome.superseded => AppStrings.signOutSupersededMessage,
};

Future<SignOutOutcome> _run(BuildContext context, WidgetRef ref) {
  // SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): every
  // sign-out control inherits the rule. A running import writes pending work
  // behind the count.
  if (isImportRunning(ref.read(chordProImportControllerProvider))) {
    return Future.value(SignOutOutcome.blockedByImport);
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
