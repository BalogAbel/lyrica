import 'package:flutter/material.dart';

class SongReaderExpandedContextPanel extends StatelessWidget {
  const SongReaderExpandedContextPanel({
    super.key,
    this.previousTitle,
    this.nextTitle,
  });

  final String? previousTitle;
  final String? nextTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set context', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            _PanelRow(label: 'Previous', value: previousTitle ?? 'None'),
            const SizedBox(height: 12),
            _PanelRow(label: 'Next', value: nextTitle ?? 'None'),
          ],
        ),
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}
