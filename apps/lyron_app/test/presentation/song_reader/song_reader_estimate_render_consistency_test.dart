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
      // Measured 2026-07-27 against this fixture (4 sections / 11 lines:
      // long wrapping chorded lines, a 4-chord instrumental bar with no
      // lyric text under any chord, and a blank ChordproParser-shaped
      // separator line -- LyricLine(segments: [LyricSegment(text: '')]))
      // at 375x812, contentPadding=24 all sides, fontScale=1.0:
      //   rendered=1082.0  estimated=1060.0  relativeError=0.0203
      // Pinned to 0.05 (relative) -- roughly 2.5x the measured error,
      // enough headroom for font-metric jitter across machines/CI while
      // still catching a real regression in the estimator.
      // ---------------------------------------------------------------
      expect(
        relativeError,
        lessThan(0.05),
        reason:
            'estimateSongContentHeight must track the rendered content '
            'height within a tight relative bound; measured $relativeError '
            '(rendered=$rendered, estimated=$estimated)',
      );

      // Absolute ceiling: two lyric rows total, not per line. A per-line
      // allowance would be 264px here, far above the 54px the relative bound
      // already implies, so it would never bind and would prove nothing. The
      // measured absolute drift is 22px, so two rows (48px) is the tightest
      // round figure that still leaves room for font-metric jitter.
      expect(
        absoluteError,
        lessThan(lyricRowHeight * 2),
        reason:
            'absolute drift between estimate and render must stay under two '
            'lyric rows; measured $absoluteError px',
      );
    });
  });
}
