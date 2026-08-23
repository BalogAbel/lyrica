import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Shows the D5/Phase 4 (ADR-035) confirmed-purge dialog: the second,
/// independent verified-empty-membership resolution found pending local
/// work (or could not determine the amount) and needs the user's
/// confirmation before `LocalDataLifecycle.resolveVerifiedEmptyMembership`
/// proceeds to purge the local song catalog and planning data.
///
/// Mirrors `showReauthDifferentUserDialog`'s exact structure -- see that
/// file for the sibling different-user-reauth prompt this dialog is
/// deliberately shaped to match (same host, same "at most one prompt
/// pending" machinery, ADR-029/ADR-035 Gap 3).
///
/// Returns `true` if the user confirms the purge, `false` if cancelled or
/// dismissed (the safe default: stay quarantined rather than purge).
///
/// [pendingCount] of `null` means the count could not be determined; the
/// dialog then states honestly that the amount is unknown instead of
/// showing a fabricated number.
Future<bool> showMembershipQuarantinePurgeDialog(
  BuildContext context, {
  required int? pendingCount,
}) async {
  final count = pendingCount;
  final message = count == null
      ? AppStrings.membershipQuarantinePurgeUnknownPendingMessage
      : AppStrings.membershipQuarantinePurgePendingMessage(count: count);
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text(AppStrings.membershipQuarantinePurgeTitle),
          content: Text(message),
          actions: [
            TextButton(
              key: const Key('membership-quarantine-purge-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppStrings.reauthCancelAction),
            ),
            TextButton(
              key: const Key('membership-quarantine-purge-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppStrings.membershipQuarantinePurgeConfirmAction),
            ),
          ],
        ),
      ) ??
      false; // null (barrier dismiss) → safe default: stay quarantined
}
