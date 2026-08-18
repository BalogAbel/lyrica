// Guard test for the reader chrome restructure
// (docs/plans/2026-08-18-reader-chrome-restructure.md, Task 1).
//
// Why exact equality, not a tolerance: `resolveFitFontScale` picks the
// largest scale whose ESTIMATED height fits a given `availableHeight`. If
// revealing the chrome changes that input even slightly, a font scale that
// was chosen while the chrome was hidden can start rendering an
// already-too-tall layout once the chrome reveals (or vice-versa) — the
// exact overflow-on-reveal failure this restructure exists to prevent. A
// tolerance would hide a regression that is one pixel short of "shrinks the
// content area"; the invariant is that the fit input never moves, full stop.
//
// This test pumps the compact surface at a fixed viewport, once with the
// chrome hidden and once with it revealed, and reads the `availableHeight`/
// `availableWidth` actually handed to `SongReaderSectionGrid` — the value
// that feeds the fit calculation — plus the section grid's rendered `Rect`.
// Both must be byte-for-byte identical between the two states.
//
// On today's code (compact_surface.dart:297-391) this MUST FAIL: the control
// bar and bottom context bar share the `Column` with the content `Expanded`,
// so revealing them shrinks `constraints.maxHeight` and therefore
// `availableHeight`. That failure is the point — it documents the behaviour
// PR4 (the Stack/Positioned overlay restructure) changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

SongReaderProjection _buildProjection() {
  return SongReaderProjection(
    song: ParsedSong(
      title: 'Song',
      sourceKey: 'G',
      sections: [
        SongSection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          lines: [
            LyricLine(
              segments: [
                LyricSegment(leadingChord: 'G', text: 'A simple lyric line'),
              ],
            ),
          ],
        ),
      ],
      diagnostics: const [],
    ),
    state: SongReaderState(),
  );
}

Widget _buildSurface({required bool areControlsVisible}) {
  return MaterialApp(
    home: Scaffold(
      body: SongReaderCompactSurface(
        projection: _buildProjection(),
        areControlsVisible: areControlsVisible,
        currentTitle: 'Song',
        onSurfaceTap: () {},
        hasRecoverableWarnings: false,
        warningCount: 0,
        contentColumnCount: 1,
        onTransposeDown: () {},
        onTransposeUp: () {},
        onDecreaseFontScale: () {},
        onIncreaseFontScale: () {},
        showBottomContextBar: true,
        previousTitle: 'Previous Song',
        nextTitle: 'Next Song',
        onPreviousTap: () {},
        onNextTap: () {},
        maxContentWidth: 960,
        contentPadding: const EdgeInsets.all(24),
      ),
    ),
  );
}

void main() {
  // Tablet-ish viewport (logical px, DPR=1) so the width isn't the tight
  // constraint and any height delta from the reveal is visible.
  const viewportWidth = 834.0;
  const viewportHeight = 1194.0;

  testWidgets('revealing the reader chrome does not move the fit input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildSurface(areControlsVisible: false));
    await tester.pumpAndSettle();

    final hiddenGrid = tester.widget<SongReaderSectionGrid>(
      find.byType(SongReaderSectionGrid),
    );
    final hiddenHeight = hiddenGrid.availableHeight;
    final hiddenRect = tester.getRect(find.byType(SongReaderSectionGrid));

    await tester.pumpWidget(_buildSurface(areControlsVisible: true));
    await tester.pumpAndSettle();

    final revealedGrid = tester.widget<SongReaderSectionGrid>(
      find.byType(SongReaderSectionGrid),
    );
    final revealedHeight = revealedGrid.availableHeight;
    final revealedRect = tester.getRect(find.byType(SongReaderSectionGrid));

    expect(
      revealedHeight,
      hiddenHeight,
      reason:
          'availableHeight fed to SongReaderSectionGrid (the fit input) '
          'must not change when the chrome is revealed',
    );
    expect(
      revealedRect,
      hiddenRect,
      reason:
          'the rendered content Rect must not move when the chrome is '
          'revealed — the overlays must float over content, not resize it',
    );
  });
}
