import 'package:flutter/material.dart';

/// Measured average per-character advance (in logical pixels, at
/// `fontScale == 1.0`) of the lyric and chord text styles the reader
/// actually renders with.
///
/// [song_reader_fit.dart]'s estimator used to guess both widths with a
/// single flat constant (`characterWidthEstimate = 10.0`). Real
/// `TextPainter` measurement of the actual styles showed both were wrong in
/// the same direction (undershooting), by different amounts:
///   - chord (`labelLarge`, size 14, `w700`): ~14.1 px/char
///   - lyric (`bodyLarge`, size 16): ~16.5 px/char
/// [measureSongReaderCharWidths] replaces the guess with a real measurement
/// so the estimator tracks whichever theme/text-scale is actually active,
/// instead of a number that only happened to match one specific theme.
class SongReaderCharWidths {
  const SongReaderCharWidths({
    required this.lyricCharWidth,
    required this.chordCharWidth,
  });

  /// Average px/char advance of the lyric body style (`bodyLarge`, `height:
  /// 1.25`), at fontScale == 1.0.
  final double lyricCharWidth;

  /// Average px/char advance of the chord label style (`labelLarge`,
  /// `FontWeight.w700`), at fontScale == 1.0.
  final double chordCharWidth;
}

// Representative sample strings used to measure an AVERAGE per-character
// advance, rather than a single glyph's width (which could be atypically
// narrow/wide, e.g. 'i' vs 'W'). Divide the painter's total width by the
// sample length to get the per-char figure the fit estimator multiplies by
// character counts.
const _lyricMeasureSample =
    'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789';
const _chordMeasureSample = 'ABCDEFG#b/mjasdimug 0123456789';

/// Measures [SongReaderCharWidths] for the current [context]'s theme.
///
/// Mirrors the exact text styles `SongLineView` (widgets/song_line_view.dart)
/// builds for chord and lyric text:
///   - chord: `theme.textTheme.labelLarge` + `FontWeight.w700`
///   - lyric: `theme.textTheme.bodyLarge` + `height: 1.25`
/// at their BASE font size (fontScale == 1.0) -- callers scale the returned
/// widths linearly by fontScale themselves rather than re-measuring at every
/// scale. This keeps `resolveFitFontScale`'s ~24-iteration binary search
/// (song_reader_fit.dart) free of repeated `TextPainter` layout work: this
/// function is meant to be called once per build (or once per event, for a
/// one-shot double-tap handler), with the result reused across every line
/// and every binary-search iteration in that call.
SongReaderCharWidths measureSongReaderCharWidths(BuildContext context) {
  final theme = Theme.of(context);
  final chordStyle = theme.textTheme.labelLarge?.copyWith(
    fontWeight: FontWeight.w700,
  );
  final lyricStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.25);

  double measure(String sample, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    return painter.width / sample.length;
  }

  return SongReaderCharWidths(
    lyricCharWidth: measure(_lyricMeasureSample, lyricStyle),
    chordCharWidth: measure(_chordMeasureSample, chordStyle),
  );
}
