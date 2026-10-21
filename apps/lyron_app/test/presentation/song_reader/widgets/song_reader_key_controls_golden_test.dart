import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_rail.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';

import '../../../support/tolerant_golden_comparator.dart';

// Goldens for the reader's key controls in both layouts (S3 PR 3, U14): the
// compact control rail and the expanded tools panel, each with the source
// labels (Song / Plan / Temporary) and the Reset / Save to plan buttons in
// their enabled and disabled states.
//
// They pin chrome only, in the default test font: every glyph renders as a
// square box (Ahem), so the labels show their length and position, not their
// letters. `flutter test` does not load the Material icon font either, so an
// icon is a hollow box: which icon a button has is not pinned, its place, size
// and enabled or disabled color are. The words and the icons are asserted in
// the widget tests next to the widgets; these catch layout, color and
// enabled-versus-disabled regressions that an assertion on keys does not.
//
// Regenerate with `flutter test --update-goldens <this file>` and review the
// changed PNGs as images in the pull request.

/// Fixed surfaces at a device pixel ratio of 1, so the PNGs are the same size
/// on every machine. The control is pinned to the top of its surface, so a
/// change in its height moves only its bottom edge. The rail takes its own
/// width (the test font's boxes are wider than the real glyphs, so the surface
/// leaves it room); the panel is as wide as it is in the expanded shell (320).
const _railSurface = Size(144, 580);
const _panelSurface = Size(360, 460);
const _panelWidth = 320.0;
const _surfaceMargin = 20.0;

const _songTranspose = 2;
const _songCapo = 2;

void main() {
  late GoldenFileComparator previousComparator;

  setUpAll(() {
    previousComparator = goldenFileComparator;
    // Anti-aliasing differs a little between the macOS the goldens are made on
    // and the Linux CI runs on. Only this file gets the tolerance.
    goldenFileComparator = TolerantGoldenComparator(
      (previousComparator as LocalFileComparator).basedir.resolve(
        'song_reader_key_controls_golden_test.dart',
      ),
      maxDiffPercent: 0.005,
    );
  });

  tearDownAll(() => goldenFileComparator = previousComparator);

  group('compact control rail', () {
    testWidgets('library song: Song / Song, Reset disabled, no Save to plan', (
      tester,
    ) async {
      await _pumpRail(
        tester,
        key: _key(SongKeyLayerId.song, SongKeyLayerId.song),
        keyActions: SongReaderKeyActions.none,
      );

      await _expectGolden('compact_library_song.png');
    });

    testWidgets('plan editor: Plan / Plan, Reset and Save to plan disabled', (
      tester,
    ) async {
      await _pumpRail(
        tester,
        key: _key(
          SongKeyLayerId.plan,
          SongKeyLayerId.plan,
          transpose: 5,
          capo: 3,
        ),
        keyActions: const SongReaderKeyActions(isSaveToPlanAvailable: true),
      );

      await _expectGolden('compact_plan_editor.png');
    });

    testWidgets('temporary transpose over a plan capo, Reset and Save to plan '
        'enabled', (tester) async {
      await _pumpRail(
        tester,
        key: _key(
          SongKeyLayerId.temporary,
          SongKeyLayerId.plan,
          transpose: -3,
          capo: 3,
        ),
        keyActions: _enabledKeyActions(),
      );

      await _expectGolden('compact_temporary.png');
    });

    testWidgets('temporary transpose over a plan capo in the dark theme', (
      tester,
    ) async {
      await _pumpRail(
        tester,
        theme: buildDarkTheme(),
        key: _key(
          SongKeyLayerId.temporary,
          SongKeyLayerId.plan,
          transpose: -3,
          capo: 3,
        ),
        keyActions: _enabledKeyActions(),
      );

      await _expectGolden('compact_temporary_dark.png');
    });

    testWidgets('a song transpose outside the range: +14, step up disabled', (
      tester,
    ) async {
      await _pumpRail(
        tester,
        key: _key(SongKeyLayerId.song, SongKeyLayerId.song, transpose: 14),
        keyActions: SongReaderKeyActions.none,
        onTransposeUp: null,
      );

      await _expectGolden('compact_out_of_range.png');
    });
  });

  group('expanded tools panel', () {
    testWidgets('library song: Song / Song, Reset disabled, no Save to plan', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        key: _key(SongKeyLayerId.song, SongKeyLayerId.song),
        keyActions: SongReaderKeyActions.none,
      );

      await _expectGolden('expanded_library_song.png');
    });

    testWidgets('temporary transpose over a plan capo, Reset and Save to plan '
        'enabled', (tester) async {
      await _pumpPanel(
        tester,
        key: _key(
          SongKeyLayerId.temporary,
          SongKeyLayerId.plan,
          transpose: -3,
          capo: 3,
        ),
        keyActions: _enabledKeyActions(),
      );

      await _expectGolden('expanded_temporary.png');
    });

    testWidgets('temporary transpose over a plan capo in the dark theme', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        theme: buildDarkTheme(),
        key: _key(
          SongKeyLayerId.temporary,
          SongKeyLayerId.plan,
          transpose: -3,
          capo: 3,
        ),
        keyActions: _enabledKeyActions(),
      );

      await _expectGolden('expanded_temporary_dark.png');
    });
  });
}

