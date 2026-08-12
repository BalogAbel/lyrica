import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
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
    tester.getSize(find.byType(SongLineView)).height +
    SongReaderMetrics.legacy.lineGap;

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
      'realistic annotated chord label ("N.C. (fade out)") wraps at a width '
      'that isolates the wrap model from the old clamp floor',
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
        // group above and for the same reason: this case must isolate its own
        // wrap-model bug from any effective-width mismatch. It was chosen to
        // sit above _lineItemHeight's then-120px clamp floor, which used to
        // make the estimator silently evaluate every narrower column at 120px
        // -- a wider effective line than the real render, and therefore an
        // under-estimate. That floor was lowered to [minEffectiveLineWidth]
        // on 2026-08-10 (song_reader_fit.dart), so widths below 120 are now
        // modelled honestly too; 130 is kept here because this fixture's
        // point is the wrap model, not the clamp.
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

  group('SongLineView per-line estimate/render consistency: breakable '
      'whitespace beyond a plain ASCII space (seventh review round)', () {
    // A seventh review round found _wordWrapLineCount (song_reader_fit.dart)
    // splits on `' '` -- the ASCII space only -- while Flutter's real line
    // breaker also breaks at TAB and at several Unicode space-separator
    // characters, and treats some characters as MANDATORY breaks rather
    // than mere break opportunities. text.split(' ') does not see any of
    // these, so a "word" containing one of them is measured as a single
    // unbreakable token; if that token's total width happens to fit within
    // effectiveLineWidth, the estimator reports ONE line where the real
    // render, breaking internally, needs several -- the same under-estimate
    // shape as the sixth round's chord-space bug, just reached through a
    // different separator each time.
    //
    // Verified empirically with a real TextPainter (not assumed from the
    // Unicode category name) before writing these fixtures. Two separate
    // properties were checked and must not be conflated:
    //
    // (1) Is the character a BREAK OPPORTUNITY at all?
    // TextPainter.getLineBoundary confirms TAB and every tested Unicode
    // space separator -- U+2000-U+200A, U+202F, U+205F, U+3000, U+1680,
    // U+200B, and even U+00A0 NO-BREAK SPACE despite the name -- place the
    // same trailing-whitespace line boundary a plain ASCII space does: all
    // of them break. A bare `\r` does NOT break at all (glued, no break
    // opportunity); `\r\n` and a lone `\n` each force exactly one MANDATORY
    // break (line ends immediately after the preceding content, the
    // separator itself consumed as the terminator) -- as do U+2028 LINE
    // SEPARATOR and U+2029 PARAGRAPH SEPARATOR.
    //
    // (2) Does the OLD code's oversized-single-token fallback
    // (`ceil(wordWidth / effectiveLineWidth)`, used when a separator isn't
    // recognized and the whole text becomes one "word") already happen to
    // match what the real render needs, or does it fall short?
    // This is NOT the same question as (1), and the answer surprisingly
    // splits the "no-break"-branded characters from the plain ones:
    // U+00A0 NO-BREAK SPACE and U+202F NARROW NO-BREAK SPACE both let
    // Flutter's real layout "steal" trailing characters of an oversized
    // following run across the break to fill the remaining line width
    // (confirmed via TextPainter.getLineBoundary showing line 1 ending
    // mid-word, e.g. "CCCCCCC CCCC" / "CCC CCCCCCC" for a
    // three-word run at 200px) -- real Flutter's line count for these two
    // characters converges on the SAME theoretical minimum
    // (`ceil(totalWidth / lineWidth)`) the old fallback already computes,
    // so testing with either of them, in every width/shape tried, produced
    // NO under-estimate at all (a "plausible-looking fixture that doesn't
    // reproduce," same lesson as the sixth round). TAB and every OTHER
    // tested Unicode space (U+2003 EM SPACE, U+2009 THIN SPACE, U+200B ZERO
    // WIDTH SPACE, U+3000 IDEOGRAPHIC SPACE) do NOT permit this stealing --
    // real Flutter treats the oversized run as a hard atomic unit needing
    // its own fresh line(s), same as this file's greedy model -- so the old
    // fallback's theoretical-minimum ceiling under-counts for all of them,
    // reproducing the defect. U+3000 IDEOGRAPHIC SPACE is used below as a
    // realistic, plausible separator (a real character a CJK-writing user
    // could type into a lyric or comment), not a synthetic corner case.

    testWidgets(
      "reviewer's repro: a chord label with an internal TAB wraps at the "
      'tab, not treated as one unbreakable token',
      (tester) async {
        // 'C\tCCCCCCCCCC' (12 chars: 'C', a tab, then 10 C's) -- the exact
        // shape as the sixth round's space repro ('C CCCCCCCCCC'), just
        // with a tab instead of a space. text.split(' ') does not see a tab
        // as a separator at all, so the old code measured this as ONE
        // 12-character word; at a 130px column that word's width happens
        // to fit under the oversized-single-word threshold differently than
        // the space case, reproducing an under-estimate through a shape the
        // sixth round's fix never touched.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(
              displayChord: 'C\tCCCCCCCCCC',
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

        // PRE-FIX (2026-07-28, seventh round): rendered=72.0 estimated=52.0
        // -- RED, the same under-estimate shape as the sixth round's space
        // repro, reached through a tab instead.
        // POST-FIX (splitting on the full breakable-whitespace class):
        // rendered=72.0 estimated=72.0 -- exact match.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'chord label contains a tab that forces a word-boundary wrap; '
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

    testWidgets(
      'a lyric line containing an IDEOGRAPHIC SPACE (U+3000) wraps at it, '
      'not treated as one unbreakable token',
      (tester) async {
        // Same shape again ('C' + separator + ten C\'s), this time a plain
        // lyric segment (no chord) with U+3000 IDEOGRAPHIC SPACE standing in
        // for the ASCII space -- a real Unicode space-separator character
        // (the full-width space CJK text uses), not a synthetic corner
        // case. text.split(' ') does not recognize it either, so the old
        // code measures the whole 12-character string as ONE token.
        //
        // NOTE on U+00A0 NO-BREAK SPACE, which might look like the more
        // obvious pick here: it WAS measured (see the group doc above) and
        // confirmed to genuinely break, same as this character -- but at
        // every width/shape tried, real Flutter's layout let the following
        // oversized run "steal" enough trailing characters across the break
        // to exactly match the old fallback's theoretical-minimum line
        // count, so it never actually went RED. U+3000 does not exhibit
        // that stealing (confirmed empirically, not assumed), so it is the
        // one that actually demonstrates the defect.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(
              displayChord: null,
              text: 'C　CCCCCCCCCC',
            ),
          ],
        );

        // width=150 -- at 130 (the width used by every other fixture in
        // this file) this particular shape's old-fallback line count
        // already happens to match the real render (both compute 2); 150 is
        // the width at which real Flutter's line breaker needs a genuine
        // 3rd line (measured directly: real render breaks into "C", then
        // the ten-C run splits across two more lines) while the old
        // fallback's ceil(totalWidth / 150) still only reaches 2.
        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 150.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 150.0,
          fontScale: fontScale,
        );

        // PRE-FIX (2026-07-28, seventh round): rendered=72.0 estimated=60.0
        // -- RED, the same under-estimate shape as the tab repro above,
        // reached through a Unicode space instead.
        // POST-FIX: rendered=72.0 estimated=84.0 (ratio 1.17x) -- the greedy
        // model, once it recognizes U+3000 as breakable, puts "C" on its own
        // line same as the render, but (like the sixth round's chord-space
        // fix) does not model Flutter's "steal a few characters back onto
        // the previous line" optimization, so it is looser here than the
        // exact TAB match above.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'lyric segment contains an IDEOGRAPHIC SPACE that Flutter '
              'breaks at; rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.25),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.25}',
        );
      },
    );

    testWidgets(
      'a lyric line containing an embedded newline is a MANDATORY break, '
      'not a mere break opportunity',
      (tester) async {
        // '\n' forces the line to end immediately after the preceding
        // content regardless of remaining width, and starts the next
        // segment on a fresh line -- not "pack until it no longer fits"
        // like a breakable-whitespace opportunity.
        //
        // No ASCII space anywhere in this text ('Verse' + '\n' + 'Chorus',
        // 12 characters total) -- text.split(' ') therefore sees the whole
        // thing as ONE "word" (the '\n' is just an ordinary character to
        // the old code, contributing its own charWidth like any other
        // glyph), and at a wide column (300px) that one 12-character
        // "word"'s flat width fits comfortably under effectiveLineWidth, so
        // the old code reports exactly ONE line. (An earlier version of
        // this fixture used two ASCII-space-separated halves at this same
        // width and did NOT reproduce the defect: the old greedy algorithm,
        // while not modelling '\n' as a break at all, still happened to
        // compute 2 lines from ordinary width-driven wrapping of its OTHER
        // words, coincidentally matching the mandatory-break count. Cutting
        // out every ASCII space removes that coincidence and isolates the
        // mandatory-break defect on its own.) The real render forces
        // exactly two lines regardless of the column being wide enough for
        // both halves together.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(
              displayChord: null,
              text: 'Verse\nChorus',
            ),
          ],
        );

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 300.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 300.0,
          fontScale: fontScale,
        );

        // PRE-FIX (2026-07-28, seventh round): rendered=52.0 estimated=36.0
        // -- RED, a genuine under-estimate: the old code sees one
        // comfortably-fitting 12-character "word" and reports 1 line, while
        // the real render, honoring the mandatory break, needs 2.
        // POST-FIX (splitting on _mandatoryLineBreak first, each side
        // wrapped independently): rendered=52.0 estimated=60.0 (ratio
        // 1.15x) -- each mandatory-delimited chunk ("Verse", "Chorus") is
        // charged its own full lyricRowHeight, matching the render's own
        // per-line charging.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'lyric segment contains an embedded mandatory newline; '
              'rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.25),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.25}',
        );
      },
    );

    testWidgets(
      'a lyric line containing an embedded VERTICAL TAB (U+000B) is ALSO a '
      'MANDATORY break, not just \\n',
      (tester) async {
        // Same isolation reasoning as the '\n' case above (no ASCII space
        // anywhere in the text, so the old code sees one comfortably-fitting
        // "word" and reports 1 line): a coordinator follow-up asked whether
        // U+000B (VERTICAL TAB) and U+000C (FORM FEED) are ALSO honored as
        // mandatory breaks by Flutter, since this helper's contract is an
        // upper bound over arbitrary strings, not just trusted ChordPro
        // output. Measured with a real TextPainter first:
        // TextPainter.getLineBoundary places U+000B's line boundary
        // identically to '\n' (line ends immediately after the preceding
        // content), and a double U+000B produces a genuine blank line the
        // same way 'AAAA\n\nBBBB' does -- confirmed to behave exactly like
        // '\n', not merely "close enough." U+000C (FORM FEED) was measured
        // the same way with the same result; only one of the two is
        // exercised here since both are identical in every way that
        // matters to this helper.
        final line = SongReaderLyricLineProjection(
          segments: [
            SongReaderSegmentProjection(
              displayChord: null,
              text: 'VerseChorus',
            ),
          ],
        );

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 300.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 300.0,
          fontScale: fontScale,
        );

        // PRE-FIX (2026-07-28, coordinator follow-up): rendered=52.0
        // estimated=36.0 -- RED, the same shape as the '\n' case: U+000B
        // was not yet in _mandatoryLineBreak, so the old code saw one
        // comfortably-fitting "word" and reported 1 line.
        // POST-FIX: rendered=52.0 estimated=60.0 -- same numbers as the
        // '\n' case, since U+000B is now in _mandatoryLineBreak alongside
        // it.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'lyric segment contains an embedded VERTICAL TAB mandatory '
              'break; rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.25),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.25}',
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
        // before the non-linear-scaler fix.
        //
        // Re-measured 2026-08-10, after song_reader_fit.dart's estimator
        // started splitting segments at word boundaries before grouping
        // (mirroring the renderer, see splitSegmentsAtWordBoundaries):
        // rendered=610.0 estimated=1026.0 (ratio 1.68x). Word-granularity
        // groups accumulate more per-group packing conservatism than the
        // old segment-granularity groups did, on both sides of this
        // fixture -- rendered grew too (492.0 -> 610.0) because splitting
        // this line at word boundaries changes where it actually wraps at
        // width=160. estimated still never drops below rendered. Ceiling
        // pinned at 1.75x, just above the new measured ratio.
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
          lessThan(rendered * 1.75),
          reason:
              'the estimate must not be uselessly loose under a '
              'non-default text scaler either; rendered=$rendered '
              'estimated=$estimated ceiling=${rendered * 1.75}',
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
      //
      // Re-measured 2026-08-10, after song_reader_fit.dart's estimator
      // started splitting segments at word boundaries before grouping
      // (mirroring the renderer, see splitSegmentsAtWordBoundaries):
      // rendered=610.0 (unchanged -- this fixture already wrapped at word
      // boundaries pre-fix, since the line has no embedded chords to split
      // words apart) estimated=1279.8 (ratio 2.10x). Word-granularity
      // groups compound the peak ~1.9x non-linear factor per group more
      // than segment-granularity groups did; estimated still never drops
      // below rendered. Ceiling pinned at 2.15x, just above the new
      // measured ratio.
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
        lessThan(rendered * 2.15),
        reason:
            'the estimate must not be uselessly loose under a non-linear '
            'text scaler either; rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 2.15}',
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
        //
        // Re-measured 2026-08-10, after song_reader_fit.dart's estimator
        // started splitting segments at word boundaries before grouping
        // (mirroring the renderer, see splitSegmentsAtWordBoundaries):
        // rendered=610.0 estimated=925.604 (ratio 1.52x). Word-granularity
        // groups accumulate more per-group packing conservatism than the
        // old segment-granularity groups did, on both sides of this
        // fixture -- rendered grew too (488.0 -> 610.0) because splitting
        // this line at word boundaries changes where it actually wraps at
        // width=200/fontScale=1.3. estimated still never drops below
        // rendered. Ceiling pinned at 1.6x, just above the new measured
        // ratio.
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
          lessThan(rendered * 1.6),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.6}',
        );
      },
    );
  });

  group('SongLineView per-line estimate/render consistency: word-boundary '
      'wrapping (splitSegmentsAtWordBoundaries)', () {
    testWidgets(
      "reproduction: ChordPro splits a word at the chord ('Igédben'), the "
      'word must not break at the chord join',
      (tester) async {
        // The exact defect from docs/specs/2026-08-09-song-presentation.md,
        // "Defect pulled into scope": ChordPro places the G#m chord inside
        // "Igédben", producing two segments ('...Igé' / 'dben bízok én')
        // with no whitespace at the join. Before word-boundary splitting,
        // groupSegmentsIntoWords could only see segment boundaries, so the
        // whole line was one giant group; now splitSegmentsAtWordBoundaries
        // cuts each segment at its OWN internal word boundaries first, so
        // 'Igédben' (spanning the segment join) stays a single word group
        // while the other words on the line are free to wrap independently.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(
              displayChord: 'E',
              text: 'Kegyelmed elég, több, mint elég, Igé',
            ),
            SongReaderSegmentProjection(
              displayChord: 'G#m',
              text: 'dben bízok én',
            ),
          ],
        );

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 375.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 375.0,
          fontScale: fontScale,
        );

        // Measured 2026-08-10: rendered=136.0 estimated=148.0 (width=375,
        // ratio 1.09x). estimated > rendered -- the greedy word-wrap model's
        // usual per-group over-count (see the plain wrapping fixtures
        // above), not a defect. Ceiling pinned at 1.1x, just above the
        // measured ratio.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render for the '
              "reproduction shape (ChordPro splitting 'Igédben' at its "
              'chord); rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.1),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.1}',
        );
      },
    );

    testWidgets(
      'a word split across three segments stays one group across a wrap '
      'point',
      (tester) async {
        // 'al' + 'ph' + 'a beta' -- three segments with no whitespace at the
        // al/ph join, so splitSegmentsAtWordBoundaries leaves 'al' and 'ph'
        // untouched (each is already a single word-piece) while it splits
        // the third segment's internal space into 'a ' and 'beta'.
        // groupSegmentsIntoWords then merges al+ph+'a ' into one 'alpha '
        // group (three segments, one word) and 'beta' into its own group.
        // At a narrow enough width the outer Wrap must break between the
        // two groups -- the atomic-group architecture (each group is a
        // single child of the outer Wrap) means 'alpha' can never itself be
        // split across that break, even though it is built from three
        // separate segments each carrying its own chord.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(displayChord: 'C', text: 'al'),
            SongReaderSegmentProjection(displayChord: 'G', text: 'ph'),
            SongReaderSegmentProjection(displayChord: 'Am', text: 'a beta'),
          ],
        );

        final rendered = await _renderAndMeasure(
          tester,
          line: line,
          viewMode: viewMode,
          width: 90.0,
          fontScale: fontScale,
        );
        final estimated = _estimatedLineHeight(
          tester,
          line: line,
          viewMode: viewMode,
          width: 90.0,
          fontScale: fontScale,
        );

        // Measured 2026-08-10: rendered=136.0 estimated=148.0 (width=90,
        // ratio 1.09x) -- the render puts 'al'+'ph' on one row, the split
        // word's tail 'a ' on a second, and 'beta' on a third.
        //
        // This fixture is the one that caught the effective-width clamp bug:
        // width=90 is BELOW the estimator's old 120px floor, so
        // flowBlockHeight modelled a 120px line for a 90px render, saw the
        // 99px 'alpha' group fit on one row where the real 90px column
        // splits it across two, and returned 92px against a 136px render --
        // an under-estimate, the exact failure this suite exists to catch.
        // The floor is now [minEffectiveLineWidth] (song_reader_fit.dart),
        // a pure numeric guard that can never raise a real column width.
        // Ceiling pinned at 1.1x.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render when a '
              'single word is split across three segments and the line '
              'wraps between that word and the next; rendered=$rendered '
              'estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.1),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.1}',
        );
      },
    );

    testWidgets(
      'a single word longer than the line still wraps inside itself via the '
      'over-wide-group ConstrainedBox fallback',
      (tester) async {
        // No whitespace anywhere in this ~40-character text -- a genuinely
        // unbreakable single word is the one case where a mid-word break is
        // still the correct behaviour (there is no word boundary to prefer
        // instead). splitSegmentsAtWordBoundaries leaves a single-piece
        // segment untouched (song_reader_word_groups.dart: `if
        // (pieces.length == 1) { result.add(segment); continue; }`), so
        // groupSegmentsIntoWords produces one group containing this one
        // segment, and that group's own width comfortably exceeds a 130px
        // column -- forcing the renderer's inner, over-wide-group
        // ConstrainedBox/Wrap fallback (widgets/song_line_view.dart's
        // per-group `ConstrainedBox(constraints: BoxConstraints(maxWidth:
        // maxWidth))`) to wrap the segment's own Text internally.
        final line = SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(
              displayChord: null,
              text: 'abcdefghijklmnopqrstuvwxyzabcdefghijkl',
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

        // Measured 2026-08-10: rendered=132.0 estimated=132.0 (width=130,
        // ratio 1.00x) -- exact match. estimated never drops below
        // rendered. Ceiling pinned at 1.1x.
        expect(
          estimated,
          greaterThanOrEqualTo(rendered),
          reason:
              'the estimate must never fall below the real render for a '
              'single word longer than the line, wrapping inside itself; '
              'rendered=$rendered estimated=$estimated',
        );
        expect(
          estimated,
          lessThan(rendered * 1.1),
          reason:
              'the estimate must not be uselessly loose either; '
              'rendered=$rendered estimated=$estimated '
              'ceiling=${rendered * 1.1}',
        );
      },
    );
  });
}
