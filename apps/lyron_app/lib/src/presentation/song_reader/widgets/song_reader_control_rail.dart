import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The reader's floating control rail (spec section 6, "Chrome"). Hidden by
/// default, revealed by the same tap that reveals `SongReaderTopBar`, and
/// drawn as a `Positioned` overlay at the compact shell's right edge,
/// offset from it by `SongReaderChromeMetrics.railEdgeInset` -- see
/// `SongReaderCompactSurface`'s `Stack` comment for why floating chrome is
/// excluded from the fit calculation's available width.
///
/// Vertical groups, top to bottom: transpose −/value/+, capo −/value/+
/// (guitar only), font A−/A+. The capo group is hidden entirely in piano
/// mode, driven by `projection.isCapoDirectiveVisible`, exactly as the old
/// horizontal `SongReaderControlBar` did.
///
/// Floats over scrolling lyric content, so it needs its own background to
/// stay legible in both themes -- taken from
/// [ReaderTheme.floatingChromeBackground], never hardcoded (ADR-033).
///
/// The rail assumes a right-handed grip. There is deliberately **no**
/// mirroring / handedness setting here -- spec "Open questions" defers that
/// until the layout has been used on real hardware. Do not add one.
class SongReaderControlRail extends StatelessWidget {
  const SongReaderControlRail({
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
    final readerTheme = ReaderTheme.of(context);
    final showCapo = projection.isCapoDirectiveVisible;

    return Material(
      key: const Key('song-reader-control-rail-surface'),
      color: readerTheme.floatingChromeBackground,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Group(
                children: [
                  IconButton(
                    key: const Key('song-reader-transpose-down'),
                    tooltip: AppStrings.songReaderTransposeDownSemantics,
                    onPressed: onTransposeDown,
                    icon: const Icon(Icons.remove),
                  ),
                  _ValueChip(
                    key: const Key('song-reader-transpose-value'),
                    value: _signed(projection.effectiveTranspose),
                  ),
                  IconButton(
                    key: const Key('song-reader-transpose-up'),
                    tooltip: AppStrings.songReaderTransposeUpSemantics,
                    onPressed: onTransposeUp,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (showCapo) ...[
                const _Divider(),
                _Group(
                  children: [
                    IconButton(
                      key: const Key('song-reader-capo-down'),
                      tooltip: AppStrings.songReaderCapoDownSemantics,
                      onPressed: onCapoDown,
                      icon: const Icon(Icons.remove),
                    ),
                    _ValueChip(
                      key: const Key('song-reader-capo-value'),
                      value:
                          '${AppStrings.songReaderCapoDirectivePrefix}'
                          '${projection.effectiveCapo}',
                    ),
                    IconButton(
                      key: const Key('song-reader-capo-up'),
                      tooltip: AppStrings.songReaderCapoUpSemantics,
                      onPressed: onCapoUp,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
              const _Divider(),
              _Group(
                children: [
                  IconButton(
                    key: const Key('song-reader-font-decrease'),
                    tooltip: AppStrings.songReaderDecreaseFontSemantics,
                    onPressed: onDecreaseFontScale,
                    icon: const Icon(Icons.text_decrease),
                  ),
                  IconButton(
                    key: const Key('song-reader-font-increase'),
                    tooltip: AppStrings.songReaderIncreaseFontSemantics,
                    onPressed: onIncreaseFontScale,
                    icon: const Icon(Icons.text_increase),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: 24,
        child: Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(value, style: theme.textTheme.labelLarge),
        ),
      ),
    );
  }
}
