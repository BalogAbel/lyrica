import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';

void main() {
  testWidgets('measureSongReaderCharWidths returns the reader metrics', (
    tester,
  ) async {
    late SongReaderCharWidths measured;
    late ReaderTheme expectedTokens;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            measured = measureSongReaderCharWidths(context);
            expectedTokens = ReaderTheme.stageLight(
              colorScheme: Theme.of(context).colorScheme,
              textTheme: Theme.of(context).textTheme,
              compact: false,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // A bare MaterialApp registers no ReaderThemeSet, so ReaderTheme.of
    // falls back to ReaderTheme.stageLight over the ambient theme (see that
    // factory's doc). Before the type scale (PR3, #71) that fallback used
    // SongReaderMetrics.legacy directly; now it derives real metrics from
    // the viewport width, and the test window's default size is wide
    // enough to resolve the REGULAR set -- so this must match
    // ReaderTheme.of's own regular metrics, not the legacy constant.
    expect(measured.metrics, expectedTokens.metrics);
  });

  testWidgets(
    'lyricCharWidth is measured at the rendered w500 lyric weight, not w400',
    (tester) async {
      // Copied verbatim from song_reader_char_metrics.dart's private
      // `_lyricMeasureSample` -- it cannot be imported (library-private), so
      // this local copy stands in for it. Length is read off the string
      // itself (`.length`), never hardcoded, so a future change to the
      // sample string cannot silently desync this test from the real one.
      const lyricMeasureSample =
          'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789';

      late SongReaderCharWidths measured;
      late TextStyle realLyricStyle;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              measured = measureSongReaderCharWidths(context);
              realLyricStyle = ReaderTheme.of(context).lyricStyle;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // The renderer draws lyrics at w500 (spec section: "Lyrics move to
      // w500"). If this ever regresses to w400, the estimator silently goes
      // back to measuring a style the renderer does not draw with.
      expect(realLyricStyle.fontWeight, FontWeight.w500);

      TextPainter paint(TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: lyricMeasureSample, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        return painter;
      }

      // measureSongReaderCharWidths must have measured the SAME style the
      // renderer draws with (real lyricStyle, real weight, real
      // letterSpacing if any) -- reproduce that measurement here and compare.
      final realPainter = paint(realLyricStyle);
      final reconstructedWidth =
          measured.lyricCharWidth * lyricMeasureSample.length;
      expect(
        reconstructedWidth,
        closeTo(realPainter.width, 0.5),
        reason:
            'lyricCharWidth must reproduce a TextPainter layout at the '
            'real, rendered lyricStyle -- a mismatch means the estimator is '
            'measuring a style the renderer does not draw with',
      );

      // Compare against a w400 painter of the same style/sample: if the
      // bundled test font only ships one weight, the two widths come out
      // equal, which is an environment fact (no distinct w400 glyphs to
      // measure), not a defect -- hence greaterThanOrEqualTo rather than
      // greaterThan. The fontWeight assertion above plus the closeTo check
      // are the real signal that the estimator tracks the rendered weight.
      final w400Painter = paint(realLyricStyle.copyWith(fontWeight: FontWeight.w400));
      expect(realPainter.width, greaterThanOrEqualTo(w400Painter.width));

      realPainter.dispose();
      w400Painter.dispose();
    },
  );
}
