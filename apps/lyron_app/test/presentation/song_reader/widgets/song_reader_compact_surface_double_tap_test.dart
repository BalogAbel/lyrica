// Regression coverage for the HIGH finding on
// song_reader_compact_surface.dart:328 (2026-08-19 PR #72 review): double-
// tap-to-fit never fired at all.
//
// The bug did not reproduce against a host with a no-op `onSurfaceTap` --
// see song_reader_fit_to_screen_test.dart, whose surface never actually
// toggles `areControlsVisible`, so the old `onDoubleTap: areControlsVisible
// ? null : _handleDoubleTap` gate was always the same value across both taps
// of a double-tap and the bug never triggered. These tests instead host the
// surface behind a real `areControlsVisible` toggle -- `onSurfaceTap` flips
// it via `setState`, the way the production screen actually wires it -- so
// the ambient `Listener`'s pointer-up reveal genuinely fires between the two
// taps of a double-tap, the same way it does in the app.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Builds a tall projection whose estimated height at scale=1.0 far exceeds
/// a 600px viewport, so a fit is guaranteed to shrink it below 1.0 --
/// matching the fixture in song_reader_fit_to_screen_test.dart.
SongReaderProjection _buildTallProjection({double fontScale = 1.0}) {
  final sections = <SongSection>[
    for (var s = 1; s <= 8; s++)
      SongSection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: s,
        lines: [
          for (var l = 0; l < 5; l++)
            LyricLine(
              segments: [
                LyricSegment(
                  leadingChord: 'G',
                  text: 'Line $s-$l a very long lyric that wraps nicely',
                ),
              ],
            ),
        ],
      ),
  ];

  return SongReaderProjection(
    song: ParsedSong(
      title: 'Fit Test Song',
      sourceKey: 'G',
      sections: sections,
      diagnostics: const [],
    ),
    state: SongReaderState(sharedFontScale: fontScale),
  );
}

/// Hosts the surface with `areControlsVisible` driven by a real toggle (like
/// the production screen), plus a real `SongReaderTopBar` with a working
/// overflow menu so the arena-steal regression the old gate guarded against
/// can be pinned too.
class _Harness extends StatefulWidget {
  const _Harness({required this.onSetFontScale, this.onOverflowSelected});

  final ValueChanged<double> onSetFontScale;
  final ValueChanged<SongReaderOverflowAction>? onOverflowSelected;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _controlsVisible = false;
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final projection = _buildTallProjection(fontScale: _scale);
    return MaterialApp(
      home: Scaffold(
        body: SongReaderCompactSurface(
          projection: projection,
          areControlsVisible: _controlsVisible,
          currentTitle: projection.title,
          topBar: SongReaderTopBar(
            title: projection.title,
            onBack: () {},
            showOverflowMenu: true,
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: false,
            isDarkActive: false,
            onOverflowAction: (action) {
              widget.onOverflowSelected?.call(action);
            },
          ),
          onSurfaceTap: () =>
              setState(() => _controlsVisible = !_controlsVisible),
          contentColumnCount: 1,
          onTransposeDown: () {},
          onTransposeUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
          showBottomContextBar: false,
          maxContentWidth: 960,
          contentPadding: const EdgeInsets.all(24),
          onSetFontScale: (s) {
            widget.onSetFontScale(s);
            setState(() => _scale = s);
          },
        ),
      ),
    );
  }
}

