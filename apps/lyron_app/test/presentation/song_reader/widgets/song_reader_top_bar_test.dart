import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_chrome_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_rail.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Widget _host(
  SongReaderTopBar bar, {
  ThemeData? theme,
  Size size = const Size(800, 600),
}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        // SizedBox constrains the LayoutBuilder inside SongReaderTopBar to
        // the intended width -- MediaQueryData alone doesn't resize the
        // actual test surface, only what `MediaQuery.of` reports.
        body: SizedBox(
          width: size.width,
          child: Align(alignment: Alignment.topCenter, child: bar),
        ),
      ),
    ),
  );
}

SongReaderTopBar _bar({
  String title = 'Song',
  bool hasRecoverableWarnings = false,
  VoidCallback? onShowWarnings,
  bool showOverflowMenu = true,
  void Function(SongReaderOverflowAction)? onOverflowAction,
}) {
  return SongReaderTopBar(
    title: title,
    onBack: () {},
    hasRecoverableWarnings: hasRecoverableWarnings,
    onShowWarnings: onShowWarnings,
    showOverflowMenu: showOverflowMenu,
    viewMode: SongReaderViewMode.chordsAndLyrics,
    canEditSongs: false,
    isDarkActive: false,
    onOverflowAction: onOverflowAction ?? (_) {},
  );
}

void main() {
  testWidgets('back sits at the leading edge using the standard back symbol', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_bar()));

    final row = tester.widget<Row>(find.byType(Row).first);
    final leading = row.children.first;
    expect(leading, isA<IconButton>());
    expect((leading as IconButton).icon, isA<BackButtonIcon>());
    expect(find.byTooltip(AppStrings.songReaderBackAction), findsOneWidget);
    // Never a text label -- HIG *Toolbars* requires the standard symbol.
    expect(find.text(AppStrings.songReaderBackAction), findsNothing);
  });

  testWidgets('back invokes onBack', (tester) async {
    var backTaps = 0;
    await tester.pumpWidget(
      _host(
        SongReaderTopBar(
          title: 'Song',
          onBack: () => backTaps += 1,
          showOverflowMenu: false,
          viewMode: SongReaderViewMode.chordsAndLyrics,
          canEditSongs: false,
          isDarkActive: false,
        ),
      ),
    );

    await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
    expect(backTaps, 1);
  });

  testWidgets('renders the song title', (tester) async {
    await tester.pumpWidget(_host(_bar(title: 'Amazing Grace')));

    expect(find.text('Amazing Grace'), findsOneWidget);
  });

  testWidgets(
    'shows the warnings indicator only when hasRecoverableWarnings is true',
    (tester) async {
      await tester.pumpWidget(_host(_bar(hasRecoverableWarnings: false)));
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);

      var warningTaps = 0;
      await tester.pumpWidget(
        _host(
          _bar(
            hasRecoverableWarnings: true,
            onShowWarnings: () => warningTaps += 1,
          ),
        ),
      );
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.warning_amber_outlined));
      expect(warningTaps, 1);
    },
  );

  testWidgets('shows the overflow menu only when showOverflowMenu is true', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_bar(showOverflowMenu: false)));
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    await tester.pumpWidget(_host(_bar(showOverflowMenu: true)));
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });

  testWidgets('overflow menu selection invokes onOverflowAction', (
    tester,
  ) async {
    SongReaderOverflowAction? selected;
    await tester.pumpWidget(
      _host(
        _bar(showOverflowMenu: true, onOverflowAction: (a) => selected = a),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songReaderLyricsOnlyAction).last);
    await tester.pumpAndSettle();

    expect(selected, SongReaderOverflowAction.toggleViewMode);
  });

  group('sizing', () {
    testWidgets('resolves to SongReaderChromeMetrics.topBarHeight (tablet)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_bar(), size: const Size(800, 600)));

      final metrics = SongReaderChromeMetrics.resolve(800);
      expect(
        tester.getSize(find.byType(SongReaderTopBar)).height,
        metrics.topBarHeight,
      );
    });

    testWidgets('resolves to SongReaderChromeMetrics.topBarHeight (phone)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_bar(), size: const Size(375, 812)));

      final metrics = SongReaderChromeMetrics.resolve(375);
      expect(
        tester.getSize(find.byType(SongReaderTopBar)).height,
        metrics.topBarHeight,
      );
    });
  });

  group('floating chrome background', () {
    testWidgets('light theme takes its background from ReaderTheme, not '
        'the ambient ColorScheme', (tester) async {
      final theme = buildLightTheme();
      await tester.pumpWidget(_host(_bar(), theme: theme));

      final material = tester.widget<Material>(
        find.byKey(const Key('song-reader-top-bar-surface')),
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
      await tester.pumpWidget(_host(_bar(), theme: theme));

      final material = tester.widget<Material>(
        find.byKey(const Key('song-reader-top-bar-surface')),
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
      await tester.pumpWidget(_host(_bar(), theme: buildDarkTheme()));

      expect(tester.takeException(), isNull);
      expect(find.text('Song'), findsOneWidget);
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
            topBar: _bar(),
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
      'one tap reveals both the top bar and the rail; a second dismisses both',
      (tester) async {
        await tester.pumpWidget(host(areControlsVisible: false));
        expect(find.byType(SongReaderTopBar), findsNothing);
        expect(find.byType(SongReaderControlRail), findsNothing);

        await tester.pumpWidget(host(areControlsVisible: true));
        expect(find.byType(SongReaderTopBar), findsOneWidget);
        expect(find.byType(SongReaderControlRail), findsOneWidget);

        await tester.pumpWidget(host(areControlsVisible: false));
        expect(find.byType(SongReaderTopBar), findsNothing);
        expect(find.byType(SongReaderControlRail), findsNothing);
      },
    );
  });
}
