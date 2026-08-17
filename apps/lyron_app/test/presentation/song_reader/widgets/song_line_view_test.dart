import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

void main() {
  testWidgets(
    'does not insert layout gaps into lyric text at chord boundaries',
    (tester) async {
      final line = SongReaderLyricLineProjection(
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

      // "lo world" is two words -- splitSegmentsAtWordBoundaries now cuts
      // it at the internal space, so the word-internal chord split (the
      // thing this test guards) shows up as 'Hel' butting against 'lo ',
      // not the whole clause.
      final firstTextRight = tester.getTopRight(find.text('Hel')).dx;
      final secondTextLeft = tester.getTopLeft(find.text('lo ')).dx;

      expect(secondTextLeft - firstTextRight, lessThanOrEqualTo(1));
    },
  );

  testWidgets('applies shared font scale to lyric text size', (tester) async {
    final line = SongReaderLyricLineProjection(
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
    final line = SongReaderLyricLineProjection(
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
    final line = SongReaderLyricLineProjection(
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

  testWidgets(
    'long unbreakable segment does not overflow when parent gives unbounded width',
    (tester) async {
      // A single token with no spaces — naturally ~3000px wide at scale 3.0.
      // When SongLineView receives unbounded width (e.g. inside InteractiveViewer
      // during zoom), Wrap passes unbounded constraints to its children and the
      // segment Text would expand to its natural width.  The fix — LayoutBuilder +
      // ConstrainedBox with the MediaQuery screen width — must cap it to screen
      // width (800px in test) and wrap the text rather than letting it overflow.
      const longToken =
          'supercalifragilisticexpialidocioussupercalifragilisticexpialidocious';
      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'G', text: longToken),
        ],
      );

      // OverflowBox gives SongLineView truly unbounded width — same effect as
      // InteractiveViewer / horizontal SingleChildScrollView.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 2000,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: double.infinity,
                child: SongLineView(
                  line: line,
                  viewMode: SongReaderViewMode.chordsAndLyrics,
                  sharedFontScale: 3.0,
                ),
              ),
            ),
          ),
        ),
      );

      // No RenderFlex/overflow exception.
      expect(tester.takeException(), isNull);
      // With unbounded parent width, the widget must still respect the screen
      // width (MediaQuery reports 800px in Flutter test env) — not expand to
      // the natural single-line text width (~3000px).
      final renderedWidth = tester.getSize(find.byType(SongLineView)).width;
      expect(renderedWidth, lessThanOrEqualTo(800.5));
    },
  );

  testWidgets('collapses chord-only lines in lyrics only mode', (tester) async {
    final line = SongReaderLyricLineProjection(
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

  testWidgets('does not split a chord-broken word across rows at 375px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Leading words fill the row almost exactly to the 375px wrap boundary
    // right after "porcika", so "m," is forced onto the next row unless the
    // renderer keeps the chord-split word ("porcika" + "m," -- no whitespace
    // between the two segments) together as one unbreakable unit.
    final line = SongReaderLyricLineProjection(
      segments: const [
        SongReaderSegmentProjection(displayChord: 'C', text: 'Minden '),
        SongReaderSegmentProjection(displayChord: null, text: 'apro '),
        SongReaderSegmentProjection(displayChord: 'C', text: 'porcikamban '),
        SongReaderSegmentProjection(displayChord: null, text: 'el '),
        SongReaderSegmentProjection(displayChord: 'G', text: 'porcika'),
        SongReaderSegmentProjection(displayChord: 'D', text: 'm,'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 375,
            child: SongLineView(
              line: line,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1.0,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('m,')).dy,
      tester.getTopLeft(find.text('porcika')).dy,
      reason: 'the word must not be split across rows',
    );
  });

  testWidgets('never breaks inside a word split by a chord change', (
    tester,
  ) async {
    // Narrow enough that the line must wrap. The reproduction from the spec:
    // ChordPro cuts "Igédben" in half at the chord.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final line = SongReaderLyricLineProjection(
      segments: const [
        SongReaderSegmentProjection(
          displayChord: 'E',
          text: 'Kegyelmed elég, több, mint elég, Igé',
        ),
        SongReaderSegmentProjection(displayChord: 'G#m', text: 'dben bízok én'),
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

    // Every rendered lyric box holds at most one word: no box may contain
    // whitespace with text on both sides of it.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();

    for (final text in texts) {
      expect(
        text.trimRight().contains(RegExp(r'\s')),
        isFalse,
        reason: 'a rendered box holds more than one word: "$text"',
      );
    }

    // And the line still says what it said before.
    expect(
      texts
          .where((t) => t != 'E' && t != 'G#m')
          .join()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
      'Kegyelmed elég, több, mint elég, Igédben bízok én',
    );
  });

  testWidgets('renders a chord inside a tinted, rounded chip', (tester) async {
    // No ReaderThemeSet registered -- ReaderTheme.of falls back to
    // ReaderTheme.stageLight, whose chordChipColor is non-null (spec section
    // 2: a chip in both themes).
    final line = SongReaderLyricLineProjection(
      segments: const [
        SongReaderSegmentProjection(displayChord: 'Am', text: 'Hello'),
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

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Am'), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.borderRadius, BorderRadius.circular(3));
    expect(decoration.color, isNotNull);
    expect(container.padding, const EdgeInsets.symmetric(horizontal: 3));
  });

  testWidgets(
    'renders a bare chord label when the token set has no chip colour',
    (tester) async {
      // Build a token set with chordChipColor cleared to null via direct
      // construction -- ReaderTheme.copyWith uses `??` and cannot clear a
      // value back to null, so copyWith cannot express "no chip" starting
      // from a base theme that has one. Direct construction is the smaller
      // change: it needs no new API on ReaderTheme, just copying the base
      // theme's other fields (see report for the alternative considered:
      // adding a `bool clearChordChipColor` flag to copyWith).
      final base = ReaderTheme.stageLight(
        colorScheme: ThemeData.light().colorScheme,
        textTheme: ThemeData.light().textTheme,
        compact: false,
      );
      final noChipTokens = ReaderTheme(
        lyricStyle: base.lyricStyle,
        chordStyle: base.chordStyle,
        chordChipColor: null,
        sectionLabelStyle: base.sectionLabelStyle,
        unknownSectionLabelColor: base.unknownSectionLabelColor,
        commentStyle: base.commentStyle,
        directiveStyle: base.directiveStyle,
        leadingDirectiveStyle: base.leadingDirectiveStyle,
        tabStyle: base.tabStyle,
        tabBackgroundColor: base.tabBackgroundColor,
        metrics: base.metrics,
      );

      final line = SongReaderLyricLineProjection(
        segments: const [
          SongReaderSegmentProjection(displayChord: 'Am', text: 'Hello'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [
              ReaderThemeSet(compact: noChipTokens, regular: noChipTokens),
            ],
          ),
          home: Scaffold(
            body: SongLineView(
              line: line,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1,
            ),
          ),
        ),
      );

      expect(find.text('Am'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Am'), matching: find.byType(Container)),
        findsNothing,
      );
    },
  );
}
