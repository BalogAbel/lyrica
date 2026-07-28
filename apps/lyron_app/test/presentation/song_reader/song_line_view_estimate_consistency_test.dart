import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

// ---------------------------------------------------------------------------
// Per-line real-render vs estimate regression test.
// ---------------------------------------------------------------------------
//
// The whole-song consistency fixtures (song_reader_estimate_render_consistency_
// test.dart) aggregate error across many lines, sections, and gaps -- a wide
// tolerance there can hide a per-line bug that happens to cancel out over a
// whole song. This file isolates ONE line at a time: render a real
// SongLineView at a fixed narrow width, measure its actual rendered height
// from the render tree, and compare it directly against the estimator's
// height for that exact same line, width, and font scale. No aggregation
// slack -- bounds here are pinned tight.
//
// Each fixture renders SongLineView the same way SongReaderSectionGrid does
// (widget height + the grid's own trailing 10px gap between lines --
// song_reader_section_grid.dart's `_buildBlockWidgets` appends
// `SizedBox(height: lineGap)` after every line widget) and compares that to
// flowBlockHeight's line branch (isSectionStart: false), which is the exact
// per-line quantity the grid and the fit calculator both use.
//
// Measured 2026-07-28, MaterialApp default ThemeData, fontScale = 1.0.

double _measuredLineHeight(WidgetTester tester) =>
    tester.getSize(find.byType(SongLineView)).height + lineGap;

Future<double> _renderAndMeasure(
  WidgetTester tester, {
  required SongReaderLyricLineProjection line,
  required SongReaderViewMode viewMode,
  required double width,
  required double fontScale,
  TextScaler? textScaler,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            Widget content = Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SongLineView(
                  line: line,
                  viewMode: viewMode,
                  sharedFontScale: fontScale,
                ),
              ),
            );
            if (textScaler != null) {
              content = MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: content,
              );
            }
            return content;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return _measuredLineHeight(tester);
}

// Note: no textScaler parameter here -- measureSongReaderCharWidths reads
// the ambient MediaQuery textScaler straight off the element's context,
// which already sits inside whatever MediaQuery override _renderAndMeasure
// installed, so the estimate automatically picks up a non-default scaler
// once the widget tree carries one.
double _estimatedLineHeight(
  WidgetTester tester, {
  required SongReaderLyricLineProjection line,
  required SongReaderViewMode viewMode,
  required double width,
  required double fontScale,
}) {
  final charWidths = measureSongReaderCharWidths(
    tester.element(find.byType(SongLineView)),
  );
  final block = FlowBlock(
    kind: FlowBlockKind.line,
    sectionIndex: 0,
    line: line,
  );
  return flowBlockHeight(
    block: block,
    viewMode: viewMode,
    columnWidth: width,
    fontScale: fontScale,
    lyricCharWidth: charWidths.lyricCharWidth,
    chordCharWidth: charWidths.chordCharWidth,
    ambientTextScaleRatio: charWidths.ambientTextScaleRatio,
  );
}

