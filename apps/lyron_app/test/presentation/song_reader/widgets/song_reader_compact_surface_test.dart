import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_rail.dart';

SongReaderProjection _buildLabeledProjection({required String lineText}) {
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
              segments: [LyricSegment(leadingChord: 'G', text: lineText)],
            ),
          ],
        ),
      ],
      diagnostics: const [],
    ),
    state: SongReaderState(),
  );
}

Widget _buildLabeledSurface({
  required SongReaderProjection projection,
  required EdgeInsetsGeometry contentPadding,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SongReaderCompactSurface(
        projection: projection,
        areControlsVisible: false,
        currentTitle: 'Song',
        onSurfaceTap: () {},
        hasRecoverableWarnings: false,
        warningCount: 0,
        contentColumnCount: 1,
        onTransposeDown: () {},
        onTransposeUp: () {},
        onDecreaseFontScale: () {},
        onIncreaseFontScale: () {},
        showBottomContextBar: false,
        maxContentWidth: 960,
        contentPadding: contentPadding,
      ),
    ),
  );
}

void main() {
  SongReaderCompactSurface buildSurface({required bool areControlsVisible}) {
    return SongReaderCompactSurface(
      projection: SongReaderProjection(
        song: ParsedSong(
          title: 'Song',
          sourceKey: 'G',
          sections: const [],
          diagnostics: const [],
        ),
        state: SongReaderState(),
      ),
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
      showBottomContextBar: false,
      maxContentWidth: 960,
      contentPadding: const EdgeInsets.all(24),
    );
  }

  testWidgets('opens controls from keyboard and exposes semantics tap', (
    tester,
  ) async {
    var surfaceTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderCompactSurface(
            projection: SongReaderProjection(
              song: ParsedSong(
                title: 'Song',
                sourceKey: 'G',
                sections: const [],
                diagnostics: const [],
              ),
              state: SongReaderState(),
            ),
            areControlsVisible: false,
            currentTitle: 'Song',
            onSurfaceTap: () => surfaceTaps += 1,
            hasRecoverableWarnings: false,
            warningCount: 0,
            contentColumnCount: 1,
            onTransposeDown: () {},
            onTransposeUp: () {},
            onDecreaseFontScale: () {},
            onIncreaseFontScale: () {},
            showBottomContextBar: false,
            maxContentWidth: 960,
            contentPadding: const EdgeInsets.all(24),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(surfaceTaps, 1);
  });

  testWidgets('shows the control rail only when controls are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: buildSurface(areControlsVisible: false)),
      ),
    );
    expect(find.byType(SongReaderControlRail), findsNothing);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildSurface(areControlsVisible: true))),
    );
    expect(find.byType(SongReaderControlRail), findsOneWidget);
  });

  testWidgets('content starts at a fixed left edge, not centred on its '
      'longest line', (tester) async {
    // Two songs with very different longest-line lengths must put their first
    // section label at the SAME x. Before this change the shrink-wrap made
    // that x depend on the content.
    const contentPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 14);

    await tester.pumpWidget(
      _buildLabeledSurface(
        projection: _buildLabeledProjection(lineText: 'Short'),
        contentPadding: contentPadding,
      ),
    );
    final narrowSongLabelX = tester.getTopLeft(find.text('VERSE 1')).dx;

    await tester.pumpWidget(
      _buildLabeledSurface(
        projection: _buildLabeledProjection(
          lineText: 'A very very very very very very long lyric line',
        ),
        contentPadding: contentPadding,
      ),
    );
    final wideSongLabelX = tester.getTopLeft(find.text('VERSE 1')).dx;

    expect(narrowSongLabelX, wideSongLabelX);
  });

  testWidgets('content padding is 12 horizontal', (tester) async {
    const contentPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 14);

    await tester.pumpWidget(
      _buildLabeledSurface(
        projection: _buildLabeledProjection(lineText: 'Short'),
        contentPadding: contentPadding,
      ),
    );
    final labelX = tester.getTopLeft(find.text('VERSE 1')).dx;

    expect(labelX, 12.0);
  });

  group('control rail landscape side inset', () {
    // The rail already added the right-edge safe-area inset to its
    // `Positioned` offset (song_reader_compact_surface.dart), but until now
    // had no test pinning that a landscape notch on the right actually
    // pushes it clear -- unlike the top bar and bottom bar, which each have
    // their own coverage in song_reader_chrome_safe_area_test.dart.
    const landscapeNotchRight = 60.0;

    Widget buildWithViewPadding({required EdgeInsets viewPadding}) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(1200, 700),
            viewPadding: viewPadding,
          ),
          child: Scaffold(body: buildSurface(areControlsVisible: true)),
        ),
      );
    }

    testWidgets('the rail shifts left by exactly the right inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWithViewPadding(viewPadding: EdgeInsets.zero),
      );
      final withoutInset = tester
          .getRect(find.byType(SongReaderControlRail))
          .right;

      await tester.pumpWidget(
        buildWithViewPadding(
          viewPadding: const EdgeInsets.only(right: landscapeNotchRight),
        ),
      );
      final withInset = tester
          .getRect(find.byType(SongReaderControlRail))
          .right;

      expect(withoutInset - withInset, landscapeNotchRight);
    });
  });
}