void main() {
  const viewportWidth = 400.0;
  const viewportHeight = 600.0;

  group('double-tap-to-fit against a real areControlsVisible toggle', () {
    testWidgets(
      'double-tap starting from the hidden chrome state calls onSetFontScale',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final scaleCalls = <double>[];
        await tester.pumpWidget(_Harness(onSetFontScale: scaleCalls.add));
        await tester.pump();

        expect(find.byType(SongReaderTopBar), findsNothing);

        final center = tester.getCenter(find.byType(SongReaderCompactSurface));
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(
          scaleCalls,
          isNotEmpty,
          reason:
              'the double-tap must reach _handleDoubleTap and call '
              'onSetFontScale even though the first tap of the pair reveals '
              'the chrome and rebuilds the widget mid-gesture',
        );
        expect(scaleCalls.last, lessThan(1.0));
      },
    );

    testWidgets('a second double-tap restores the pre-fit scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scaleCalls = <double>[];
      await tester.pumpWidget(_Harness(onSetFontScale: scaleCalls.add));
      await tester.pump();

      final center = tester.getCenter(find.byType(SongReaderCompactSurface));

      // First double-tap: fit.
      await tester.tapAt(center);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(scaleCalls, isNotEmpty);
      expect(scaleCalls.last, lessThan(1.0));

      // Second double-tap: restore. The chrome is revealed now (see the
      // "final reveal state" test below), so tap the content area directly
      // rather than the surface's own center, which may now sit under the
      // control rail.
      final contentCenter = tester.getCenter(
        find.byType(SongReaderCompactSurface),
      );
      await tester.tapAt(contentCenter);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(contentCenter);
      await tester.pumpAndSettle();

      expect(scaleCalls.length, greaterThanOrEqualTo(2));
      expect(
        scaleCalls.last,
        moreOrLessEquals(1.0, epsilon: 1e-9),
        reason: 'the second double-tap must restore the original scale',
      );
    });

    testWidgets('a single tap still reveals the chrome promptly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_Harness(onSetFontScale: (_) {}));
      await tester.pump();
      expect(find.byType(SongReaderTopBar), findsNothing);

      final center = tester.getCenter(find.byType(SongReaderCompactSurface));
      await tester.tapAt(center);
      // A single tap must not wait out the double-tap window: pump only one
      // frame, not pumpAndSettle, to prove the reveal isn't gated behind
      // GestureDetector.onTap's tap-vs-double-tap arena delay.
      await tester.pump();

      expect(
        find.byType(SongReaderTopBar),
        findsOneWidget,
        reason: 'a single tap must reveal the chrome without a ~300ms lag',
      );

      // Flush the pending double-tap-window timer the lone tap left behind
      // so the test framework doesn't flag it as a leak at teardown.
      await tester.pump(kDoubleTapTimeout);
    });

    testWidgets(
      'the overflow menu can be opened, closed and reopened while the '
      'chrome is revealed (the arena-steal bug the old gate existed for)',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final selected = <SongReaderOverflowAction>[];
        await tester.pumpWidget(
          _Harness(onSetFontScale: (_) {}, onOverflowSelected: selected.add),
        );
        await tester.pump();

        // Reveal the chrome.
        final center = tester.getCenter(find.byType(SongReaderCompactSurface));
        await tester.tapAt(center);
        await tester.pump();
        expect(find.byType(SongReaderTopBar), findsOneWidget);

        // Open, select, then reopen -- twice, to guard against the arena
        // stealing the second open.
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byIcon(Icons.more_horiz));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(AppStrings.songReaderLyricsOnlyAction).last,
          );
          await tester.pumpAndSettle();
        }

        expect(
          selected,
          [
            SongReaderOverflowAction.toggleViewMode,
            SongReaderOverflowAction.toggleViewMode,
          ],
          reason:
              'both opens of the overflow menu must reach onOverflowAction '
              '-- a stolen second tap would leave this with only one entry',
        );
      },
    );

    testWidgets(
      'a double-tap from the hidden state ends with the chrome revealed '
      '(the reveal fires on tap 1 pointer-up, before the arena resolves '
      'tap vs. double-tap, so it cannot be suppressed without lagging the '
      'single-tap reveal)',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_Harness(onSetFontScale: (_) {}));
        await tester.pump();
        expect(find.byType(SongReaderTopBar), findsNothing);

        final center = tester.getCenter(find.byType(SongReaderCompactSurface));
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(
          find.byType(SongReaderTopBar),
          findsOneWidget,
          reason:
              'pinning the intentional final state: the chrome ends up '
              'revealed after a double-tap-to-fit starting from hidden',
        );
      },
    );
  });
}
