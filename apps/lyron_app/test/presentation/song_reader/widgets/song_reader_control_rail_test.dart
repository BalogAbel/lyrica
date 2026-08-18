import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_rail.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';

ParsedSong _song({int baseCapo = 2}) {
  return ParsedSong(
    title: 'Song',
    sourceKey: 'G',
    baseTranspose: 2,
    baseCapo: baseCapo,
    sections: const [],
    diagnostics: const [],
  );
}

Widget _host(SongReaderControlRail rail, {ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: rail)),
);

void main() {
  testWidgets('renders transpose, capo and font controls in guitar mode, '
      'stacked vertically', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlRail(
          projection: SongReaderProjection(
            song: _song(),
            state: SongReaderState(),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onCapoDown: () {},
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('song-reader-transpose-down')), findsOneWidget);
    expect(
      find.byKey(const Key('song-reader-transpose-value')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-down')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-value')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-up')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-font-decrease')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-font-increase')), findsOneWidget);

    // Vertical groups: transpose down sits directly above the value chip,
    // which sits above transpose up -- the layout carried over from the
    // horizontal bar, rotated onto the y axis.
    final downY = tester
        .getCenter(find.byKey(const Key('song-reader-transpose-down')))
        .dy;
    final valueY = tester
        .getCenter(find.byKey(const Key('song-reader-transpose-value')))
        .dy;
    final upY = tester
        .getCenter(find.byKey(const Key('song-reader-transpose-up')))
        .dy;
    expect(downY, lessThan(valueY));
    expect(valueY, lessThan(upY));
  });

  testWidgets('hides the capo group in piano mode', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlRail(
          projection: SongReaderProjection(
            song: _song(),
            state: SongReaderState(
              instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
            ),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('song-reader-capo-down')), findsNothing);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
  });

  testWidgets('disables capo-down when onCapoDown is null', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlRail(
          projection: SongReaderProjection(
            song: _song(baseCapo: 0),
            state: SongReaderState(),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onCapoDown: null,
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('song-reader-capo-down')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('invokes callbacks on tap', (tester) async {
    var transposeUp = 0;
    var fontUp = 0;
    await tester.pumpWidget(
      _host(
        SongReaderControlRail(
          projection: SongReaderProjection(
            song: _song(),
            state: SongReaderState(),
          ),
          onTransposeDown: () {},
          onTransposeUp: () => transposeUp += 1,
          onCapoDown: () {},
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () => fontUp += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('song-reader-transpose-up')));
    await tester.tap(find.byKey(const Key('song-reader-font-increase')));
    expect(transposeUp, 1);
    expect(fontUp, 1);
  });

  group('floating chrome background', () {
    SongReaderControlRail rail() {
      return SongReaderControlRail(
        projection: SongReaderProjection(
          song: _song(),
          state: SongReaderState(),
        ),
        onTransposeDown: () {},
        onTransposeUp: () {},
        onCapoDown: () {},
        onCapoUp: () {},
        onDecreaseFontScale: () {},
        onIncreaseFontScale: () {},
      );
    }

    testWidgets('light theme takes its background from ReaderTheme, not '
        'the ambient ColorScheme', (tester) async {
      final theme = buildLightTheme();
      await tester.pumpWidget(_host(rail(), theme: theme));

      final material = tester.widget<Material>(
        find.byKey(const Key('song-reader-control-rail-surface')),
      );
      final expected = ReaderTheme.stageLight(
        colorScheme: theme.colorScheme,
        textTheme: theme.textTheme,
        compact: false,
      ).floatingChromeBackground;

      expect(material.color, expected);
      expect(material.color, isNot(theme.colorScheme.surface));
    });

    testWidgets('dark theme takes its background from ReaderTheme, not the '
        'ambient ColorScheme', (tester) async {
      final theme = buildDarkTheme();
      await tester.pumpWidget(_host(rail(), theme: theme));

      final material = tester.widget<Material>(
        find.byKey(const Key('song-reader-control-rail-surface')),
      );
      final expected = ReaderTheme.stageDark(
        textTheme: theme.textTheme,
        compact: false,
      ).floatingChromeBackground;

      expect(material.color, expected);
      expect(material.color, isNot(theme.colorScheme.surface));
    });

    testWidgets('renders without error against a dark background', (
      tester,
    ) async {
      await tester.pumpWidget(_host(rail(), theme: buildDarkTheme()));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('song-reader-transpose-value')),
        findsOneWidget,
      );
    });
  });

  group('reveal toggle (hosted in SongReaderCompactSurface)', () {
    SongReaderProjection projection() {
      return SongReaderProjection(
        song: ParsedSong(
          title: 'Song',
          sourceKey: 'G',
          sections: const [],
          diagnostics: const [],
        ),
        state: SongReaderState(),
      );
    }

    Widget host({required bool areControlsVisible}) {
      return MaterialApp(
        home: Scaffold(
          body: SongReaderCompactSurface(
            projection: projection(),
            areControlsVisible: areControlsVisible,
            currentTitle: 'Song',
            topBar: SongReaderTopBar(
              title: 'Song',
              onBack: () {},
              showOverflowMenu: false,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              canEditSongs: false,
              isDarkActive: false,
            ),
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
          ),
        ),
      );
    }

    testWidgets(
      'one tap reveals both the rail and the top bar; a second dismisses both',
      (tester) async {
        await tester.pumpWidget(host(areControlsVisible: false));
        expect(find.byType(SongReaderControlRail), findsNothing);
        expect(find.byType(SongReaderTopBar), findsNothing);

        await tester.pumpWidget(host(areControlsVisible: true));
        expect(find.byType(SongReaderControlRail), findsOneWidget);
        expect(find.byType(SongReaderTopBar), findsOneWidget);

        await tester.pumpWidget(host(areControlsVisible: false));
        expect(find.byType(SongReaderControlRail), findsNothing);
        expect(find.byType(SongReaderTopBar), findsNothing);
      },
    );
  });
}
