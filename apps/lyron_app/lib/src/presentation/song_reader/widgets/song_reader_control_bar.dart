import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Slim bottom control bar shown when the reader is active. Holds transpose,
/// capo (guitar only) and font-size controls as compact icon buttons.
class SongReaderControlBar extends StatelessWidget {
  const SongReaderControlBar({
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
    final theme = Theme.of(context);
    final showCapo = projection.isCapoDirectiveVisible;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
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
                        value: '${AppStrings.songReaderCapoDirectivePrefix}'
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
    return Row(
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(value, style: theme.textTheme.labelLarge),
    );
  }
}
