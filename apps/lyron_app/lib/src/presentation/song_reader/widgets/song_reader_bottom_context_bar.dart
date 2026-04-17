import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongReaderBottomContextBar extends StatelessWidget {
  const SongReaderBottomContextBar({
    super.key,
    required this.currentTitle,
    this.previousTitle,
    this.nextTitle,
    this.onPreviousTap,
    this.onNextTap,
  });

  static const previousSegmentKey = Key(
    'song-reader-bottom-context-previous-segment',
  );
  static const nextSegmentKey = Key('song-reader-bottom-context-next-segment');
  static const disabledSegmentOpacity = 0.5;

  final String currentTitle;
  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;

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
              child: _NeighborSegment(
                key: previousSegmentKey,
                alignment: CrossAxisAlignment.start,
                label: AppStrings.scopedReaderPreviousAction,
                title: previousTitle,
                onTap: onPreviousTap,
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.scopedReaderCurrentSongLabel,
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
              child: _NeighborSegment(
                key: nextSegmentKey,
                alignment: CrossAxisAlignment.end,
                label: AppStrings.scopedReaderNextAction,
                title: nextTitle,
                onTap: onNextTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeighborSegment extends StatelessWidget {
  const _NeighborSegment({
    super.key,
    required this.alignment,
    required this.label,
    required this.title,
    required this.onTap,
  });

  final CrossAxisAlignment alignment;
  final String label;
  final String? title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTitle = title ?? ' ';
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
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
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null
              ? SongReaderBottomContextBar.disabledSegmentOpacity
              : 1,
          child: content,
        ),
      ),
    );
  }
}
