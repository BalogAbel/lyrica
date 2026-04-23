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
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
  });

  final SongReaderProjection projection;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final VoidCallback onToggleViewMode;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  @override
  Widget build(BuildContext context) {
    final showCapoControls = projection.isCapoDirectiveVisible;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (projection.sourceKey != null) ...[
              _MetadataChip(label: 'Key', value: projection.sourceKey!),
              const SizedBox(height: 16),
            ],
            if (hasRecoverableWarnings) ...[
              const SizedBox(height: 14),
              _WarningSurface(warningCount: warningCount),
            ],
            const SizedBox(height: 16),
            _ControlSection(
              label: 'View',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: onToggleViewMode,
                    child: Text(_viewModeLabel(projection.viewMode)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ControlSection(
              label: 'Transpose',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('song-reader-transpose-down'),
                    onPressed: onTransposeDown,
                    child: const Text('-'),
                  ),
                  _ValueChip(
                    key: const Key('song-reader-transpose-value'),
                    value: _signed(projection.effectiveTranspose),
                  ),
                  OutlinedButton(
                    key: const Key('song-reader-transpose-up'),
                    onPressed: onTransposeUp,
                    child: const Text('+'),
                  ),
                ],
              ),
            ),
            if (showCapoControls) ...[
              const SizedBox(height: 16),
              _ControlSection(
                label: 'Capo',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const Key('song-reader-capo-down'),
                      onPressed: onCapoDown,
                      child: const Text('-'),
                    ),
                    _ValueChip(
                      key: const Key('song-reader-capo-value'),
                      value: '${projection.effectiveCapo}',
                    ),
                    OutlinedButton(
                      key: const Key('song-reader-capo-up'),
                      onPressed: onCapoUp,
                      child: const Text('+'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _ControlSection(
              label: 'Scale',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
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

  String _signed(int value) {
    return value > 0 ? '+$value' : '$value';
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

class _ValueChip extends StatelessWidget {
  const _ValueChip({super.key, required this.value});

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
        child: Text(value, style: theme.textTheme.labelLarge),
      ),
    );
  }
}

class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.label, required this.child});

  final String label;
  final Widget child;

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
            letterSpacing: 0.08,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
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
