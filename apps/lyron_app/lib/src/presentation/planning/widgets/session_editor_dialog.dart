import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SessionEditorDialog extends ConsumerStatefulWidget {
  const SessionEditorDialog({super.key, this.initialName = ''});

  final String initialName;

  @override
  ConsumerState<SessionEditorDialog> createState() =>
      _SessionEditorDialogState();
}

class _SessionEditorDialogState extends ConsumerState<SessionEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activePlanningContextProvider, (previous, next) {
      if (!mounted || previous == next) {
        return;
      }

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });

    final isRename = widget.initialName.isNotEmpty;

    return AlertDialog(
      title: Text(
        isRename
            ? AppStrings.sessionEditorTitleRename
            : AppStrings.sessionEditorTitleCreate,
      ),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('session-editor-name'),
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: AppStrings.sessionNameLabel,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songCancelAction),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_nameController.text.trim()),
          child: const Text(AppStrings.planSaveAction),
        ),
      ],
    );
  }
}
