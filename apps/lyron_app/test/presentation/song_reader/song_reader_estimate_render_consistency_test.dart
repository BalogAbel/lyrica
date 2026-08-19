import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------
//
// Mirrors real ChordPro output shapes rather than synthetic edge cases:
//   - several sections (2 verses, a chorus, a bridge)
//   - long chorded lyric lines that actually wrap at a 375px-wide viewport
//   - one chord-only line (an instrumental bar: chords, no lyric text) --
//     the renderer draws only a chord row for this, never a lyric row
//   - one blank separator line using the EXACT shape the real parser emits
//     for an empty source line: `LyricLine(segments: [LyricSegment(text: '')])`
//     (see lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart:31)
//     -- the renderer collapses this to near-zero height, which is the
//     "collapsing empty elements" case the estimator must mirror.
SongReaderProjection _buildFixtureProjection({double fontScale = 1.0}) {
  final sections = <SongSection>[
    SongSection(
      kind: SongSectionKind.verse,
      label: 'Verse',
      number: 1,
      lines: [
        LyricLine(
          segments: const [
            LyricSegment(
              leadingChord: 'G',
              text: 'A long lyric line that will wrap across multiple rows',
            ),
          ],
        ),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'C', text: 'Another wrapping line '),
            LyricSegment(
              leadingChord: 'D',
              text: 'with a mid-line chord change that also wraps around',
            ),
          ],
        ),
        // Blank separator line -- exact shape ChordproParser emits for an
        // empty source line (chordpro_parser.dart:31).
        LyricLine(segments: const [LyricSegment(text: '')]),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'Em', text: 'Shorter line here'),
          ],
        ),
      ],
    ),
    SongSection(
      kind: SongSectionKind.chorus,
      label: 'Chorus',
      number: 1,
      lines: [
        LyricLine(
          segments: const [
            LyricSegment(
              leadingChord: 'C',
              text: 'Chorus line one is fairly long and wraps as well',
            ),
          ],
        ),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'G', text: 'Chorus line two, shorter'),
          ],
        ),
        // Chord-only instrumental bar: chords with no lyric text under any
        // of them. The renderer draws just the chord row, no lyric row.
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'Em', text: ''),
            LyricSegment(leadingChord: 'C', text: ''),
            LyricSegment(leadingChord: 'G', text: ''),
            LyricSegment(leadingChord: 'D', text: ''),
          ],
        ),
      ],
    ),
    SongSection(
      kind: SongSectionKind.verse,
      label: 'Verse',
      number: 2,
      lines: [
        LyricLine(
          segments: const [
            LyricSegment(
              leadingChord: 'G',
              text: 'Second verse opens with another long lyric line here',
            ),
          ],
        ),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'D', text: 'A shorter closing line'),
          ],
        ),
      ],
    ),
    SongSection(
      kind: SongSectionKind.bridge,
      label: 'Bridge',
      number: null,
      lines: [
        LyricLine(
          segments: const [
            LyricSegment(
              leadingChord: 'Am',
              text: 'Bridge line that is also long enough to wrap around',
            ),
          ],
        ),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'F', text: 'Final bridge line'),
          ],
        ),
      ],
    ),
  ];

  return SongReaderProjection(
    song: ParsedSong(
      title: 'Consistency Fixture',
      sourceKey: 'G',
      sections: sections,
      diagnostics: const [],
    ),
    state: SongReaderState(sharedFontScale: fontScale),
  );
}

