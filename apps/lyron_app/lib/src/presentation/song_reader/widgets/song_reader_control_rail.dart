import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_key_source_style.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The reader's floating control rail (spec section 6, "Chrome"). Hidden by
/// default, revealed by the same tap that reveals `SongReaderTopBar`, and
/// drawn as a `Positioned` overlay at the compact shell's right edge,
/// offset from it by `SongReaderChromeMetrics.railEdgeInset` -- see
/// `SongReaderCompactSurface`'s `Stack` comment for why floating chrome is
/// excluded from the fit calculation's available width.
///
/// Vertical groups, top to bottom: transpose −/value/source/+, capo
/// −/value/source/+ (guitar only), Reset and Save to plan, font A−/A+. The
/// source caption names the layer the value comes from (PS25) in a fixed-width
/// slot, so the rail never changes size with it. The Reset and Save to plan
/// buttons are always there where they apply and only enabled while they do
/// (PS7), so the rail, which is vertically centered, never grows under the
/// musician's finger. The capo group is hidden entirely in piano mode, driven
/// by `projection.isCapoDirectiveVisible`, exactly as the old horizontal
/// `SongReaderControlBar` did.
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
                    source: projection.key.transpose.source,
                  ),
                  _SourceCaption(
                    textKey: const Key('song-reader-transpose-source'),
                    source: projection.key.transpose.source,
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
                      source: projection.key.capo.source,
                    ),
                    _SourceCaption(
                      textKey: const Key('song-reader-capo-source'),
                      source: projection.key.capo.source,
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
                    key: const Key('song-reader-key-reset'),
                    tooltip: AppStrings.songReaderResetKeyAction,
                    onPressed: keyActions.onReset,
                    icon: const Icon(Icons.restart_alt),
                  ),
                  if (keyActions.isSaveToPlanAvailable)
                    IconButton(
                      key: const Key('song-reader-key-save-to-plan'),
                      tooltip: AppStrings.songReaderSaveToPlanAction,
                      onPressed: keyActions.onSaveToPlan,
                      icon: const Icon(Icons.playlist_add_check),
                    ),
                ],
              ),
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
  const _ValueChip({super.key, required this.value, required this.source});

  final String value;
  final SongKeyLayerId source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = songKeySourceColors(theme.colorScheme, source);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// The word under a value chip that names its source. A fixed-width slot,
/// scaled down to fit on one line, so a longer word never grows the rail. It
/// sits on the rail's own background, so it takes `onSurfaceVariant`: the
/// `on...Container` colors are made for the chip.
class _SourceCaption extends StatelessWidget {
  const _SourceCaption({required this.textKey, required this.source});

  static const _slotWidth = 56.0;

  /// The key of the word itself, which is what tests and callers look up.
  final Key textKey;
  final SongKeyLayerId source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SizedBox(
      width: _slotWidth,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // An empty line of the same style: it holds the slot at one full
          // line high, because a word scaled down to fit the width would
          // otherwise be shorter than the others.
          Text('', style: style),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              songKeySourceLabel(source),
              key: textKey,
              maxLines: 1,
              softWrap: false,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
