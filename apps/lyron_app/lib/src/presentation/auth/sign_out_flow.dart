import 'dart:async';

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
///
/// FB16 (docs/specs/2026-10-12-sync-and-account-feedback.md): a dialog route
/// whose navigator is torn down never completes its future. The router is
/// rebuilt on every auth state change, so a user switch or a session loss
/// while this dialog is open would leave the caller (the sign-out command,
/// with its lock held) waiting for good. A dialog that is disposed without an
/// answer therefore answers `false` itself and calls [onLostUnanswered]. A
/// dialog the user answered (Cancel, confirm, a barrier dismiss, back) is
/// never reported: the route completes its future when it is popped, before
/// its overlay entries, and so this dialog, are disposed.
Future<bool> showUnsyncedSignOutDialog(
  BuildContext context, {
  required int? pendingCount,
  VoidCallback? onLostUnanswered,
}) async {
  final count = pendingCount;
  final message = count == null
      ? AppStrings.unsyncedSignOutUnknownPendingMessage
      : AppStrings.unsyncedSignOutPendingMessage(count: count);
  final lost = Completer<bool>();
  var answered = false;
  final answer =
      showDialog<bool>(
        context: context,
        builder: (context) => _LostDialogWatcher(
          isAnswered: () => answered,
          onLost: () {
            if (!lost.isCompleted) {
              lost.complete(false);
              onLostUnanswered?.call();
            }
          },
          child: AlertDialog(
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
        ),
      ).then((value) {
        answered = true;
        return value ?? false; // barrier dismiss: delete nothing
      });
  return Future.any([answer, lost.future]);
}

/// FB16: reports a dialog that is disposed before its route's future
/// completed, which only happens when the navigator under it was torn down.
class _LostDialogWatcher extends StatefulWidget {
  const _LostDialogWatcher({
    required this.isAnswered,
    required this.onLost,
    required this.child,
  });

  final bool Function() isAnswered;
  final VoidCallback onLost;
  final Widget child;

  @override
  State<_LostDialogWatcher> createState() => _LostDialogWatcherState();
}

class _LostDialogWatcherState extends State<_LostDialogWatcher> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    if (!widget.isAnswered()) {
      widget.onLost();
    }
    super.dispose();
  }
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
/// user's own Cancel, a completed sign-out and a double tap show nothing. A
/// discard dialog lost unanswered (FB16) is `failed`. The callers ignore the
/// outcome and do not change.
Future<SignOutOutcome> signOutWithPendingWorkGuard(
  BuildContext context,
  WidgetRef ref,
) async {
  // Captured before the first await (SO1): the screen that took the tap can
  // unmount while the dialog or the sequence runs, but the messenger belongs
  // to the app and survives it.
  final messenger = ScaffoldMessenger.maybeOf(context);
  var dialogLost = false;
  final ran = await _run(context, ref, onDialogLost: () => dialogLost = true);
  // FB16: a discard dialog that was torn down unanswered reads as "not
  // confirmed" to the command, which releases its lock and returns
  // `cancelled`. The user did not cancel; the sign-out did not complete.
  final outcome = ran == SignOutOutcome.cancelled && dialogLost
      ? SignOutOutcome.failed
      : ran;
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

Future<SignOutOutcome> _run(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onDialogLost,
}) {
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
      return showUnsyncedSignOutDialog(
        context,
        pendingCount: pendingCount,
        onLostUnanswered: onDialogLost,
      );
    },
  );
}
