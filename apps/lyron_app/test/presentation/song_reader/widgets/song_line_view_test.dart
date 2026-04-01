import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

void main() {
  testWidgets(
    'does not insert layout gaps into lyric text at chord boundaries',
    (tester) async {
      final line = SongReaderLineProjection(
        segments: [
          const SongReaderSegmentProjection(displayChord: 'A', text: 'Hel'),
          const SongReaderSegmentProjection(
            displayChord: 'Bm',
            text: 'lo world',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongLineView(
              line: line,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1,
            ),
          ),
        ),
      );

      final firstTextRight = tester.getTopRight(find.text('Hel')).dx;
      final secondTextLeft = tester.getTopLeft(find.text('lo world')).dx;

      expect(secondTextLeft - firstTextRight, lessThanOrEqualTo(1));
    },
  );
}
