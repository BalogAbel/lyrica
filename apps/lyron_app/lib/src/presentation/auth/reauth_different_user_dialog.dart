import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Shows a confirmation dialog when a different user signs in while prior user
/// has pending mutations.
///
/// Returns true if user confirms wiping prior data, false if cancelled or dismissed
/// (which is the safe default to keep prior user offline-authenticated).
///
/// [pendingCount] of `null` means the count could not be determined; the
/// dialog then states honestly that the amount is unknown instead of
/// showing a fabricated number.
Future<bool> showReauthDifferentUserDialog(
  BuildContext context, {
  required String email,
  required int? pendingCount,
}) async {
  final count = pendingCount;
  final message = count == null
      ? AppStrings.reauthDifferentUserUnknownPendingMessage(email: email)
      : AppStrings.reauthDifferentUserPendingMessage(
          email: email,
          count: count,
        );
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text(AppStrings.reauthDifferentUserTitle),
          content: Text(message),
          actions: [
            TextButton(
              key: const Key('reauth-different-user-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppStrings.reauthCancelAction),
            ),
            TextButton(
              key: const Key('reauth-different-user-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppStrings.reauthConfirmWipeAction),
            ),
          ],
        ),
      ) ??
      false; // null (barrier dismiss) → safe default: keep prior data
}
