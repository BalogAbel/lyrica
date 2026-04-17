import 'package:flutter/material.dart';

class SongReaderExpandedContextPanel extends StatelessWidget {
  const SongReaderExpandedContextPanel({
    super.key,
    this.previousTitle,
    this.nextTitle,
    this.onPreviousTap,
    this.onNextTap,
  });

  static const previousSegmentKey = Key(
    'song-reader-expanded-context-previous-segment',
  );
  static const nextSegmentKey = Key(
    'song-reader-expanded-context-next-segment',
  );

  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;

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
            _PanelRow(
              key: previousSegmentKey,
              label: 'Previous',
              value: previousTitle ?? 'None',
              onTap: onPreviousTap,
            ),
            const SizedBox(height: 12),
            _PanelRow(
              key: nextSegmentKey,
              label: 'Next',
              value: nextTitle ?? 'None',
              onTap: onNextTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
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
          ),
        ),
      ),
    );
  }
}
