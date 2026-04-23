import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';

void main() {
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
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(surfaceTaps, 1);
  });
}