/// The path is relative to this file; [TolerantGoldenComparator] resolves it
/// the way the default comparator does.
Future<void> _expectGolden(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/song_key_controls/$name'),
);

ParsedSong _song() => ParsedSong(
  title: 'Song',
  sourceKey: 'G',
  baseTranspose: _songTranspose,
  baseCapo: _songCapo,
  sections: const [],
  diagnostics: const [],
);

/// A resolved key built directly, so the golden pins the chrome and not the
/// resolver (which has its own tests). The values default to the song base.
ResolvedSongKey _key(
  SongKeyLayerId transposeSource,
  SongKeyLayerId capoSource, {
  int transpose = _songTranspose,
  int capo = _songCapo,
}) => ResolvedSongKey(
  transpose: ResolvedSongKeyField(value: transpose, source: transposeSource),
  capo: ResolvedSongKeyField(value: capo, source: capoSource),
);

SongReaderKeyActions _enabledKeyActions() => SongReaderKeyActions(
  isSaveToPlanAvailable: true,
  onReset: () {},
  onSaveToPlan: () {},
);

/// [key] decides what the controls show; the song only has to exist.
SongReaderProjection _projection(ResolvedSongKey key) =>
    SongReaderProjection(song: _song(), state: SongReaderState(), key: key);

/// Gives the test view a fixed size at a device pixel ratio of 1 and pumps
/// [child] alone in a `MaterialApp`.
Future<void> _pumpSurface(
  WidgetTester tester, {
  required Size surface,
  required ThemeData? theme,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? buildLightTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: _surfaceMargin),
            child: child,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpRail(
  WidgetTester tester, {
  required ResolvedSongKey key,
  required SongReaderKeyActions keyActions,
  ThemeData? theme,
  VoidCallback? onTransposeUp = _noop,
}) => _pumpSurface(
  tester,
  surface: _railSurface,
  theme: theme,
  child: SongReaderControlRail(
    projection: _projection(key),
    onTransposeDown: _noop,
    onTransposeUp: onTransposeUp,
    onCapoDown: _noop,
    onCapoUp: _noop,
    onDecreaseFontScale: _noop,
    onIncreaseFontScale: _noop,
    keyActions: keyActions,
  ),
);

Future<void> _pumpPanel(
  WidgetTester tester, {
  required ResolvedSongKey key,
  required SongReaderKeyActions keyActions,
  ThemeData? theme,
}) => _pumpSurface(
  tester,
  surface: _panelSurface,
  theme: theme,
  child: SizedBox(
    width: _panelWidth,
    child: SongReaderExpandedToolsPanel(
      projection: _projection(key),
      onTransposeDown: _noop,
      onTransposeUp: _noop,
      onCapoDown: _noop,
      onCapoUp: _noop,
      onDecreaseFontScale: _noop,
      onIncreaseFontScale: _noop,
      keyActions: keyActions,
    ),
  ),
);

void _noop() {}