void main() {
  const viewMode = SongReaderViewMode.chordsAndLyrics;
  const fontScale = 1.0;

  // One-sided contract: resolveFitFontScale picks the largest scale whose
  // ESTIMATED height fits the viewport, so an estimate below the real
  // render lets the grid overflow -- the one thing fit-to-screen exists to
  // prevent. An estimate above the real render only ever picks a slightly
  // smaller font. Direction therefore matters in a way a symmetric
  // tolerance cannot express: the estimate must never fall below the
  // rendered height, and [ceilingMultiplier] just keeps it from being
  // uselessly loose.
  Future<void> expectUpperBound(
    WidgetTester tester, {
    required SongReaderLyricLineProjection line,
    required double width,
    required double ceilingMultiplier,
  }) async {
    final rendered = await _renderAndMeasure(
      tester,
      line: line,
      viewMode: viewMode,
      width: width,
      fontScale: fontScale,
    );
    final estimated = _estimatedLineHeight(
      tester,
      line: line,
      viewMode: viewMode,
      width: width,
      fontScale: fontScale,
    );

    expect(
      estimated,
      greaterThanOrEqualTo(rendered),
      reason:
          'the estimate must never fall below the real render (an '
          'under-estimate lets resolveFitFontScale pick a scale that '
          'overflows); rendered=$rendered estimated=$estimated',
    );
    expect(
      estimated,
      lessThan(rendered * ceilingMultiplier),
      reason:
          'the estimate must not be uselessly loose; rendered=$rendered '
          'estimated=$estimated ceiling=${rendered * ceilingMultiplier}',
    );
  }

  group('SongLineView per-line estimate/render consistency', () {
    testWidgets('plain lyric line, no chords, wraps at a narrow width', (
      tester,
    ) async {
      final line = SongReaderLyricLineProjection(
        segments: [
          const SongReaderSegmentProjection(
            displayChord: null,
            text:
                'This is a long lyric line without any chords and it will '
                'definitely wrap across several rows',
          ),
        ],
      );

      // PRE-FIX (2026-07-28): rendered=292.0 estimated=250.0 (width=160).
      // estimated < rendered -- RED under the one-sided contract. The old
      // intra-segment wrap count (_segmentIntraLines) used
      // ceil(lyricWidth / effectiveLineWidth), a plain character-count
      // division that ignores word boundaries, so it undercounts wrapped
      // lines for a run of ordinary words.
      //
      // POST-FIX (2026-07-28), after modelling greedy word-boundary wrap in
      // _segmentIntraLines: rendered=292.0 estimated=372.0. estimated >
      // rendered (ratio 1.27x) -- the word-wrap model now over-counts this
      // fixture's wraps slightly (it does not know the actual glyph widths
      // within a word, only a flat per-character average), but never drops
      // below the render.
      await expectUpperBound(
        tester,
        line: line,
        width: 160.0,
        ceilingMultiplier: 1.35,
      );
    });

    testWidgets('wide chords over short syllables force separate runs '
        '(reviewer\'s case)', (tester) async {
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'C#m/G#', text: 'a '),
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11', text: 'b '),
          SongReaderSegmentProjection(displayChord: 'C#m/G#', text: 'c '),
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11', text: 'd'),
        ],
      );

      // PRE-FIX (2026-07-28): rendered=210.0 estimated=224.0 (width=150).
      // estimated > rendered -- already satisfies the one-sided contract.
      // This is the reviewer's original repro shape: wide chords (C#m/G#
      // @ ~84.6px, Cmaj7#11 wider still) over one-character syllables at a
      // narrow column -- the estimator must count 4 separate runs here
      // (one wide chord per run), not collapse them into fewer runs.
      //
      // POST-FIX (2026-07-28): rendered=210.0 estimated=226.0 (ratio 1.08x).
      // Word-wrap modelling and the +2px widget-padding margin barely move
      // this fixture (no segment's own text wraps here), as expected.
      await expectUpperBound(
        tester,
        line: line,
        width: 150.0,
        ceilingMultiplier: 1.15,
      );
    });

    testWidgets('wide chords with NO whitespace at any join force the inner '
        'over-wide-group Wrap branch (not just inter-group packing)', (
      tester,
    ) async {
      // The "wide chords over short syllables" fixture above uses segment
      // texts ending in spaces ('a ', 'b ', 'c '), so
      // groupSegmentsIntoWords splits them into separate single-segment
      // groups -- it only ever exercises inter-GROUP packing (the normal
      // groups loop in _lineItemHeight), never the inner, over-wide-GROUP
      // Wrap branch that packs several segments of the SAME group
      // segment-by-segment (song_reader_fit.dart's `if (groupWidth >
      // effectiveLineWidth)` branch), because each of its groups has only
      // one segment.
      //
      // This fixture has NO whitespace at any join (every segment's text
      // is exactly 'a', no trailing/leading space), so
      // groupSegmentsIntoWords merges all four segments into ONE group.
      // Four "C#m/G#" chords (~84.6px each) sum to roughly 340px, several
      // times over a 120-150px line, so the group as a whole is over-wide
      // and must be packed segment-by-segment inside its own Wrap --
      // exactly the branch this fixture targets.
      final line = SongReaderLyricLineProjection(
        segments: List.generate(
          4,
          (_) => const SongReaderSegmentProjection(
            displayChord: 'C#m/G#',
            text: 'a',
          ),
        ),
      );

      // Measured 2026-07-28: rendered=210.0 estimated=226.0 (width=130,
      // ratio 1.08x). Same run structure and numbers as the "wide chords
      // over short syllables" fixture above -- at both 130px and 150px, a
      // single 'C#m/G#' chord (~84.6px) fits one run but any two never do,
      // so both widths pack down to 4 runs of one segment each. estimated
      // > rendered throughout, confirming the over-wide-group branch
      // (song_reader_fit.dart's `if (groupWidth > effectiveLineWidth)`)
      // handles a multi-segment group correctly, not just the
      // single-segment case the other fixtures exercise.
      await expectUpperBound(
        tester,
        line: line,
        width: 130.0,
        ceilingMultiplier: 1.15,
      );
    });

    testWidgets('chord-only instrumental bar of several wide chords', (
      tester,
    ) async {
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'C#m/G#', text: ''),
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11', text: ''),
          SongReaderSegmentProjection(displayChord: 'C#m/G#', text: ''),
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11', text: ''),
        ],
      );

      // PRE-FIX (2026-07-28): rendered=122.0 estimated=120.0 (width=150).
      // estimated < rendered by 2px -- RED under the one-sided contract.
      // Not a wrap-model bug (every segment's text is empty here, so no
      // word-wrap path is involved) -- it is SongLineView's own
      // `Padding(bottom: 2)` (widgets/song_line_view.dart), which is part of
      // the widget's measured render height but was never added on the
      // estimate side.
      //
      // POST-FIX (2026-07-28), after charging `lineWidgetBottomPadding`
      // (song_reader_fit.dart) once per lyric line: rendered=122.0
      // estimated=122.0 -- exact match, confirming the 2px gap was fully
      // explained by that one padding constant, not by an additional
      // font-metric imprecision needing its own separate margin.
      await expectUpperBound(
        tester,
        line: line,
        width: 150.0,
        ceilingMultiplier: 1.05,
      );
    });

    testWidgets('single-segment line long enough that its own Text wraps '
        'several times', (tester) async {
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(
            displayChord: 'D',
            text:
                'The quick brown fox jumps over the lazy dog again and '
                'again until the line finally wraps several times over',
          ),
        ],
      );

      // PRE-FIX (2026-07-28): rendered=434.0 estimated=368.0 (width=130).
      // estimated < rendered -- RED under the one-sided contract. Same
      // intra-segment wrap-count gap as the plain-lyric-line fixture
      // above: a single long run's own Text wraps into several real
      // visual lines that a plain ceil(lyricWidth / effectiveLineWidth)
      // division undercounts because it ignores word boundaries.
      //
      // POST-FIX (2026-07-28): rendered=434.0 estimated=514.0 (ratio 1.18x).
      // The greedy word-wrap model now over-counts this multi-wrap segment
      // (same flat per-character-average limitation as the first fixture,
      // amplified here since this segment wraps more times), but always
      // stays at or above the render.
      await expectUpperBound(
        tester,
        line: line,
        width: 130.0,
        ceilingMultiplier: 1.25,
      );
    });

    testWidgets('chord-split word (adjacent segments, no whitespace at the '
        'join)', (tester) async {
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'C', text: 'won'),
          SongReaderSegmentProjection(displayChord: 'G', text: 'der'),
          SongReaderSegmentProjection(displayChord: null, text: 'ful'),
        ],
      );

      // PRE-FIX (2026-07-28): rendered=54.0 estimated=56.0 (width=200).
      // estimated > rendered -- already satisfies the one-sided contract.
      // 'won'+'der'+'ful' merge into one word group (groupSegmentsIntoWords)
      // since none of the three segments end/start with whitespace, so the
      // estimator must not mistake this for three separate runs.
      //
      // POST-FIX (2026-07-28): rendered=54.0 estimated=58.0 (ratio 1.07x).
      // 'won'+'der'+'ful' has no space in the underlying text at all (the
      // three segments concatenate into a single word for word-wrap
      // purposes too), so the new greedy word-wrap model does not change
      // this fixture's shape -- the small increase is entirely the
      // lineWidgetBottomPadding margin.
      await expectUpperBound(
        tester,
        line: line,
        width: 200.0,
        ceilingMultiplier: 1.15,
      );
    });
  });

  group('SongLineView per-line estimate/render consistency under a '
      'non-default text scaler', () {
    // song_reader_char_metrics.dart used to measure with
    // TextScaler.noScaling while the rendered Text inherits
    // MediaQuery.textScalerOf(context): with system font scaling turned up,
    // the estimate stayed at 1.0x glyph width while the real render grew,
    // reintroducing an under-estimate -- an accessibility-relevant
    // correctness bug (a real user with large-text turned on is exactly the
    // user this must not overflow for), not a nicety. 1.5x is a scale a
    // real user with system-level large-text accessibility settings would
    // plausibly use.
    testWidgets(
      'plain lyric line still satisfies the one-sided contract at 1.5x '
      'text scaling',
      (tester) async {
        final line = SongReaderLyricLineProjection(
          segments: [
            const SongReaderSegmentProjection(
              displayChord: null,
              text:
                  'This is a long lyric line without any chords and it will '
                  'definitely wrap across several rows',
            ),
          ],
        );
        const textScaler = TextScaler.linear(1.5);

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 160.0,
          fontScale: fontScale,
          textScaler: textScaler,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 160.0,
          fontScale: fontScale,
        );

        // Measured 2026-07-28: rendered=492.0 estimated=660.0 (width=160,
        // textScaler=1.5x). estimated > rendered (ratio 1.34x) -- the
        // combination of the word-wrap model's own over-count (see the
        // plain-lyric-line fixture above, ratio 1.27x at scale 1.0) and
        // song_reader_fit.dart's `ambientTextScaleRatio` parameter (which
        // scales the flat chordRowHeight/lyricRowHeight row-height guesses by
        // the same ambient factor lyricCharWidth/chordCharWidth already bake
        // in via measureSongReaderCharWidths) never drops below the render.
        // Ceiling pinned at 1.5x, just above the measured ratio.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render even '
              'under a non-default ambient text scaler; rendered=$rendered '
              'estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.5),
          reason:
              'the estimate must not be uselessly loose under a '
              'non-default text scaler either; rendered=$rendered '
              'estimated=$estimated ceiling=${rendered * 1.5}',
        );
      },
    );
  });
}
