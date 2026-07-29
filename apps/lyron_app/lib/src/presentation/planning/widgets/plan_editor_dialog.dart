import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/planning/widgets/scheduled_for_field.dart';
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
  late DateTime? _scheduledFor = widget.initialScheduledFor;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
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
            ScheduledForField(
              value: _scheduledFor,
              onChanged: (value) => setState(() => _scheduledFor = value),
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
            Navigator.of(context).pop(
              PlanEditDraft(
                planId: widget.planId,
                name: _nameController.text.trim(),
                description: _normalizeText(_descriptionController.text),
                scheduledFor: _scheduledFor,
              ),
            );
          },
          child: const Text(AppStrings.planSaveAction),
        ),
      ],
    );
  }
}

String? _normalizeText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
