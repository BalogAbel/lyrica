import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _sectionSpacing = 16.0;
const _controlSpacing = 12.0;
const _chipHorizontalPadding = 12.0;
const _chipVerticalPadding = 8.0;
const _labelValueGap = 8.0;

class SongReaderHeader extends StatelessWidget {
  const SongReaderHeader({
    super.key,
    required this.projection,
    required this.onTransposeDown,
    required this.onTransposeUp,
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
  });

  final SongReaderProjection projection;
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
            _ControlSection(
              label: AppStrings.songReaderTransposeSectionLabel,
              child: Wrap(
                spacing: _controlSpacing,
                runSpacing: _controlSpacing,
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
              const SizedBox(height: _sectionSpacing),
              _ControlSection(
                label: AppStrings.songReaderCapoSectionLabel,
                child: Wrap(
                  spacing: _controlSpacing,
                  runSpacing: _controlSpacing,
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
            const SizedBox(height: _sectionSpacing),
            _ControlSection(
              label: AppStrings.songReaderScaleSectionLabel,
              child: Wrap(
                spacing: _controlSpacing,
                runSpacing: _controlSpacing,
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

  String _signed(int value) {
    return value > 0 ? '+$value' : '$value';
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
        padding: const EdgeInsets.symmetric(
          horizontal: _chipHorizontalPadding,
          vertical: _chipVerticalPadding,
        ),
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
        const SizedBox(height: _labelValueGap),
        child,
      ],
    );
  }
}
