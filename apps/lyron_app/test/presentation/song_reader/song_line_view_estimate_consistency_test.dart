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

// ---------------------------------------------------------------------------
// Non-linear TextScaler fixture.
// ---------------------------------------------------------------------------
//
// `TextScaler.linear(x)` scales every font size by the same ratio `x`, so
// flattening it to a single probe -- `textScaler.scale(1.0)` -- and
// multiplying every quantity by that one number happens to be correct: the
// ratio at 1px equals the ratio at any other size. Real non-linear scalers
// (Android 14+ "non-linear font scaling") do not have this property.
//
// This scaler models a "hump" shape: real accessibility scaling curves
// typically boost near-illegible TINY text only modestly, boost COMMON
// READING sizes (roughly the 12-16px range this reader's directive/chord/
// lyric styles live in) the MOST, and taper back down for already-large
// text (headlines, this reader's 22px section header) that doesn't need as
// much help. Concretely: 1.1x at/below 2px, rising to a 1.9x peak at 14px,
// falling back to 1.2x at/above 22px, linearly interpolated in between.
//
// This shape is what makes `textScaler.scale(1.0)` -- the flattened probe
// the old ambientTextScaleRatio bug evaluated at, 1.0 being comfortably in
// the near-zero "modest boost" region -- a genuine UNDER-estimate of the
// real ratio at every one of this reader's actual text styles (1.1x at the
// probe vs. ~1.7-1.9x at the chord/lyric/directive styles' real sizes),
// not just "a different number": using the flattened 1.1x in place of each
// style's own ~1.7-1.9x factor charges LESS row height than the real render
// needs, reproducing the reviewer's under-estimate directly. A simple
// monotonically-decreasing curve (small sizes boosted more than large, no
// hump) was tried first and could NOT reproduce a genuine under-estimate
// here: since `scale(1.0)` would then be the curve's global maximum, the
// flattened ratio would only ever be a conservative OVER-estimate of every
// larger style's real ratio -- safe, if uselessly loose, never the actual
// failure mode. The hump shape is also the more realistic model: it is not
// how a font-scaling curve for READABILITY would be designed to boost
// microscopic decorative text harder than the body copy people actually
// read.
class _NonLinearTextScaler extends TextScaler {
  const _NonLinearTextScaler();

  static const _tinySize = 2.0;
  static const _tinyFactor = 1.1;
  static const _peakSize = 14.0;
  static const _peakFactor = 1.9;
  static const _largeSize = 22.0;
  static const _largeFactor = 1.2;

  @override
  double scale(double fontSize) {
    if (fontSize <= _tinySize) return fontSize * _tinyFactor;
    if (fontSize <= _peakSize) {
      final t = (fontSize - _tinySize) / (_peakSize - _tinySize);
      return fontSize * (_tinyFactor + (_peakFactor - _tinyFactor) * t);
    }
    if (fontSize <= _largeSize) {
      final t = (fontSize - _peakSize) / (_largeSize - _peakSize);
      return fontSize * (_peakFactor + (_largeFactor - _peakFactor) * t);
    }
    return fontSize * _largeFactor;
  }

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => scale(_peakSize) / _peakSize;

  @override
  bool operator ==(Object other) => other is _NonLinearTextScaler;

  @override
  int get hashCode => runtimeType.hashCode;
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
    textScale: charWidths.textScale,
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

