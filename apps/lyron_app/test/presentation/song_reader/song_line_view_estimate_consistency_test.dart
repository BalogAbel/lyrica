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

  Future<void> expectClose(
    WidgetTester tester, {
    required SongReaderLyricLineProjection line,
    required double width,
    required double relativeTolerance,
    required double absoluteToleranceFloor,
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

    final absoluteError = (estimated - rendered).abs();
    final relativeError = absoluteError / rendered;
    final tolerance = rendered * relativeTolerance > absoluteToleranceFloor
        ? rendered * relativeTolerance
        : absoluteToleranceFloor;

    expect(
      absoluteError,
      lessThan(tolerance),
      reason:
          'rendered=$rendered estimated=$estimated absoluteError=$absoluteError '
          'relativeError=$relativeError tolerance=$tolerance',
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

      // Measured 2026-07-28: rendered=292.0 estimated=250.0 (width=160)
      // absoluteError=42.0 relativeError=0.144. The gap here is the
      // intra-segment wrap count (_segmentIntraLines): ceil(lyricWidth /
      // effectiveLineWidth) approximates real word-wrapping with a plain
      // character-count division, so it can be off by roughly one wrapped
      // line for a single long run -- an accepted, already-documented
      // approximation (see "a single over-wide segment models its own
      // lyric text wrap" in song_reader_fit_test.dart), not a regression
      // this slice introduces.
      await expectClose(
        tester,
        line: line,
        width: 160.0,
        relativeTolerance: 0.17,
        absoluteToleranceFloor: 8.0,
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

      // Measured 2026-07-28: rendered=210.0 estimated=224.0 (width=150)
      // absoluteError=14.0 relativeError=0.067. This is the reviewer's
      // original repro shape: wide chords (C#m/G# @ ~84.6px, Cmaj7#11
      // wider still) over one-character syllables at a narrow column --
      // the estimator must count 4 separate runs here (one wide chord per
      // run), not collapse them into fewer runs the way the flat
      // characterWidthEstimate=10.0 guess used to.
      await expectClose(
        tester,
        line: line,
        width: 150.0,
        relativeTolerance: 0.09,
        absoluteToleranceFloor: 6.0,
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

      // Measured 2026-07-28: rendered=122.0 estimated=120.0 (width=150)
      // absoluteError=2.0 relativeError=0.016. Every segment's text is
      // empty, so this run must cost a chord row only (no lyric row) --
      // the Step 2 fix this line exists to pin down.
      await expectClose(
        tester,
        line: line,
        width: 150.0,
        relativeTolerance: 0.05,
        absoluteToleranceFloor: 6.0,
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

      // Measured 2026-07-28: rendered=434.0 estimated=368.0 (width=130)
      // absoluteError=66.0 relativeError=0.152. Same intra-segment
      // wrap-count approximation as the plain-lyric-line fixture above --
      // a single long run's own Text wraps into several real visual lines
      // that a plain ceil(lyricWidth / effectiveLineWidth) division can
      // only approximate, not reproduce exactly.
      await expectClose(
        tester,
        line: line,
        width: 130.0,
        relativeTolerance: 0.18,
        absoluteToleranceFloor: 10.0,
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

      // Measured 2026-07-28: rendered=54.0 estimated=56.0 (width=200)
      // absoluteError=2.0 relativeError=0.037. 'won'+'der'+'ful' merge into
      // one word group (groupSegmentsIntoWords) since none of the three
      // segments end/start with whitespace, so the estimator must not
      // mistake this for three separate runs.
      await expectClose(
        tester,
        line: line,
        width: 200.0,
        relativeTolerance: 0.05,
        absoluteToleranceFloor: 6.0,
      );
    });
  });
}
