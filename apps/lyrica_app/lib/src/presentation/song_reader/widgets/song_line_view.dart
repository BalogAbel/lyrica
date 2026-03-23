import 'package:flutter/material.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

class SongLineView extends StatelessWidget {
  const SongLineView({
    super.key,
    required this.line,
    required this.viewMode,
    required this.sharedFontScale,
  });

  final SongReaderLineProjection line;
  final SongReaderViewMode viewMode;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chordStyle = theme.textTheme.labelLarge?.copyWith(
      fontSize: (theme.textTheme.labelLarge?.fontSize ?? 14) * sharedFontScale,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
    );
    final lyricStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) * sharedFontScale,
      height: 1.25,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final segment in line.segments)
            _SongLineSegmentView(
              segment: segment,
              viewMode: viewMode,
              chordStyle: chordStyle,
              lyricStyle: lyricStyle,
            ),
        ],
      ),
    );
  }
}

class _SongLineSegmentView extends StatelessWidget {
  const _SongLineSegmentView({
    required this.segment,
    required this.viewMode,
    required this.chordStyle,
    required this.lyricStyle,
  });

  final SongReaderSegmentProjection segment;
  final SongReaderViewMode viewMode;
  final TextStyle? chordStyle;
  final TextStyle? lyricStyle;

  @override
  Widget build(BuildContext context) {
    final showChord =
        viewMode == SongReaderViewMode.chordsAndLyrics &&
        segment.displayChord != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showChord) ...[
          Text(segment.displayChord!, style: chordStyle),
          const SizedBox(height: 2),
        ],
        Text(segment.text, style: lyricStyle),
      ],
    );
  }
}
