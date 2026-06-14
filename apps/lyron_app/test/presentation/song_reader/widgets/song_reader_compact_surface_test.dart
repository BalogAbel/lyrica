import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_bar.dart';

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

  testWidgets('shows the control bar only when controls are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: buildSurface(areControlsVisible: false)),
      ),
    );
    expect(find.byType(SongReaderControlBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildSurface(areControlsVisible: true))),
    );
    expect(find.byType(SongReaderControlBar), findsOneWidget);
  });
}
