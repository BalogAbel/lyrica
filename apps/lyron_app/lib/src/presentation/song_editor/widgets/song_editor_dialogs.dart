import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<void> showSongEditorConflictDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStrings.songConflictTitle),
      content: const Text(AppStrings.songConflictMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songCancelAction),
        ),
      ],
    ),
  );
}

Future<bool> confirmDiscardSongEditorChanges(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStrings.songEditorDiscardChangesTitle),
          content: const Text(AppStrings.songEditorDiscardChangesMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.songEditorKeepEditingAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.songEditorDiscardAction),
            ),
          ],
        ),
      ) ??
      false;
}
