import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_rail.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

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

  group('key source captions', () {
    ResolvedSongKey keyFrom(
      SongKeyLayerId transposeSource, [
      SongKeyLayerId capoSource = SongKeyLayerId.song,
    ]) => ResolvedSongKey(
      transpose: ResolvedSongKeyField(value: 2, source: transposeSource),
      capo: ResolvedSongKeyField(value: 2, source: capoSource),
    );

    SongReaderControlRail rail(
      ResolvedSongKey key, {
      SongReaderInstrumentDisplayMode mode =
          SongReaderInstrumentDisplayMode.guitar,
    }) => SongReaderControlRail(
      projection: SongReaderProjection(
        song: _song(),
        state: SongReaderState(instrumentDisplayMode: mode),
        key: key,
      ),
      onTransposeDown: () {},
      onTransposeUp: () {},
      onCapoDown: () {},
      onCapoUp: () {},
      onDecreaseFontScale: () {},
      onIncreaseFontScale: () {},
    );

    Text caption(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key)));

    testWidgets('each value chip has its source caption below it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(rail(keyFrom(SongKeyLayerId.temporary, SongKeyLayerId.plan))),
      );

      expect(
        caption(tester, 'song-reader-transpose-source').data,
        AppStrings.songReaderKeySourceTemporary,
      );
      expect(
        caption(tester, 'song-reader-capo-source').data,
        AppStrings.songReaderKeySourcePlan,
      );
      for (final field in ['transpose', 'capo']) {
        expect(
          tester.getCenter(find.byKey(Key('song-reader-$field-source'))).dy,
          greaterThan(
            tester.getCenter(find.byKey(Key('song-reader-$field-value'))).dy,
          ),
          reason: '$field caption sits below its chip',
        );
      }
    });

    testWidgets('the caption sits between its chip and the next button', (
      tester,
    ) async {
      await tester.pumpWidget(_host(rail(keyFrom(SongKeyLayerId.song))));

      expect(
        tester
            .getCenter(find.byKey(const Key('song-reader-transpose-source')))
            .dy,
        lessThan(
          tester
              .getCenter(find.byKey(const Key('song-reader-transpose-up')))
              .dy,
        ),
      );
    });

    testWidgets('the rail keeps its size whichever source a caption shows', (
      tester,
    ) async {
      final surface = find.byKey(const Key('song-reader-control-rail-surface'));
      await tester.pumpWidget(_host(rail(keyFrom(SongKeyLayerId.song))));
      final songSize = tester.getSize(surface);

      for (final source in [SongKeyLayerId.temporary, SongKeyLayerId.plan]) {
        await tester.pumpWidget(_host(rail(keyFrom(source, source))));
        expect(tester.getSize(surface), songSize, reason: source.name);
      }
    });

    testWidgets('the chip colors follow the source from the color scheme', (
      tester,
    ) async {
      final theme = buildLightTheme();
      await tester.pumpWidget(
        _host(rail(keyFrom(SongKeyLayerId.temporary)), theme: theme),
      );

      final chipKey = find.byKey(const Key('song-reader-transpose-value'));
      final chip = tester.widget<DecoratedBox>(
        find.descendant(of: chipKey, matching: find.byType(DecoratedBox)),
      );
      expect(
        (chip.decoration as BoxDecoration).color,
        theme.colorScheme.tertiaryContainer,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: chipKey, matching: find.byType(Text)),
            )
            .style
            ?.color,
        theme.colorScheme.onTertiaryContainer,
      );
    });

    testWidgets('the capo caption goes with the capo group in piano mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          rail(
            keyFrom(SongKeyLayerId.song),
            mode: SongReaderInstrumentDisplayMode.piano,
          ),
        ),
      );

      expect(
        find.byKey(const Key('song-reader-transpose-source')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('song-reader-capo-source')), findsNothing);
    });
  });

  group('key actions', () {
    const resetKey = Key('song-reader-key-reset');
    const saveKey = Key('song-reader-key-save-to-plan');

    SongReaderControlRail rail(
      SongReaderKeyActions keyActions, {
      SongReaderInstrumentDisplayMode mode =
          SongReaderInstrumentDisplayMode.guitar,
    }) => SongReaderControlRail(
      projection: SongReaderProjection(
        song: _song(),
        state: SongReaderState(instrumentDisplayMode: mode),
      ),
      onTransposeDown: () {},
      onTransposeUp: () {},
      onCapoDown: () {},
      onCapoUp: () {},
      onDecreaseFontScale: () {},
      onIncreaseFontScale: () {},
      keyActions: keyActions,
    );

    VoidCallback? onPressed(WidgetTester tester, Key key) =>
        tester.widget<IconButton>(find.byKey(key)).onPressed;

    testWidgets('without actions Reset is there and disabled, Save to plan '
        'is not there', (tester) async {
      await tester.pumpWidget(_host(rail(SongReaderKeyActions.none)));

      expect(find.byKey(resetKey), findsOneWidget);
      expect(onPressed(tester, resetKey), isNull);
      expect(find.byKey(saveKey), findsNothing);
      expect(find.byTooltip(AppStrings.songReaderResetKeyAction), findsOne);
    });

    testWidgets('when Save to plan is available both buttons are there, Reset '
        'above Save, between the capo group and the font group', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(rail(const SongReaderKeyActions(isSaveToPlanAvailable: true))),
      );

      expect(find.byKey(resetKey), findsOneWidget);
      expect(find.byKey(saveKey), findsOneWidget);
      expect(onPressed(tester, resetKey), isNull);
      expect(onPressed(tester, saveKey), isNull);
      expect(find.byTooltip(AppStrings.songReaderSaveToPlanAction), findsOne);
      double centerY(Key key) => tester.getCenter(find.byKey(key)).dy;
      expect(
        centerY(const Key('song-reader-capo-up')),
        lessThan(centerY(resetKey)),
      );
      expect(centerY(resetKey), lessThan(centerY(saveKey)));
      expect(
        centerY(saveKey),
        lessThan(centerY(const Key('song-reader-font-decrease'))),
      );
    });

    testWidgets('the group stays in place in piano mode', (tester) async {
      await tester.pumpWidget(
        _host(
          rail(
            const SongReaderKeyActions(isSaveToPlanAvailable: true),
            mode: SongReaderInstrumentDisplayMode.piano,
          ),
        ),
      );

      double centerY(Key key) => tester.getCenter(find.byKey(key)).dy;
      expect(
        centerY(const Key('song-reader-transpose-up')),
        lessThan(centerY(resetKey)),
      );
      expect(
        centerY(saveKey),
        lessThan(centerY(const Key('song-reader-font-decrease'))),
      );
    });

    testWidgets('enabling the callbacks does not change the rail size', (
      tester,
    ) async {
      final surface = find.byKey(const Key('song-reader-control-rail-surface'));
      await tester.pumpWidget(
        _host(rail(const SongReaderKeyActions(isSaveToPlanAvailable: true))),
      );
      final disabledSize = tester.getSize(surface);
      final resetCenter = tester.getCenter(find.byKey(resetKey));

      await tester.pumpWidget(
        _host(
          rail(
            SongReaderKeyActions(
              isSaveToPlanAvailable: true,
              onReset: () {},
              onSaveToPlan: () {},
            ),
          ),
        ),
      );

      expect(onPressed(tester, resetKey), isNotNull);
      expect(onPressed(tester, saveKey), isNotNull);
      expect(tester.getSize(surface), disabledSize);
      expect(tester.getCenter(find.byKey(resetKey)), resetCenter);
    });

    testWidgets('the callbacks run on tap', (tester) async {
      var resets = 0;
      var saves = 0;
      await tester.pumpWidget(
        _host(
          rail(
            SongReaderKeyActions(
              isSaveToPlanAvailable: true,
              onReset: () => resets += 1,
              onSaveToPlan: () => saves += 1,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(resetKey));
      await tester.tap(find.byKey(saveKey));

      expect(resets, 1);
      expect(saves, 1);
    });

    testWidgets('in a landscape phone viewport Reset and Save are reachable '
        'in the rail scroll view', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var resets = 0;
      var saves = 0;
      await tester.pumpWidget(
        _host(
          rail(
            SongReaderKeyActions(
              isSaveToPlanAvailable: true,
              onReset: () => resets += 1,
              onSaveToPlan: () => saves += 1,
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.byKey(resetKey));
      await tester.pump();
      await tester.tap(find.byKey(resetKey));
      await tester.ensureVisible(find.byKey(saveKey));
      await tester.pump();
      await tester.tap(find.byKey(saveKey));

      expect(resets, 1);
      expect(saves, 1);
    });
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

    testWidgets('a rail taller than the free height starts below the top '
        'bar, so it never covers the bar\'s controls', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(areControlsVisible: true));

      expect(
        tester.getRect(find.byType(SongReaderControlRail)).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(SongReaderTopBar)).bottom,
        ),
      );
    });
  });
}
