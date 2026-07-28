import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
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

const _contentPadding = EdgeInsets.all(24);
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
        hasRecoverableWarnings: false,
        warningCount: 0,
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

        // Real-tree read: the actual rendered width of the render grid's own
        // LayoutBuilder (Column/Row fill the full loose max width offered by
        // Center+ConstrainedBox+Padding, so this is a genuine layout
        // measurement, not a second run of the same formula).
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

        // Tie the derived dimensions back to the actual fit calculator: feed
        // them into resolveFitFontScale and confirm the result matches what a
        // real double-tap applies. This fixture's estimated content height at
        // scale 1.0 must straddle the viewport so the binary search lands in
        // its interior rather than degenerating to minScale/maxScale (a
        // degenerate collapse would make this assertion vacuous).
        final expectedFit = resolveFitFontScale(
          sections: projection.sections,
          viewMode: projection.viewMode,
          availableWidth: expectedCalculatorWidth,
          availableHeight: expectedCalculatorHeight,
          minScale: SongReaderState.minSharedFontScale,
          maxScale: SongReaderState.maxSharedFontScale,
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

      final estimated = estimateSongContentHeight(
        sections: projection.sections,
        viewMode: projection.viewMode,
        availableWidth: gridWidth,
        fontScale: projection.sharedFontScale,
      );

      final absoluteError = (estimated - rendered).abs();
      final relativeError = absoluteError / rendered;

      // ---------------------------------------------------------------
      // Re-measured 2026-07-28 after fixing TWO related bugs in
      // _lineItemHeight's over-wide-group branch (song_reader_fit.dart):
      //
      // 1. Between segments: a word group too wide for one run now packs
      //    its own segments into inner runs the way song_line_view.dart's
      //    inner Wrap does (spacing: 0 between segments of the same
      //    group), instead of dividing the group's total width by the
      //    effective line width and guessing a run count. See the
      //    "over-wide group packs its own segments into runs" test in
      //    song_reader_fit_test.dart for the reviewer's original repro.
      //
      // 2. Inside one segment: a lone over-wide segment (no chord-induced
      //    mid-word split -- the shape of an ordinary long lyric line) now
      //    also charges extra LYRIC-only height for the visual lines its
      //    own `Text` soft-wraps into (_segmentIntraLines), on top of
      //    exactly one chord row, matching _SongLineSegmentView's
      //    Column(chord, lyric) shape in song_line_view.dart. See the "a
      //    single over-wide segment models its own lyric text wrap" group
      //    in song_reader_fit_test.dart.
      //
      // Fixing (1) alone regressed this fixture (rendered=1082.0
      // estimated=890.0, 17.7%/192px) because this fixture's first line
      // ("A long lyric line that will wrap across multiple rows", one
      // segment, ~530px wide against a 327px column) lost the old
      // ceil(groupWidth / effectiveLineWidth)'s accidental approximation
      // of its own Text-internal wrap once that guess was replaced by
      // correct per-segment run packing. Fixing (2) restores that
      // modeling on a principled basis (lyric-only width, not the
      // chord-inclusive packing width) without reintroducing the extra
      // (wrong) chord row the old guess also produced.
      //
      // Against this fixture (4 sections / 11 lines: long wrapping chorded
      // lines, a 4-chord instrumental bar with no lyric text under any
      // chord, and a blank ChordproParser-shaped separator line --
      // LyricLine(segments: [LyricSegment(text: '')])) at 375x812,
      // contentPadding=24 all sides, fontScale=1.0:
      //   rendered=1082.0  estimated=1010.0  relativeError=0.0665 (6.7%)
      //   absoluteError=72.0
      // Back in the same ballpark as the original pre-chord-row-bug-fix
      // measurement (2.0%/22px) -- not pixel-identical, because the new
      // model's ceil(lyricWidth / effectiveLineWidth) line count is a
      // different (more principled, chord-label-excluded) approximation
      // than the old group-width-based guess, not the same formula by
      // coincidence.
      //
      // Tightened from the interim 0.22/250px (pinned right after fixing
      // only bug (1), before intra-segment modeling existed) back down to
      // 0.15/160px -- headroom similar to the file's original convention
      // (~2.2-2.3x the measured error) now that both effects are modeled.
      // ---------------------------------------------------------------
      expect(
        relativeError,
        lessThan(0.15),
        reason:
            'estimateSongContentHeight must track the rendered content '
            'height within a tight relative bound; measured $relativeError '
            '(rendered=$rendered, estimated=$estimated)',
      );

      expect(
        absoluteError,
        lessThan(160.0),
        reason:
            'absolute drift between estimate and render must stay bounded; '
            'measured $absoluteError px',
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

      final estimated = estimateSongContentHeight(
        sections: projection.sections,
        viewMode: projection.viewMode,
        availableWidth: gridWidth,
        fontScale: projection.sharedFontScale,
      );

      final absoluteError = (estimated - rendered).abs();
      final relativeError = absoluteError / rendered;

      // ---------------------------------------------------------------
      // Re-measured 2026-07-28 after fixing TWO related bugs in
      // _lineItemHeight's over-wide-group branch (song_reader_fit.dart):
      // (1) between-segment run packing now mirrors song_line_view.dart's
      // inner Wrap (spacing: 0) instead of guessing a run count from the
      // group's total width, giving every run its correct chord-row
      // count; and (2) a lone over-wide segment (no chord-induced
      // mid-word split) now also charges extra LYRIC-only height for the
      // visual lines its own text soft-wraps into (_segmentIntraLines),
      // using the lyric-only width so a chord label never inflates that
      // line count. See song_reader_fit_test.dart's "over-wide group
      // packs its own segments into runs" and "a single over-wide segment
      // models its own lyric text wrap" groups.
      //
      // Against the chord-heavy fixture (4 sections / 10 lines: wide
      // extended/slash chords -- Cmaj7#11, F#m7b5, Bbsus4/D, G#dim7,
      // Eb6/9 (5-9 chars each) -- a line of three single-character
      // syllables each under a wide chord, TWO chord-only instrumental
      // bars of EIGHTY wide chords each (no lyric text under any of
      // them), and the same blank ChordproParser-shaped separator line as
      // the plain fixture) at 375x812, contentPadding=24 all sides,
      // fontScale=1.0:
      //   rendered=2574.0  estimated=3378.0  relativeError=0.3124 (31.2%)
      //   absoluteError=804.0
      //
      // Essentially back to the original pre-chord-row-bug-fix measurement
      // (31.6%/814px), slightly better (804 < 814): fix (1) alone dropped
      // this to 30.3%/780px by removing the old ceil()-guess's second row
      // for this fixture's one single-segment over-wide line ("Chorus line
      // with a wide chord up front" under Cmaj7#11); fix (2) restores that
      // row on a principled basis. None of this fixture's other
      // multi-segment merged groups (e.g. the "Cmaj7#11/a"+"F#m7b5/b"+
      // "Bbsus4/D/c" run, merged because there is no whitespace between
      // the segments) are actually over-wide at this column width (~220px
      // combined vs ~327px column), so the reviewer's multi-segment
      // chord-row bug doesn't itself manifest in this fixture; the two
      // 80-chord instrumental bars are unaffected too, since each
      // chord-only segment is well under the column width on its own and
      // never enters the over-wide branch. The remaining ~31% error is the
      // separate, already-known characterWidthEstimate/bold-chord-glyph
      // calibration gap described in
      // docs/deferred/2026-07-27-reader-fit-character-width-calibration.md,
      // not a wrap/run-count defect -- this fixture exists to bound that
      // drift, not to hide it.
      //
      // Bounds restored to essentially the original 0.38/950px (tightened
      // very slightly to 0.37/930px, matching the file's original ~1.2x
      // headroom ratio over the measured error) now that both effects are
      // modeled and the number is back where it started.
      // ---------------------------------------------------------------
      expect(
        relativeError,
        lessThan(0.37),
        reason:
            'estimateSongContentHeight must track the rendered content '
            'height within a bounded relative error on a chord-heavy '
            'fixture too; measured $relativeError '
            '(rendered=$rendered, estimated=$estimated)',
      );
      expect(
        absoluteError,
        lessThan(930.0),
        reason:
            'absolute drift between estimate and render must stay bounded '
            'on a chord-heavy fixture too; measured $absoluteError px',
      );
    });
  });
}