// ---------------------------------------------------------------------------
// Chord-heavy fixture
// ---------------------------------------------------------------------------
//
// Same real-parser shapes as _buildFixtureProjection, but every chord is a
// wide extended/slash label (Cmaj7#11, F#m7b5, Bbsus4/D, G#dim7, Eb6/9 --
// 5-9 chars) instead of the 1-2 char chords above. This is the shape the
// estimator got wrong before the chord-width fix: a chord-only segment's
// width came from its (empty) lyric text alone, and a chord wider than its
// lyric syllable was undercounted.
//   - TWO chord-only instrumental bars of EIGHTY wide chords each (no lyric
//     text under any of them). The count is deliberately large: lyric-only
//     width counting (the bug) sizes a chord-only line as exactly one row
//     no matter how many chords it holds, so the gap between that flat,
//     count-independent estimate and the real multi-row render grows
//     without bound as segment count grows -- a smaller count (tried: 4, 8,
//     20) left the fixed estimator's own font-metric imprecision (see
//     below) large enough to mask the difference between fixed and
//     reverted code, so the count was raised until reverting the fix
//     clearly produced a larger error than leaving it fixed.
//   - a line where each wide chord sits over a single short syllable, so the
//     chord is clearly wider than the lyric under it
//   - the same blank-separator-line shape the real parser emits
SongReaderProjection _buildChordHeavyFixtureProjection({
  double fontScale = 1.0,
}) {
  final sections = <SongSection>[
    SongSection(
      kind: SongSectionKind.verse,
      label: 'Verse',
      number: 1,
      lines: [
        // Each wide chord sits over a single short syllable -- the segment
        // column is as wide as the chord, not the one-character lyric.
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'Cmaj7#11', text: 'a'),
            LyricSegment(leadingChord: 'F#m7b5', text: 'b'),
            LyricSegment(leadingChord: 'Bbsus4/D', text: 'c'),
          ],
        ),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'G#dim7', text: 'Some words here'),
          ],
        ),
        // Blank separator line -- exact shape ChordproParser emits for an
        // empty source line (chordpro_parser.dart:31).
        LyricLine(segments: const [LyricSegment(text: '')]),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'Eb6/9', text: 'Shorter line here'),
          ],
        ),
      ],
    ),
    SongSection(
      kind: SongSectionKind.chorus,
      label: 'Chorus',
      number: 1,
      lines: [
        LyricLine(
          segments: const [
            LyricSegment(
              leadingChord: 'Cmaj7#11',
              text: 'Chorus line with a wide chord up front',
            ),
          ],
        ),
        // Chord-only instrumental bar: EIGHTY wide chords, no lyric text
        // under any of them. The renderer draws just the chord row, no
        // lyric row, and eighty wide labels must wrap into many rows at
        // 375px width.
        LyricLine(
          segments: List.generate(
            80,
            (i) => LyricSegment(
              leadingChord: const [
                'Cmaj7#11',
                'F#m7b5',
                'Bbsus4/D',
                'G#dim7',
                'Eb6/9',
              ][i % 5],
              text: '',
            ),
          ),
        ),
      ],
    ),
    SongSection(
      kind: SongSectionKind.verse,
      label: 'Verse',
      number: 2,
      lines: [
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'Bbsus4/D', text: 'x'),
            LyricSegment(leadingChord: 'Eb6/9', text: 'y'),
            LyricSegment(leadingChord: 'F#m7b5', text: 'z'),
          ],
        ),
        LyricLine(
          segments: const [
            LyricSegment(
              leadingChord: 'G#dim7',
              text: 'A shorter closing line',
            ),
          ],
        ),
      ],
    ),
    SongSection(
      kind: SongSectionKind.bridge,
      label: 'Bridge',
      number: null,
      lines: [
        // Second chord-only bar (EIGHTY wide chords again) to make the
        // wide-chord-only path dominate more of the fixture's total height.
        LyricLine(
          segments: List.generate(
            80,
            (i) => LyricSegment(
              leadingChord: const [
                'Bbsus4/D',
                'G#dim7',
                'Eb6/9',
                'Cmaj7#11',
                'F#m7b5',
              ][i % 5],
              text: '',
            ),
          ),
        ),
        LyricLine(
          segments: const [
            LyricSegment(leadingChord: 'Cmaj7#11', text: 'Final bridge line'),
          ],
        ),
      ],
    ),
  ];

  return SongReaderProjection(
    song: ParsedSong(
      title: 'Chord-Heavy Consistency Fixture',
      sourceKey: 'G',
      sections: sections,
      diagnostics: const [],
    ),
    state: SongReaderState(sharedFontScale: fontScale),
  );
}

