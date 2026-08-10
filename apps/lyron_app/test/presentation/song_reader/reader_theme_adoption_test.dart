// apps/lyron_app/test/presentation/song_reader/reader_theme_adoption_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/comment_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/directive_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/tab_block_view.dart';

/// A deliberately unmistakable token set: if a widget still derives its style
/// from the ambient TextTheme/ColorScheme instead of reading the extension,
/// these values will not appear.
ReaderTheme _markedTokens(ThemeData base) {
  return ReaderTheme.fromM3(
    colorScheme: base.colorScheme,
    textTheme: base.textTheme,
  ).copyWith(
    lyricStyle: const TextStyle(fontSize: 31, color: Color(0xFFAA0001)),
    chordStyle: const TextStyle(fontSize: 29, color: Color(0xFFAA0002)),
    sectionLabelStyle: const TextStyle(fontSize: 27, color: Color(0xFFAA0003)),
    unknownSectionLabelColor: const Color(0xFFAA0004),
    leadingDirectiveStyle: const TextStyle(fontSize: 25, color: Color(0xFFAA0005)),
    commentStyle: const TextStyle(fontSize: 23, color: Color(0xFFAA0006)),
    directiveStyle: const TextStyle(fontSize: 21, color: Color(0xFFAA0007)),
    tabStyle: const TextStyle(fontSize: 19, color: Color(0xFFAA0008)),
    tabBackgroundColor: const Color(0xFFAA0009),
  );
}

ThemeData _themeWith(ReaderTheme Function(ThemeData) tokens) {
  final base = buildLightTheme();
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[tokens(base)],
  );
}

void main() {
  testWidgets('SongLineView styles chords and lyrics from ReaderTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: SongLineView(
            line: SongReaderLyricLineProjection(
              segments: const [
                SongReaderSegmentProjection(
                  text: 'lyric',
                  displayChord: 'Am',
                ),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    final lyric = tester.widget<Text>(find.text('lyric'));
    final chord = tester.widget<Text>(find.text('Am'));

    expect(lyric.style!.fontSize, 31);
    expect(lyric.style!.color, const Color(0xFFAA0001));
    expect(chord.style!.fontSize, 29);
    expect(chord.style!.color, const Color(0xFFAA0002));
  });

  testWidgets('SongLineView still multiplies the base size by the font scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: SongLineView(
            line: SongReaderLyricLineProjection(
              segments: const [
                SongReaderSegmentProjection(
                  text: 'lyric',
                  displayChord: 'Am',
                ),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 2,
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('lyric')).style!.fontSize, 62);
    expect(tester.widget<Text>(find.text('Am')).style!.fontSize, 58);
  });

  testWidgets('the section header uses the ReaderTheme label style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: SongReaderSectionGrid(
            leadingDirectiveText: 'Capo 2',
            sections: [
              SongReaderSectionProjection(
                kind: SongSectionKind.verse,
                label: 'Verse',
                number: 1,
                isUnknown: false,
                lines: const [],
              ),
            ],
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
            columnCount: 1,
            availableHeight: 600,
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('Verse 1')).style!.fontSize, 27);
    expect(
      tester.widget<Text>(find.text('Verse 1')).style!.color,
      const Color(0xFFAA0003),
    );
    expect(
      tester.widget<Text>(find.text('Capo 2')).style!.color,
      const Color(0xFFAA0005),
    );
  });

  testWidgets('an unrecognised section kind uses the unknown label colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: SongReaderSectionGrid(
            sections: [
              SongReaderSectionProjection(
                kind: SongSectionKind.unknown,
                label: 'Interlude',
                number: null,
                isUnknown: true,
                lines: const [],
              ),
            ],
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
            columnCount: 1,
            availableHeight: 600,
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('Interlude')).style!.color,
      const Color(0xFFAA0004),
    );
  });

  testWidgets('comment, directive and tab views read ReaderTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _themeWith(_markedTokens),
        home: Scaffold(
          body: Column(
            children: [
              CommentLineView(
                projection: const SongReaderCommentProjection(text: 'note'),
                sharedFontScale: 1,
              ),
              const DirectiveLineView(
                projection: SongReaderDirectiveProjection(
                  name: 'tempo',
                  value: '72',
                ),
              ),
              TabBlockView(
                projection: SongReaderTabProjection(rawLines: ['e|--0--']),
                sharedFontScale: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('note')).style!.color,
      const Color(0xFFAA0006),
    );
    expect(
      tester.widget<Text>(find.text('{tempo: 72}')).style!.color,
      const Color(0xFFAA0007),
    );
    expect(
      tester.widget<Text>(find.text('e|--0--')).style!.color,
      const Color(0xFFAA0008),
    );

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('e|--0--'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0xFFAA0009),
    );
  });

  testWidgets(
    'measureSongReaderCharWidths measures the styles ReaderTheme declares, '
    'not the ambient TextTheme',
    (tester) async {
      late SongReaderCharWidths widths;

      await tester.pumpWidget(
        MaterialApp(
          theme: _themeWith(_markedTokens),
          home: Builder(
            builder: (context) {
              widths = measureSongReaderCharWidths(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // The marked tokens set lyric 31 / chord 29 / header 27; the M3 defaults
      // would report 16 / 14 / 22.
      expect(widths.textScale.lyricBaseFontSize, 31);
      expect(widths.textScale.chordBaseFontSize, 29);
      expect(widths.textScale.headerBaseFontSize, 27);
      expect(widths.textScale.inlineDirectiveBaseFontSize, 21);
    },
  );
}
