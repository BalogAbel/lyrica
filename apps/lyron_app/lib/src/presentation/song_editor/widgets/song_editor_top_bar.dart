import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';

class SongEditorTopBar extends ConsumerWidget {
  const SongEditorTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.canCancel,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
    required this.organizationId,
  });

  final String title;
  final VoidCallback onBack;
  final bool canCancel;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 840;
        final titleColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('song-editor-back-button'),
                  onPressed: onBack,
                  icon: const BackButtonIcon(),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            FilledButton.tonal(
              onPressed: canCancel ? onCancel : null,
              child: const Text('Cancel'),
            ),
            IfCapability(
              capability: Capability.editSongs,
              organizationId: organizationId,
              child: FilledButton(
                onPressed: canSave ? onSave : null,
                child: const Text('Save'),
              ),
            ),
          ],
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleColumn, const SizedBox(height: 12), actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleColumn),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [actions],
            ),
          ],
        );
      },
    );
  }
}

class SongEditorStatusBanner extends StatelessWidget {
  const SongEditorStatusBanner({super.key, required this.diagnosticCount});

  final int diagnosticCount;

  @override
  Widget build(BuildContext context) {
    if (diagnosticCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Source parsed with $diagnosticCount recoverable warning(s).',
            ),
          ),
        ],
      ),
    );
  }
}
