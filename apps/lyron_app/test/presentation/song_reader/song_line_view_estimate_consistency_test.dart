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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SongLineView(
              line: line,
              viewMode: viewMode,
              sharedFontScale: fontScale,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _measuredLineHeight(tester);
}

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
}
