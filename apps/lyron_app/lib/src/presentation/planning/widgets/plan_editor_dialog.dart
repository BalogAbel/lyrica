import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanEditorDialog extends ConsumerStatefulWidget {
  const PlanEditorDialog({
    super.key,
    required this.planId,
    required this.initialName,
    this.initialDescription,
    this.initialScheduledFor,
  });

  final String planId;
  final String initialName;
  final String? initialDescription;
  final DateTime? initialScheduledFor;

  @override
  ConsumerState<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends ConsumerState<PlanEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription ?? '');
  late final TextEditingController _scheduledForController =
      TextEditingController(
        text: widget.initialScheduledFor?.toUtc().toIso8601String() ?? '',
      );
  String? _scheduledForError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _scheduledForController.dispose();
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

    return AlertDialog(
      title: const Text(AppStrings.planEditorTitleEdit),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('plan-editor-name'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: AppStrings.planNameLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('plan-editor-description'),
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: AppStrings.planDescriptionLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('plan-editor-scheduled-for'),
              controller: _scheduledForController,
              decoration: InputDecoration(
                labelText: AppStrings.planScheduledForLabel,
                errorText: _scheduledForError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songCancelAction),
        ),
        FilledButton(
          onPressed: () {
            final scheduledFor = _tryParseScheduledFor();
            if (_scheduledForController.text.trim().isNotEmpty &&
                scheduledFor == null) {
              setState(() {
                _scheduledForError = AppStrings.planScheduledForInvalidMessage;
              });
              return;
            }
            Navigator.of(context).pop(
              PlanEditDraft(
                planId: widget.planId,
                name: _nameController.text.trim(),
                description: _normalizeText(_descriptionController.text),
                scheduledFor: scheduledFor,
              ),
            );
          },
          child: const Text(AppStrings.planSaveAction),
        ),
      ],
    );
  }

  DateTime? _tryParseScheduledFor() {
    try {
      return _parseOptionalDateTime(_scheduledForController.text);
    } on FormatException {
      return null;
    }
  }
}

String? _normalizeText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _parseOptionalDateTime(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }

  return DateTime.parse(normalized).toUtc();
}
