import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';

/// Measured average per-character advance (in logical pixels, at the
/// RAW base point size -- fontScale == 1.0, no ambient scaling) of the
/// lyric and chord text styles the reader actually renders with, plus the
/// [SongReaderFitTextScale] bundle needed to convert those raw widths (and
/// every flat row-height constant in song_reader_fit.dart) to the actual
/// rendered size at any candidate fontScale.
///
/// [song_reader_fit.dart]'s estimator used to guess both widths with a
/// single flat constant (`characterWidthEstimate = 10.0`). Real
/// `TextPainter` measurement of the actual styles showed both were wrong in
/// the same direction (undershooting), by different amounts:
///   - chord (`labelLarge`, size 14, `w700`): ~14.1 px/char
///   - lyric (`bodyLarge`, size 16): ~16.5 px/char
/// [measureSongReaderCharWidths] replaces the guess with a real measurement
/// so the estimator tracks whichever theme is actually active, instead of a
/// number that only happened to match one specific theme.
///
/// These widths are measured at the RAW base size, deliberately WITHOUT the
/// ambient `MediaQuery.textScalerOf(context)` scaler baked in (unlike an
/// earlier version of this function, which measured with the ambient
/// scaler applied and left callers to multiply by `fontScale` alone
/// afterward). That flattened design assumed the ambient ratio measured at
/// the base size still applies unchanged once `fontScale` moves the
/// candidate font away from that base size -- true only for a LINEAR
/// scaler. `TextScaler.scale` is not linear in general (Android 14+
/// "non-linear font scaling" boosts small text more than large text), so
/// the ratio at, say, 14px chord text differs from the ratio at whatever
/// probe size the old design happened to measure at. Measuring raw here and
/// applying [SongReaderFitTextScale.factorFor] downstream (in
/// song_reader_fit.dart) at the REAL candidate rendered size fixes this: the
/// scaler is always evaluated at the size it will actually apply to.
class SongReaderCharWidths {
  const SongReaderCharWidths({
    required this.lyricCharWidth,
    required this.chordCharWidth,
    required this.textScale,
  });

  /// Average px/char advance of the lyric body style (`bodyLarge`, `height:
  /// 1.25`), measured RAW at its base point size (`textScale.lyricBaseFontSize`,
  /// fontScale == 1.0, no ambient scaling). Callers convert this to the
  /// width at any candidate `sharedFontScale` via
  /// `lyricCharWidth * textScale.factorFor(textScale.lyricBaseFontSize, sharedFontScale)`.
  final double lyricCharWidth;

  /// Average px/char advance of the chord label style (`labelLarge`,
  /// `FontWeight.w700`), measured RAW at its base point size
  /// (`textScale.chordBaseFontSize`). Same conversion rule as
  /// [lyricCharWidth] applies, using `textScale.chordBaseFontSize`.
  final double chordCharWidth;

  /// The ambient [SongReaderFitTextScale] bundle (scaler + every base font
  /// size song_reader_fit.dart's estimator models), captured once per build
  /// alongside the char-width measurements above. Pass this straight through
  /// as the `textScale` argument to `resolveFitFontScale` /
  /// `estimateSongContentHeight` / `resolveFlowLayoutForSections` / friends.
  final SongReaderFitTextScale textScale;
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
/// at their BASE font size (fontScale == 1.0) -- callers convert the
/// returned widths to any candidate fontScale via
/// `SongReaderFitTextScale.factorFor` (song_reader_fit.dart) rather than
/// re-measuring at every scale. This keeps `resolveFitFontScale`'s
/// ~24-iteration binary search free of repeated `TextPainter` layout work:
/// this function is meant to be called once per build (or once per event,
/// for a one-shot double-tap handler), with the result reused across every
/// line and every binary-search iteration in that call.
///
/// Measures RAW, at exactly the style's base point size -- deliberately
/// WITHOUT the ambient `MediaQuery.textScalerOf(context)` scaler applied to
/// the `TextPainter` (an earlier version of this function baked the ambient
/// scaler into the measurement itself and left callers to multiply by
/// `fontScale` alone). That flattened design assumed the ambient ratio
/// measured at the base size still holds once `fontScale` moves the
/// candidate font away from that base size -- true only for a LINEAR
/// scaler; `TextScaler.scale` is not linear in general (Android 14+
/// "non-linear font scaling" boosts small text more than large text), so a
/// single baked-in ratio silently reintroduces the same "estimate below
/// render" failure mode `sharedFontScale` exists to prevent (a real user
/// with non-linear system font scaling turned on is exactly the user this
/// must not overflow for). Instead, the ambient scaler is captured
/// unevaluated in [SongReaderFitTextScale] and applied downstream
/// (song_reader_fit.dart) at the REAL candidate rendered size for each
/// style, via `SongReaderFitTextScale.factorFor`.
SongReaderCharWidths measureSongReaderCharWidths(BuildContext context) {
  final theme = Theme.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  final chordStyle = theme.textTheme.labelLarge?.copyWith(
    fontWeight: FontWeight.w700,
  );
  final lyricStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.25);

  double measure(String sample, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: TextDirection.ltr,
    );
    try {
      painter.layout();
      return painter.width / sample.length;
    } finally {
      painter.dispose();
    }
  }

  return SongReaderCharWidths(
    lyricCharWidth: measure(_lyricMeasureSample, lyricStyle),
    chordCharWidth: measure(_chordMeasureSample, chordStyle),
    textScale: SongReaderFitTextScale(
      textScaler: textScaler,
      lyricBaseFontSize: lyricStyle?.fontSize ?? 16.0,
      chordBaseFontSize: chordStyle?.fontSize ?? 14.0,
      headerBaseFontSize: theme.textTheme.titleLarge?.fontSize ?? 22.0,
      inlineDirectiveBaseFontSize:
          theme.textTheme.labelMedium?.fontSize ?? 12.0,
    ),
  );
}
