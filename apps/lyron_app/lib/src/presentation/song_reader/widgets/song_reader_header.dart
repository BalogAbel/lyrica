import 'package:flutter/material.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_key_source_style.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _sectionSpacing = 16.0;
const _controlSpacing = 12.0;
const _chipHorizontalPadding = 12.0;
const _chipVerticalPadding = 8.0;
const _labelValueGap = 8.0;
const _labelBadgeGap = 8.0;
const _badgeHorizontalPadding = 8.0;
const _badgeVerticalPadding = 2.0;

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
    this.keyActions = SongReaderKeyActions.none,
  });

  final SongReaderProjection projection;
  final VoidCallback? onTransposeDown;
  final VoidCallback? onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;
  final SongReaderKeyActions keyActions;

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
              badge: _SourceBadge(
                textKey: const Key('song-reader-transpose-source'),
                source: projection.key.transpose.source,
              ),
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
                    source: projection.key.transpose.source,
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
                badge: _SourceBadge(
                  textKey: const Key('song-reader-capo-source'),
                  source: projection.key.capo.source,
                ),
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
                      source: projection.key.capo.source,
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
            Wrap(
              spacing: _controlSpacing,
              runSpacing: _controlSpacing,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const Key('song-reader-key-reset'),
                  onPressed: keyActions.onReset,
                  child: const Text(AppStrings.songReaderResetKeyAction),
                ),
                if (keyActions.isSaveToPlanAvailable)
                  FilledButton.tonal(
                    key: const Key('song-reader-key-save-to-plan'),
                    onPressed: keyActions.onSaveToPlan,
                    child: const Text(AppStrings.songReaderSaveToPlanAction),
                  ),
              ],
            ),
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
  const _ValueChip({super.key, required this.value, required this.source});

  final String value;
  final SongKeyLayerId source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = songKeySourceColors(theme.colorScheme, source);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _chipHorizontalPadding,
          vertical: _chipVerticalPadding,
        ),
        child: Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(color: colors.foreground),
        ),
      ),
    );
  }
}

/// The word, in the source's colors, that names the layer a value comes from
/// (PS25).
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.textKey, required this.source});

  /// The key of the word itself, which is what tests and callers look up.
  final Key textKey;
  final SongKeyLayerId source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = songKeySourceColors(theme.colorScheme, source);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _badgeHorizontalPadding,
          vertical: _badgeVerticalPadding,
        ),
        child: Text(
          songKeySourceLabel(source),
          key: textKey,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.foreground),
        ),
      ),
    );
  }
}

class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.label, required this.child, this.badge});

  final String label;
  final Widget child;

  /// Shown at the end of the label row, when the section has one.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.08,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: _labelBadgeGap),
              badge!,
            ],
          ],
        ),
        const SizedBox(height: _labelValueGap),
        child,
      ],
    );
  }
}
