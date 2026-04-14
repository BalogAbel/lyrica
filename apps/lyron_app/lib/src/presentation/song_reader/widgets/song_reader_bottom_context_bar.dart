import 'package:flutter/material.dart';

class SongReaderBottomContextBar extends StatelessWidget {
  const SongReaderBottomContextBar({
    super.key,
    required this.currentTitle,
    this.previousTitle,
    this.nextTitle,
  });

  final String currentTitle;
  final String? previousTitle;
  final String? nextTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _NeighborLabel(
                alignment: CrossAxisAlignment.start,
                label: 'Previous',
                title: previousTitle,
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Current',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _NeighborLabel(
                alignment: CrossAxisAlignment.end,
                label: 'Next',
                title: nextTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeighborLabel extends StatelessWidget {
  const _NeighborLabel({
    required this.alignment,
    required this.label,
    required this.title,
  });

  final CrossAxisAlignment alignment;
  final String label;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTitle = title ?? ' ';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment == CrossAxisAlignment.end
              ? TextAlign.end
              : TextAlign.start,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