// A single short line, deliberately narrower than the available column.
//
// Used ONLY by 'render grid width equals the fit calculator's width' below.
// _buildFixtureProjection's lines are long enough to wrap, and a line that
// wraps forces song_line_view.dart's over-wide-group ConstrainedBox fallback
// to occupy the FULL available width regardless of whether the surrounding
// Column is shrink-wrapped or tight -- which is exactly what let the shrink-
// wrap bug this test exists to catch go unnoticed for as long as it did (see
// the re-enable comment on that test). A fixture that never wraps is the only
// one this specific check can trust: under a shrink-wrap, the render grid
// narrows to this one short line's width; under the fixed-width layout, it
// still equals the full padding-adjusted column width.
SongReaderProjection _buildNarrowContentFixtureProjection() {
  final sections = <SongSection>[
    SongSection(
      kind: SongSectionKind.verse,
      label: 'Verse',
      number: 1,
      lines: [
        LyricLine(
          segments: const [LyricSegment(leadingChord: 'G', text: 'Hi')],
        ),
      ],
    ),
  ];

  return SongReaderProjection(
    song: ParsedSong(
      title: 'Narrow Content Fixture',
      sourceKey: 'G',
      sections: sections,
      diagnostics: const [],
    ),
    state: SongReaderState(sharedFontScale: 1.0),
  );
}

// Mirrors song_reader_shell.dart's `_contentPadding`. It must track the real
// shell: this suite checks that the width the render grid gets equals the width
// the fit calculator models, and both are derived from this padding -- pinning
// a value the app no longer uses would make the check self-consistent but
// meaningless.
const _contentPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 14);
const _maxContentWidth = 960.0;

Widget _buildSurface({
  required SongReaderProjection projection,
  ValueChanged<double>? onSetFontScale,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SongReaderCompactSurface(
        projection: projection,
        areControlsVisible: false,
        currentTitle: projection.title,
        onSurfaceTap: () {},
        contentColumnCount: 1,
        onTransposeDown: () {},
        onTransposeUp: () {},
        onDecreaseFontScale: () {},
        onIncreaseFontScale: () {},
        showBottomContextBar: false,
        maxContentWidth: _maxContentWidth,
        contentPadding: _contentPadding,
        onSetFontScale: onSetFontScale ?? (_) {},
      ),
    ),
  );
}