  group('SongLineView per-line estimate/render consistency: chord label '
      'wraps within its own run', () {
    // `_SongLineSegmentView`'s chord `Text` has no `ConstrainedBox` of its
    // own (widgets/song_line_view.dart) -- only the lyric `Text` below it
    // gets one -- but `RenderWrap` constrains EVERY child's main-axis size
    // to its own `constraints.maxWidth` regardless (Flutter SDK,
    // `RenderWrap._computeRuns`: `BoxConstraints(maxWidth:
    // constraints.maxWidth)` applied uniformly to every child, whether or
    // not that child wraps itself in its own ConstrainedBox). So a chord
    // label wider than the line wraps internally onto a second (or
    // further) line, growing the segment taller -- this is reachable with
    // NO non-linear scaler at all, just a long enough chord label at a
    // narrow enough column, so these cases use the default (no custom)
    // TextScaler to isolate the mechanism from the non-linear-scaler group
    // below.
    //
    // width=130 -- ABOVE _lineItemHeight's own `columnWidth.clamp(120.0,
    // 1200.0)` floor (song_reader_fit.dart), so the estimator's
    // effectiveLineWidth matches the real column width exactly rather than
    // being clamped up to 120 while the real widget still lays out at a
    // narrower width than that. A width below 120 would make the estimator
    // and the render disagree on the width being tested, not just on the
    // chord-wrap math this group exists to exercise.

    testWidgets('a long chord label alone must wrap at a narrow width', (
      tester,
    ) async {
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11/G', text: ''),
        ],
      );

      // 'Cmaj7#11/G' (10 chars -- a slash chord roughly the length of the
      // coordinator's "ten-character chord" example) at the default
      // (unscaled) chord style is ~141px wide (see
      // measureSongReaderCharWidths doc, ~14.1px/char) -- wider than a
      // 130px column, forcing ceil(141 / 130) = 2 chord rows.
      final rendered = await _renderAndMeasure(
        tester,
        line: line,
        viewMode: viewMode,
        width: 130.0,
        fontScale: fontScale,
      );
      final estimated = _estimatedLineHeight(
        tester,
        line: line,
        viewMode: viewMode,
        width: 130.0,
        fontScale: fontScale,
      );

      // PRE-FIX (2026-07-28): rendered=52.0 estimated=32.0 -- RED, a
      // genuine under-estimate (the estimator assumed the chord label
      // always fit on one row). POST-FIX: rendered=52.0 estimated=52.0 --
      // exact match.
      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render when a '
            'chord label alone must wrap onto multiple lines; '
            'rendered=$rendered estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * 1.3),
        reason:
            'the estimate must not be uselessly loose either; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 1.3}',
      );
    });

    testWidgets(
      'a wrapping chord label over a lyric syllable combines chord rows, '
      'the gap, and the lyric line correctly',
      (tester) async {
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(displayChord: 'Cmaj7#11/G', text: 'a'),
          ],
        );

        // Same wrapping chord as above, now with a one-character lyric
        // syllable under it -- exercises _segmentRowHeight's
        // chordRows*chordRowHeight + gap + lyricLines*lyricRowHeight
        // combination, not just the chord-only path.
        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 130.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 130.0,
          fontScale: fontScale,
        );

        // PRE-FIX (2026-07-28): rendered=74.0 estimated=58.0 -- RED, same
        // under-estimate as above. POST-FIX: rendered=74.0 estimated=78.0
        // (ratio 1.05x).
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'wrapping chord label sits over lyric text; rendered=$rendered '
              'estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.3),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.3}',
        );
      },
    );
  });

  group('SongLineView per-line estimate/render consistency: chord label '
      'containing a space wraps at the space, not evenly', () {
    // A sixth review round found the chord self-wrap model
    // (song_reader_fit.dart's `_segmentRowHeight`) undercounts whenever the
    // chord label itself contains a space: it counted wrapped chord rows as
    // `ceil(chordWidth / effectiveLineWidth)`, a plain even division over the
    // label's TOTAL width. That is only correct for a label with no internal
    // break points. Flutter's `Text` breaks at spaces same as any other text
    // -- a chord label CAN contain one (`N.C.`, `C (capo 2)`, or the
    // reviewer's synthetic case below), and once it does, even division
    // undercounts for the exact same reason `_segmentIntraLines`'s old
    // per-character division undercounted lyric text: it lets the estimator
    // pack more characters onto a row than real word-boundary breaking
    // would allow.
    testWidgets(
      "reviewer's repro: a chord label with an internal space wraps at "
      'the space, not by even character division',
      (tester) async {
        // 'C CCCCCCCCCC' (12 chars: 'C', a space, then 10 C's) at a 130px
        // column: real layout puts 'C' on its own row, then wraps
        // 'CCCCCCCCCC' (itself wider than 130px) onto two more rows -- three
        // rows total. Even division over the label's total width instead
        // saw ceil(12 chars worth of width / 130) = 2, one row short.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(displayChord: 'C CCCCCCCCCC', text: ''),
          ],
        );

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 130.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 130.0,
          fontScale: fontScale,
        );

        // PRE-FIX (2026-07-28): rendered=72.0 estimated=52.0 -- RED, a
        // genuine under-estimate (even division counts 2 chord rows over
        // the label's full width; the real render breaks at the space and
        // needs 3). POST-FIX: rendered=72.0 estimated=72.0 -- exact match
        // (this label's own words happen to line up exactly with the
        // greedy word-wrap model's row boundaries; ceiling pinned tight).
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'chord label contains a space that forces a word-boundary '
              'wrap; rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.05),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.05}',
        );
      },
    );

    testWidgets(
      'realistic annotated chord label ("N.C. (fade out)") must wrap at a '
      'width above the 120px clamp floor',
      (tester) async {
        // A parenthetical performance annotation appended to a chord label
        // is a realistic shape (not just the reviewer's all-C synthetic
        // repro above) -- "N.C." (no chord) followed by a performance
        // direction is standard lead-sheet notation. Measured directly with
        // a real TextPainter at this style/width: real Flutter line-breaking
        // fills as many characters of an over-wide word onto the PRECEDING
        // line as still fit, rather than always starting the oversized word
        // on a fresh line the way [_wordWrapLineCount]'s simpler model
        // assumes -- so not every spaced label reproduces an under-estimate
        // at every width (a real quirk of the real line breaker, not a
        // defect in the fix below, which only needs to stay >= the render,
        // never match it exactly). This label at this width does reproduce
        // it: "N.C." takes its own row, and "(fade out)" -- wider than the
        // column on its own -- wraps onto two more, three rows total, while
        // even division over the label's full width undercounts to two.
        //
        // width=130 -- same as the "chord label wraps within its own run"
        // group above and for the same reason: it must stay ABOVE
        // _lineItemHeight's own `columnWidth.clamp(120.0, 1200.0)` floor, or
        // the estimator would silently evaluate at a wider effective column
        // than the real render uses, confounding this case's own wrap-model
        // bug with an unrelated clamp mismatch.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(
              displayChord: 'N.C. (fade out)',
              text: '',
            ),
          ],
        );

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 130.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 130.0,
          fontScale: fontScale,
        );

        // PRE-FIX (2026-07-28): rendered=72.0 estimated=52.0 -- RED, same
        // under-estimate shape as the repro above (even division over the
        // label's total width undercounts the leading short word's own
        // row). POST-FIX: rendered=72.0 estimated=72.0 -- exact match,
        // ceiling pinned tight.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render for a '
              'realistic annotated chord label that must wrap; '
              'rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.05),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.05}',
        );
      },
    );
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
        // song_reader_fit.dart's `SongReaderFitTextScale.factorFor` (which
        // scales the flat chordRowHeight/lyricRowHeight row-height guesses,
        // and converts lyricCharWidth/chordCharWidth, by the real effective
        // factor at each style's own base size) never drops below the
        // render. `TextScaler.linear(1.5)` is linear, so factorFor gives the
        // same 1.5x at every base size -- these numbers are unchanged from
        // before the non-linear-scaler fix. Ceiling pinned at 1.5x, just
        // above the measured ratio.
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

  group('SongLineView per-line estimate/render consistency under a '
      'NON-LINEAR text scaler', () {
    // A fifth review round found the estimator still undershoots under a
    // NON-linear TextScaler: song_reader_char_metrics.dart flattened the
    // ambient scaler to `textScaler.scale(1.0)` -- a ratio measured at a 1px
    // probe -- and song_reader_fit.dart multiplied every row-height constant
    // by that single number regardless of the style's actual rendered size.
    // For `TextScaler.linear(x)` this coincides with the real ratio at every
    // size (which is why the 1.5x group above passed), but a non-linear
    // scaler has a different real ratio at every size, so collapsing it to
    // one flat number is wrong. _NonLinearTextScaler models this with a hump
    // shape (see its doc comment for why a hump, not a monotonic curve, is
    // needed to reproduce a genuine under-estimate).
    //
    // PRE-FIX (2026-07-28), captured by temporarily reverting
    // song_reader_fit.dart / song_reader_char_metrics.dart to their
    // pre-non-linear-scaler-fix state and re-running just this group:
    //   chord-only bar (fontScale=1.0, width=260):     rendered=194.0 estimated=130.0  RED (estimated < rendered)
    //   plain lyric line (fontScale=1.0, width=160):   rendered=610.0 estimated=566.4  RED (estimated < rendered)
    //   plain lyric line (fontScale=1.3, width=200):   rendered=488.0 estimated=732.72 RED (exceeds ceiling; not
    //                                                   an under-estimate here, but still proves the flattened
    //                                                   ratio produces wrong numbers once fontScale != 1.0)
    // POST-FIX numbers are documented on each case below.
    const textScaler = _NonLinearTextScaler();

    testWidgets("chord-only instrumental bar (reviewer's repro shape) under a "
        'non-linear text scaler', (tester) async {
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'C#m/G#', text: ''),
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11', text: ''),
          SongReaderSegmentProjection(displayChord: 'C#m/G#', text: ''),
          SongReaderSegmentProjection(displayChord: 'Cmaj7#11', text: ''),
        ],
      );

      // width=150 -- narrow enough that at this scaler 'Cmaj7#11' (scaled
      // to ~214px, near the 14px style's 1.9x peak factor) exceeds the line
      // width. `_SongLineSegmentView`'s chord
      // `Text` has no `ConstrainedBox` of its own (only the lyric `Text`
      // does, see widgets/song_line_view.dart), but `RenderWrap` still
      // constrains EVERY child's main-axis size to its own
      // `constraints.maxWidth` regardless (see
      // `RenderWrap._computeRuns` in the Flutter SDK), so the chord label
      // wraps internally onto a second line here -- exercising
      // song_reader_fit.dart's `_segmentRowHeight` chord-wrap modelling,
      // not just the effectiveFactor conversion.
      final rendered = await _renderAndMeasure(
        tester,
        line: line,
        viewMode: viewMode,
        width: 150.0,
        fontScale: fontScale,
        textScaler: textScaler,
      );
      final estimated = _estimatedLineHeight(
        tester,
        line: line,
        viewMode: viewMode,
        width: 150.0,
        fontScale: fontScale,
      );

      // POST-FIX (2026-07-28): rendered=346.0 estimated=346.0 -- exact
      // match. Ceiling pinned at 1.3x, comfortably above.
      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render under a '
            'non-linear text scaler; rendered=$rendered '
            'estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * 1.3),
        reason:
            'the estimate must not be uselessly loose under a non-linear '
            'text scaler either; rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 1.3}',
      );
    });

    testWidgets('plain wrapping lyric line under a non-linear text scaler', (
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

      // POST-FIX (2026-07-28): rendered=610.0 estimated=881.4 (ratio
      // 1.44x) -- the word-wrap model's own over-count (see the linear
      // fixtures above) compounds with the peak ~1.9x factor at this
      // style's 16px base size, but estimated stays above rendered.
      // Ceiling pinned at 1.5x, just above the measured ratio.
      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'the estimate must never fall below the real render under a '
            'non-linear text scaler; rendered=$rendered '
            'estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * 1.5),
        reason:
            'the estimate must not be uselessly loose under a non-linear '
            'text scaler either; rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 1.5}',
      );
    });

    testWidgets(
      'plain wrapping lyric line under a non-linear text scaler AND a '
      'non-1.0 sharedFontScale (in-app font control not at its default)',
      (tester) async {
        const scaledFontScale = 1.3;
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

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 200.0,
          fontScale: scaledFontScale,
          textScaler: textScaler,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 200.0,
          fontScale: scaledFontScale,
        );

        // POST-FIX (2026-07-28): rendered=488.0 estimated=622.74 (ratio
        // 1.28x). PRE-FIX this same case was 732.72 (ratio 1.50x, over the
        // 1.5x ceiling) -- fixing the width conversion (lyricCharWidth is
        // now converted via the factor at the REAL candidate rendered size,
        // `textScaler.scale(lyricBaseFontSize * sharedFontScale)`, instead
        // of the old `fontScale` alone assuming the ambient-baked-in
        // measurement scaled proportionally) tightens the estimate back
        // toward the render without ever dropping below it.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render under a '
              'non-linear text scaler at a non-1.0 sharedFontScale; '
              'rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.5),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.5}',
        );
      },
    );
  });
}
