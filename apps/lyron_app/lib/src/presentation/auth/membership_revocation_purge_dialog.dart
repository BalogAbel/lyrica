import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Shows the D5.4 confirmation dialog before a membership-revocation purge
/// runs with local work pending
/// (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035 Phase
/// 4). Mirrors `showReauthDifferentUserDialog`'s shape deliberately -- same
/// host (`ReauthPromptHost`), same honest-null-count handling, same
/// barrier-dismissal-is-cancel default.
///
/// Returns `true` if the user confirms the purge, `false` if cancelled or
/// dismissed (the safe default: nothing is deleted).
///
/// [pendingCount] of `null` means the count could not be determined; the
/// dialog then states honestly that the amount is unknown instead of
/// showing a fabricated number.
Future<bool> showMembershipRevocationPurgeDialog(
  BuildContext context, {
  required int? pendingCount,
}) async {
  final count = pendingCount;
  final message = count == null
      ? AppStrings.membershipRevocationPurgeUnknownPendingMessage
      : AppStrings.membershipRevocationPurgePendingMessage(count: count);
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text(AppStrings.membershipRevocationPurgeTitle),
          content: Text(message),
          actions: [
            TextButton(
              key: const Key('membership-revocation-purge-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppStrings.membershipRevocationPurgeCancelAction),
            ),
            TextButton(
              key: const Key('membership-revocation-purge-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppStrings.membershipRevocationPurgeConfirmAction),
            ),
          ],
        ),
      ) ??
      false; // null (barrier dismiss) → safe default: delete nothing
}
