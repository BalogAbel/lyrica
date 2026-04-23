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

  testWidgets('applies shared font scale to lyric text size', (tester) async {
    final line = SongReaderLineProjection(
      segments: const [
        SongReaderSegmentProjection(displayChord: null, text: 'Hello'),
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

    final baselineSize = tester
        .widget<Text>(find.text('Hello'))
        .style!
        .fontSize!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongLineView(
            line: line,
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1.4,
          ),
        ),
      ),
    );

    final scaledSize = tester.widget<Text>(find.text('Hello')).style!.fontSize!;
    expect(scaledSize, greaterThan(baselineSize));
  });

  testWidgets('renders chord-only segments without empty lyric placeholders', (
    tester,
  ) async {
    final line = SongReaderLineProjection(
      segments: const [
        SongReaderSegmentProjection(displayChord: 'E', text: ''),
        SongReaderSegmentProjection(displayChord: 'C#m/G#', text: ''),
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

    expect(find.text('E'), findsOneWidget);
    expect(find.text('C#m/G#'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('C#m/G#')).dx -
          tester.getTopRight(find.text('E')).dx,
      greaterThan(8),
    );
  });

  testWidgets('preserves whitespace lyric segments used for chord alignment', (
    tester,
  ) async {
    final line = SongReaderLineProjection(
      segments: const [
        SongReaderSegmentProjection(displayChord: 'A', text: '   '),
        SongReaderSegmentProjection(displayChord: 'E', text: 'Hello'),
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

    final whitespaceText = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == '   ',
    );

    expect(whitespaceText, findsOneWidget);
    expect(tester.getSize(whitespaceText).width, greaterThan(0));
  });

  testWidgets('collapses chord-only lines in lyrics only mode', (tester) async {
    final line = SongReaderLineProjection(
      segments: const [
        SongReaderSegmentProjection(displayChord: 'E', text: ''),
        SongReaderSegmentProjection(displayChord: 'C#m/G#', text: ''),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongLineView(
            line: line,
            viewMode: SongReaderViewMode.lyricsOnly,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    expect(find.text('E'), findsNothing);
    expect(find.text('C#m/G#'), findsNothing);
    expect(find.byType(SongLineView), findsOneWidget);
    expect(tester.getSize(find.byType(SongLineView)).height, 0);
  });
}
