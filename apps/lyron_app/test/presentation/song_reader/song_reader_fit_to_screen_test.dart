import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a tall projection with many sections so its estimated height at
/// scale=1.0 far exceeds a 600-pixel viewport.
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

Widget _buildSurface({
  required SongReaderProjection projection,
  required ValueChanged<double> onSetFontScale,
  VoidCallback? onPersistFontScale,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SongReaderCompactSurface(
        projection: projection,
        areControlsVisible: false,
        currentTitle: projection.title,
        onSurfaceTap: () {},
        hasRecoverableWarnings: false,
        warningCount: 0,
        contentColumnCount: 1,
        onToggleViewMode: () {},
        onTransposeDown: () {},
        onTransposeUp: () {},
        onDecreaseFontScale: () {},
        onIncreaseFontScale: () {},
        showBottomContextBar: false,
        maxContentWidth: 960,
        contentPadding: const EdgeInsets.all(24),
        onSetFontScale: onSetFontScale,
        onPersistFontScale: onPersistFontScale,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Viewport: 400 wide × 600 tall (logical pixels, DPR=1).
  const viewportWidth = 400.0;
  const viewportHeight = 600.0;
  // The scaffold body fills the full viewport; AppBar adds ~56px, so the
  // LayoutBuilder inside the surface sees slightly less height. But for the
  // purpose of asserting "fit < 1.0" the exact number doesn't matter — the
  // song is so tall that it definitely needs shrinking.

  group('SongReaderCompactSurface double-tap fit-to-screen', () {
    testWidgets(
      'first double-tap applies a fit scale smaller than 1.0 for a tall song',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final scaleCalls = <double>[];
        var persistCalls = 0;

        final projection = _buildTallProjection(fontScale: 1.0);

        await tester.pumpWidget(
          _buildSurface(
            projection: projection,
            onSetFontScale: scaleCalls.add,
            onPersistFontScale: () => persistCalls++,
          ),
        );
        await tester.pump();

        final center = tester.getCenter(find.byType(SongReaderCompactSurface));

        // Two taps within the double-tap window.
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(
          scaleCalls,
          isNotEmpty,
          reason: 'onSetFontScale must be called on first double-tap',
        );
        expect(
          scaleCalls.last,
          lessThan(1.0),
          reason: 'fit scale for a tall song must be less than 1.0',
        );
        expect(persistCalls, greaterThan(0), reason: 'onPersistFontScale must be called');
      },
    );

    testWidgets(
      'second double-tap restores the original scale',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // We need to drive the widget with a mutable scale so didUpdateWidget
        // correctly sees scale changes. Use a StatefulWidget wrapper.
        double currentScale = 1.0;
        final scaleCalls = <double>[];

        late StateSetter setStateOuter;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  setStateOuter = setState;
                  final projection = _buildTallProjection(fontScale: currentScale);
                  return SongReaderCompactSurface(
                    projection: projection,
                    areControlsVisible: false,
                    currentTitle: projection.title,
                    onSurfaceTap: () {},
                    hasRecoverableWarnings: false,
                    warningCount: 0,
                    contentColumnCount: 1,
                    onToggleViewMode: () {},
                    onTransposeDown: () {},
                    onTransposeUp: () {},
                    onDecreaseFontScale: () {},
                    onIncreaseFontScale: () {},
                    showBottomContextBar: false,
                    maxContentWidth: 960,
                    contentPadding: const EdgeInsets.all(24),
                    onSetFontScale: (s) {
                      scaleCalls.add(s);
                      // Simulate the parent updating the projection scale.
                      setStateOuter(() => currentScale = s);
                    },
                    onPersistFontScale: () {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        final center = tester.getCenter(find.byType(SongReaderCompactSurface));

        // --- First double-tap: fit ---
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(scaleCalls, isNotEmpty);
        final fitScale = scaleCalls.last;
        expect(fitScale, lessThan(1.0));

        // --- Second double-tap: restore ---
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(scaleCalls.length, greaterThan(1));
        expect(
          scaleCalls.last,
          moreOrLessEquals(1.0, epsilon: 1e-9),
          reason: 'second double-tap must restore original scale 1.0',
        );
      },
    );

    testWidgets(
      'fit scale matches resolveFitFontScale for the same viewport',
      (tester) async {
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final scaleCalls = <double>[];
        final projection = _buildTallProjection(fontScale: 1.0);

        await tester.pumpWidget(
          _buildSurface(
            projection: projection,
            onSetFontScale: scaleCalls.add,
          ),
        );
        await tester.pump();

        // Measure actual LayoutBuilder height from the rendered tree.
        // The Scaffold body height minus any chrome (AppBar ~56px) is what the
        // LayoutBuilder sees. Use the rendered size of the scrollable area.
        final scrollableSize = tester.getSize(find.byType(SingleChildScrollView));
        final availableWidth = scrollableSize.width;
        final availableHeight = scrollableSize.height;

        // Content render width is min(availableWidth, maxContentWidth=960).
        final contentRenderWidth = availableWidth < 960 ? availableWidth : 960.0;

        final expectedFit = resolveFitFontScale(
          sections: projection.sections,
          viewMode: projection.viewMode,
          availableWidth: contentRenderWidth,
          availableHeight: availableHeight,
          minScale: SongReaderState.minSharedFontScale,
          maxScale: SongReaderState.maxSharedFontScale,
        );

        final center = tester.getCenter(find.byType(SongReaderCompactSurface));
        await tester.tapAt(center);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(scaleCalls, isNotEmpty);
        expect(
          scaleCalls.last,
          moreOrLessEquals(expectedFit, epsilon: 1e-6),
          reason: 'applied fit scale must match resolveFitFontScale output',
        );
      },
    );
  });
}
