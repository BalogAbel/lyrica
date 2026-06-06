import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart';

SongReaderProjection _buildProjection() {
  return SongReaderProjection(
    song: ParsedSong(
      title: 'Scrollbar Test Song',
      sourceKey: 'G',
      sections: [
        SongSection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          lines: [
            LyricLine(
              segments: [
                const LyricSegment(leadingChord: 'G', text: 'Hello world'),
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

void main() {
  testWidgets(
    'compact surface SingleChildScrollView fills full viewport width (not capped to content width)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongReaderCompactSurface(
              projection: _buildProjection(),
              areControlsVisible: false,
              currentTitle: 'Scrollbar Test Song',
              onSurfaceTap: () {},
              onSurfaceDoubleTap: () {},
              hasRecoverableWarnings: false,
              warningCount: 0,
              contentColumnCount: 1,
              onToggleViewMode: () {},
              onTransposeDown: () {},
              onTransposeUp: () {},
              onDecreaseFontScale: () {},
              onIncreaseFontScale: () {},
              showBottomContextBar: false,
              maxContentWidth: 960,
              contentPadding: EdgeInsets.all(24),
            ),
          ),
        ),
      );
      await tester.pump();

      // Scrollbar must exist inside the compact surface.
      expect(find.byType(Scrollbar), findsWidgets);

      // The SingleChildScrollView must be as wide as the viewport
      // (1400 px logical — not shrunk to 960 content width).
      final scrollViewSize = tester.getSize(find.byType(SingleChildScrollView));
      expect(scrollViewSize.width, greaterThanOrEqualTo(1400 - 0.5));
    },
  );

  testWidgets(
    'expanded surface SingleChildScrollView fills its allocated width (not capped outside)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongReaderExpandedSurface(
              projection: _buildProjection(),
              showContextPanel: false,
              hasRecoverableWarnings: false,
              warningCount: 0,
              contentColumnCount: 1,
              onToggleViewMode: () {},
              onTransposeDown: () {},
              onTransposeUp: () {},
              onDecreaseFontScale: () {},
              onIncreaseFontScale: () {},
              maxContentWidth: 1440,
              contentPadding: EdgeInsets.all(24),
            ),
          ),
        ),
      );
      await tester.pump();

      // Scrollbar must exist inside the expanded surface.
      expect(find.byType(Scrollbar), findsWidgets);
    },
  );
}
