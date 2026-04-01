import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

class SongReaderHeader extends StatelessWidget {
  const SongReaderHeader({
    super.key,
    required this.projection,
    required this.hasRecoverableWarnings,
    required this.warningCount,
    required this.onToggleViewMode,
    required this.onTransposeDown,
    required this.onTransposeUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
  });

  final SongReaderProjection projection;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final VoidCallback onToggleViewMode;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(projection.title, style: theme.textTheme.headlineSmall),
            if (projection.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(projection.subtitle!, style: subtitleStyle),
            ],
            if (projection.sourceKey != null) ...[
              const SizedBox(height: 10),
              _MetadataChip(label: 'Key', value: projection.sourceKey!),
            ],
            if (hasRecoverableWarnings) ...[
              const SizedBox(height: 16),
              _WarningSurface(warningCount: warningCount),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: onToggleViewMode,
                  child: Text(_viewModeLabel(projection.viewMode)),
                ),
                OutlinedButton(
                  onPressed: onTransposeDown,
                  child: const Text('-1'),
                ),
                OutlinedButton(
                  onPressed: onTransposeUp,
                  child: const Text('+1'),
                ),
                OutlinedButton(
                  onPressed: onDecreaseFontScale,
                  child: const Text('A-'),
                ),
                OutlinedButton(
                  onPressed: onIncreaseFontScale,
                  child: const Text('A+'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _viewModeLabel(SongReaderViewMode viewMode) {
    switch (viewMode) {
      case SongReaderViewMode.chordsAndLyrics:
        return 'Lyrics only';
      case SongReaderViewMode.lyricsOnly:
        return 'Chords + lyrics';
    }
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('$label: $value', style: theme.textTheme.labelLarge),
      ),
    );
  }
}

class _WarningSurface extends StatelessWidget {
  const _WarningSurface({required this.warningCount});

  final int warningCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.tertiaryContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                warningCount == 1
                    ? '1 recoverable warning while reading this song.'
                    : '$warningCount recoverable warnings while reading this song.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
