import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

const _lineRunSpacing = 10.0;
const _chordOnlySpacing = 22.0;

class SongLineView extends StatelessWidget {
  const SongLineView({
    super.key,
    required this.line,
    required this.viewMode,
    required this.sharedFontScale,
  });

  final SongReaderLyricLineProjection line;
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

    final hasLyricSegments = line.segments.any(
      (segment) => segment.text.trim().isNotEmpty,
    );
    if (!hasLyricSegments && viewMode == SongReaderViewMode.lyricsOnly) {
      return const SizedBox.shrink();
    }
    final spacing = hasLyricSegments ? 0.0 : _chordOnlySpacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wrap passes unbounded width to its children, so an unbreakable token
        // would expand to its natural width.  Resolve the available width here
        // (falling back to the MediaQuery screen width when constraints are
        // infinite, e.g. inside an InteractiveViewer) and pass it down so each
        // segment can apply a ConstrainedBox that forces internal text wrapping.
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Wrap(
            spacing: spacing,
            runSpacing: _lineRunSpacing,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final segment in line.segments)
                _SongLineSegmentView(
                  segment: segment,
                  viewMode: viewMode,
                  chordStyle: chordStyle,
                  lyricStyle: lyricStyle,
                  maxWidth: maxWidth,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SongLineSegmentView extends StatelessWidget {
  const _SongLineSegmentView({
    required this.segment,
    required this.viewMode,
    required this.chordStyle,
    required this.lyricStyle,
    required this.maxWidth,
  });

  final SongReaderSegmentProjection segment;
  final SongReaderViewMode viewMode;
  final TextStyle? chordStyle;
  final TextStyle? lyricStyle;
  // Maximum width available for this segment's lyric text.  Wrap passes
  // unbounded constraints to its children; ConstrainedBox re-introduces the
  // bound so that a long unbreakable token wraps internally instead of
  // overflowing the line.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final showChord =
        viewMode == SongReaderViewMode.chordsAndLyrics &&
        segment.displayChord != null;
    final showLyric = segment.text.isNotEmpty;

    if (!showChord && !showLyric) {
      return const SizedBox.shrink();
    }

    final child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showChord) ...[
          Text(segment.displayChord!, style: chordStyle),
          if (showLyric) const SizedBox(height: 2),
        ],
        if (showLyric)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              segment.text,
              style: lyricStyle,
              softWrap: true,
            ),
          ),
      ],
    );

    return child;
  }
}