void main() {
  // Phone-breakpoint coverage note: every fixture in this file already pumps
  // at this 375-logical-px viewport, which is BELOW
  // readerRegularTypeScaleMinWidth (600) -- so every fixture here already
  // resolves ReaderTheme's COMPACT (phone) token set, not the regular one.
  // This is the opposite gap from the other two consistency suites (which
  // both pump at flutter_test's default 800x600 and so only ever exercised
  // the regular set until this task's additions there): this file needed no
  // new phone-width fixture, since the whole file already is one.
  const viewportWidth = 375.0;
  const viewportHeight = 812.0;

  group('SongReaderCompactSurface estimate/render consistency', () {
    testWidgets(
      'fit calculator and render grid receive identical padding-adjusted '
      'dimensions',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final projection = _buildFixtureProjection();

        await tester.pumpWidget(_buildSurface(projection: projection));
        await tester.pump();

        // Real-tree read: the raw box the surface's inner LayoutBuilder sees,
        // BEFORE content padding is subtracted. The Scrollbar/SingleChildScrollView
        // is the direct child of that LayoutBuilder and fills it exactly, so its
        // rendered size equals `constraints.biggest`.
        final rawConstraintsSize = tester.getSize(
          find.byType(SingleChildScrollView),
        );

        final expectedCalculatorWidth =
            (rawConstraintsSize.width < _maxContentWidth
                ? rawConstraintsSize.width
                : _maxContentWidth) -
            _contentPadding.horizontal;
        final expectedCalculatorHeight =
            rawConstraintsSize.height - _contentPadding.vertical;

        // Real-tree read: the height value the surface actually handed to the
        // render grid (the `availableHeight` constructor argument), taken
        // straight off the live widget instance -- not recomputed.
        final gridWidget = tester.widget<SongReaderSectionGrid>(
          find.byType(SongReaderSectionGrid),
        );
        expect(
          gridWidget.availableHeight,
          moreOrLessEquals(expectedCalculatorHeight, epsilon: 0.5),
          reason:
              'the height handed to the render grid must equal '
              'constraints.maxHeight - contentPadding.vertical, the same '
              'quantity the fit calculator uses',
        );

        // Tie the derived dimensions back to the actual fit calculator: feed
        // them into resolveFitFontScale and confirm the result matches what a
        // real double-tap applies. This fixture's estimated content height at
        // scale 1.0 must straddle the viewport so the binary search lands in
        // its interior rather than degenerating to minScale/maxScale (a
        // degenerate collapse would make this assertion vacuous).
        //
        // The widget's own double-tap handler measures the real lyric/chord
        // character advances via measureSongReaderCharWidths (rather than
        // the flat characterWidthEstimate default) before calling
        // resolveFitFontScale, so this expectation must feed the same
        // measured widths in or the two calls compute different scales for
        // reasons that have nothing to do with a real bug.
        final charWidths = measureSongReaderCharWidths(
          tester.element(find.byType(SongReaderCompactSurface)),
        );
        final expectedFit = resolveFitFontScale(
          sections: projection.sections,
          viewMode: projection.viewMode,
          availableWidth: expectedCalculatorWidth,
          availableHeight: expectedCalculatorHeight,
          minScale: SongReaderState.minSharedFontScale,
          maxScale: SongReaderState.maxSharedFontScale,
          lyricCharWidth: charWidths.lyricCharWidth,
          chordCharWidth: charWidths.chordCharWidth,
          // Must match every argument the widget's own double-tap handler
          // passes (song_reader_compact_surface.dart's _handleDoubleTap),
          // otherwise this "expected" value is computed from a different
          // resolved metrics/textScale than the real call under test.
          textScale: charWidths.textScale,
          metrics: charWidths.metrics,
        );
        expect(
          expectedFit,
          allOf(
            greaterThan(SongReaderState.minSharedFontScale),
            lessThan(SongReaderState.maxSharedFontScale),
          ),
          reason:
              'the fixture must be sized so the fit calculation lands in '
              'its interior, otherwise the dimension-agreement check below '
              'is vacuous',
        );

        final scaleCalls = <double>[];
        await tester.pumpWidget(
          _buildSurface(projection: projection, onSetFontScale: scaleCalls.add),
        );
        await tester.pump();
        final center = tester.getCenter(find.byType(SongReaderCompactSurface));
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(scaleCalls, isNotEmpty);
        expect(
          scaleCalls.last,
          moreOrLessEquals(expectedFit, epsilon: 1e-6),
          reason:
              'the applied fit scale must match resolveFitFontScale computed '
              'from the same padding-adjusted dimensions the widget uses '
              'internally',
        );
      },
    );

    testWidgets(
      'render grid width equals the fit calculator\'s width',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final projection = _buildNarrowContentFixtureProjection();

        await tester.pumpWidget(_buildSurface(projection: projection));
        await tester.pump();

        final rawConstraintsSize = tester.getSize(
          find.byType(SingleChildScrollView),
        );
        final expectedCalculatorWidth =
            (rawConstraintsSize.width < _maxContentWidth
                ? rawConstraintsSize.width
                : _maxContentWidth) -
            _contentPadding.horizontal;

        // Real-tree read: the actual rendered width of the render grid's own
        // LayoutBuilder.
        final gridRenderSize = tester.getSize(
          find.byType(SongReaderSectionGrid),
        );

        expect(
          gridRenderSize.width,
          moreOrLessEquals(expectedCalculatorWidth, epsilon: 0.5),
          reason:
              'the width the render grid\'s own LayoutBuilder sees must '
              'equal min(constraints.maxWidth, maxContentWidth) - '
              'contentPadding.horizontal, the same quantity the fit '
              'calculator uses',
        );
      },
      // Re-enabled 2026-08-12, by the type-scale PR that removed the cause.
      //
      // This was skipped by the word-boundary-wrapping PR (#70) against a
      // KNOWN GAP it did not introduce and was not scoped to fix:
      // song_reader_section_grid.dart's Column (crossAxisAlignment: start),
      // embedded under song_reader_compact_surface.dart's
      // Center + ConstrainedBox, received LOOSE constraints from that Center
      // and so shrink-wrapped to its own longest rendered line instead of
      // filling the available width. That made "render grid width == fit
      // calculator width" unholdable through no fault of the estimator.
      //
      // #70 only exposed it. Before that PR, a line wider than the available
      // width always hit song_line_view.dart's over-wide-group ConstrainedBox
      // fallback, which forced that one line -- and so the whole Column -- to
      // the full available width, incidentally masking the shrink-wrap.
      // Word-boundary splitting made a group at most one word, so that
      // fallback stopped firing for ordinary prose and the mask went with it.
      //
      // The compact surface now gives the content a TIGHT width
      // (`SizedBox(width: min(constraints.maxWidth, maxContentWidth))` inside
      // a top-left `Align`), which is exactly the precondition this test was
      // waiting on, so it is live again. It is now the assertion that pins the
      // fixed left edge's geometric consequence: if anyone reintroduces a
      // shrink-wrap here, the fit calculator starts modelling a width the grid
      // never gets.
    );

    testWidgets('estimated content height tracks the rendered content height', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final projection = _buildFixtureProjection();

      await tester.pumpWidget(_buildSurface(projection: projection));
      await tester.pump();

      final rendered = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .height;
      final gridWidth = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .width;

      // Feed the SAME measured lyric/chord char widths the real grid build
      // uses (song_reader_section_grid.dart calls measureSongReaderCharWidths
      // once per build) -- estimateSongContentHeight defaults to the flat
      // characterWidthEstimate constant, which is exactly the wrong-in-both-
      // directions guess this fixture exists to catch drift from.
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(SongReaderSectionGrid)),
      );
      final estimated = estimateSongContentHeight(
        sections: projection.sections,
        viewMode: projection.viewMode,
        availableWidth: gridWidth,
        fontScale: projection.sharedFontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
        metrics: charWidths.metrics,
      );

      // ---------------------------------------------------------------
      // One-sided contract (2026-07-28): resolveFitFontScale picks the
      // largest scale whose ESTIMATED height fits the viewport, so an
      // estimate below the real render lets the grid overflow -- the one
      // thing fit-to-screen exists to prevent. A symmetric relative/
      // absolute tolerance cannot express that direction matters; the
      // estimate must never fall below the rendered height, only "not
      // uselessly loose" above it.
      //
      // Re-measured 2026-07-28 after modelling greedy word-boundary wrap in
      // _segmentIntraLines (song_reader_fit.dart) and charging
      // lineWidgetBottomPadding once per lyric line (see that file):
      // against this fixture (4 sections / 11 lines: long wrapping chorded
      // lines, a 4-chord instrumental bar with no lyric text under any
      // chord, and a blank ChordproParser-shaped separator line --
      // LyricLine(segments: [LyricSegment(text: '')])) at 375x812,
      // contentPadding=24 all sides, fontScale=1.0:
      //   rendered=1082.0  estimated=1198.0  ratio=1.107 (10.7% over)
      // Ceiling pinned at 1.2x, just above the measured ratio.
      //
      // Re-measured 2026-08-12, wired to the resolved (600px type-scale)
      // metrics and textScale on both sides (previously this call omitted
      // both, silently comparing a resolved-metrics render against a
      // SongReaderMetrics.legacy/identity-textScale estimate): rendered=
      // 1066.0 estimated=1080.0 (ratio 1.013). The gap tightened -- the
      // type scale, not a model regression -- because the estimate side now
      // scales its row-height guesses by the same resolved metrics the
      // render actually used, instead of the legacy constants. Ceiling
      // pinned at 1.05x, just above the new measured ratio.
      // ---------------------------------------------------------------
      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'estimateSongContentHeight must never fall below the rendered '
            'content height (an under-estimate lets resolveFitFontScale '
            'pick a scale that overflows); rendered=$rendered '
            'estimated=$estimated',
      );

      expect(
        estimated,
        lessThan(rendered * 1.05),
        reason:
            'estimateSongContentHeight must not be uselessly loose; '
            'rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 1.05}',
      );
    });

    testWidgets('estimated content height tracks the rendered content height '
        '(chord-heavy fixture)', (tester) async {
      tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final projection = _buildChordHeavyFixtureProjection();

      await tester.pumpWidget(_buildSurface(projection: projection));
      await tester.pump();

      final rendered = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .height;
      final gridWidth = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .width;

      // See the plain fixture above: feed the SAME measured char widths the
      // real grid build uses instead of the flat characterWidthEstimate
      // default.
      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(SongReaderSectionGrid)),
      );
      final estimated = estimateSongContentHeight(
        sections: projection.sections,
        viewMode: projection.viewMode,
        availableWidth: gridWidth,
        fontScale: projection.sharedFontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
        metrics: charWidths.metrics,
      );

      // ---------------------------------------------------------------
      // One-sided contract (2026-07-28): see the plain fixture above for
      // why direction matters here (resolveFitFontScale must never pick a
      // scale whose estimate undershoots the real render).
      //
      // Re-measured 2026-07-28 after modelling greedy word-boundary wrap in
      // _segmentIntraLines and charging lineWidgetBottomPadding once per
      // lyric line (both in song_reader_fit.dart): against the chord-heavy
      // fixture (4 sections / 10 lines: wide extended/slash chords --
      // Cmaj7#11, F#m7b5, Bbsus4/D, G#dim7, Eb6/9 (5-9 chars each) -- a
      // line of three single-character syllables each under a wide chord,
      // TWO chord-only instrumental bars of EIGHTY wide chords each (no
      // lyric text under any of them), and the same blank
      // ChordproParser-shaped separator line as the plain fixture) at
      // 375x812, contentPadding=24 all sides, fontScale=1.0:
      //   rendered=2574.0  estimated=2630.0  ratio=1.022 (2.2% over)
      // This fixture is chord-only-heavy (no lyric text under most
      // segments), so it barely exercises the word-wrap model -- the small
      // increase over the render is mostly lineWidgetBottomPadding across
      // its many lines. Ceiling pinned at 1.1x, comfortably above the
      // measured ratio but still tight enough to catch a real regression.
      //
      // Re-measured 2026-08-12, wired to the resolved (600px type-scale)
      // metrics and textScale on both sides (previously this call omitted
      // both, same gap as the plain fixture above): rendered=1732.0
      // estimated=1746.0 (ratio 1.008). The type scale, not a model
      // regression, moved both numbers substantially (this fixture's many
      // chord-only rows are dominated by chordRowHeight, which the 600px
      // breakpoint resizes) while keeping the estimate/render gap just as
      // tight as before. Ceiling pinned at 1.03x, just above the new
      // measured ratio.
      // ---------------------------------------------------------------
      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'estimateSongContentHeight must never fall below the rendered '
            'content height on a chord-heavy fixture too; rendered=$rendered '
            'estimated=$estimated',
      );
      expect(
        estimated,
        lessThan(rendered * 1.03),
        reason:
            'estimateSongContentHeight must not be uselessly loose on a '
            'chord-heavy fixture too; rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 1.03}',
      );
    });

    testWidgets('estimated content height tracks the rendered content height '
        'at the tablet-portrait target (834x1194)', (tester) async {
      // Every other fixture in this file pumps at 375x812 (phone, the
      // COMPACT token set) -- see the "Phone-breakpoint coverage note" above.
      // 834x1194, tablet portrait, is the PRIMARY target size this type-scale
      // change was measured against (docs/specs/2026-08-09-song-presentation.md,
      // "Result at 834x1194: the whole reference song occupies 870px of the
      // 1130px available"): it is the size the product owner's mockups were
      // built at, and it resolves the REGULAR token set, which nothing else
      // in this file exercises. A whole-song estimate/render check at this
      // size is the single most load-bearing thing this PR must not break.
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final projection = _buildFixtureProjection();

      await tester.pumpWidget(_buildSurface(projection: projection));
      await tester.pump();

      final rendered = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .height;
      final gridWidth = tester
          .getSize(find.byType(SongReaderSectionGrid))
          .width;

      final charWidths = measureSongReaderCharWidths(
        tester.element(find.byType(SongReaderSectionGrid)),
      );
      final estimated = estimateSongContentHeight(
        sections: projection.sections,
        viewMode: projection.viewMode,
        availableWidth: gridWidth,
        fontScale: projection.sharedFontScale,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        textScale: charWidths.textScale,
        metrics: charWidths.metrics,
      );

      // ---------------------------------------------------------------
      // One-sided contract: see the plain fixture above for why direction
      // matters (resolveFitFontScale must never pick a scale whose estimate
      // undershoots the real render).
      //
      // Measured 2026-08-13, same fixture as the plain 375x812 case above,
      // at 834x1194 with contentPadding=12 horizontal/14 vertical (the
      // fixed-left-edge layout) and the REGULAR (>=600px) token set:
      //   rendered=778.0  estimated=792.0  ratio=1.018 (1.8% over)
      // Ceiling pinned at 1.03x, just above the measured ratio.
      // ---------------------------------------------------------------
      expect(
        estimated,
        greaterThanOrEqualTo(rendered),
        reason:
            'estimateSongContentHeight must never fall below the rendered '
            'content height at the tablet-portrait target; rendered=$rendered '
            'estimated=$estimated',
      );

      expect(
        estimated,
        lessThan(rendered * 1.03),
        reason:
            'estimateSongContentHeight must not be uselessly loose at the '
            'tablet-portrait target; rendered=$rendered estimated=$estimated '
            'ceiling=${rendered * 1.03}',
      );
    });
  });
}
