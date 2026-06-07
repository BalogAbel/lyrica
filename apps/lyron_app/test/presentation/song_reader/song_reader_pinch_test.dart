import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SongReaderProjection _buildProjection({double fontScale = 1.0}) {
  return SongReaderProjection(
    song: ParsedSong(
      title: 'Pinch Test Song',
      sourceKey: 'G',
      sections: [
        SongSection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          lines: [
            LyricLine(
              segments: [
                const LyricSegment(leadingChord: 'G', text: 'Hello world'),
              ],
            ),
          ],
        ),
      ],
      diagnostics: const [],
    ),
    state: SongReaderState(sharedFontScale: fontScale),
  );
}

/// Tall projection with many lines to force vertical scroll.
SongReaderProjection _buildTallProjection() {
  final lines = List.generate(
    60,
    (i) => LyricLine(
      segments: [
        LyricSegment(leadingChord: 'Am', text: 'Line $i of many lines'),
      ],
    ),
  );
  return SongReaderProjection(
    song: ParsedSong(
      title: 'Tall Song',
      sourceKey: 'Am',
      sections: [
        SongSection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          lines: lines,
        ),
      ],
      diagnostics: const [],
    ),
    state: SongReaderState(),
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
// Pure helper: scale clamping logic (unit test of the arithmetic)
// ---------------------------------------------------------------------------
double applyPinchScale(double baseline, double pinchFactor) {
  return (baseline * pinchFactor).clamp(
    SongReaderState.minSharedFontScale,
    SongReaderState.maxSharedFontScale,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Pure unit tests — no widget machinery, always reliable
  // -------------------------------------------------------------------------
  group('pinch scale computation', () {
    test('spreading fingers doubles scale', () {
      expect(applyPinchScale(1.0, 2.0), 2.0);
    });

    test('pinching fingers halves scale', () {
      expect(applyPinchScale(1.0, 0.5), 0.5);
    });

    test('clamps above maxSharedFontScale', () {
      expect(applyPinchScale(2.0, 2.0), SongReaderState.maxSharedFontScale);
    });

    test('clamps below minSharedFontScale', () {
      expect(applyPinchScale(0.3, 0.1), SongReaderState.minSharedFontScale);
    });

    test('baseline * 1.0 = baseline', () {
      expect(applyPinchScale(1.5, 1.0), 1.5);
    });
  });

  // -------------------------------------------------------------------------
  // Widget tests
  // -------------------------------------------------------------------------
  group('SongReaderCompactSurface pinch-to-zoom', () {
    testWidgets('two-finger pinch increases font scale via onSetFontScale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      double? lastScale;
      final projection = _buildProjection(fontScale: 1.0);

      await tester.pumpWidget(
        _buildSurface(
          projection: projection,
          onSetFontScale: (s) => lastScale = s,
        ),
      );
      await tester.pump();

      // Two-finger pinch: start two touches near centre, spread them apart.
      final centre = tester.getCenter(find.byType(SongReaderCompactSurface));
      final finger1Start = centre + const Offset(-20, 0);
      final finger2Start = centre + const Offset(20, 0);

      final touch1 = await tester.startGesture(finger1Start);
      final touch2 = await tester.startGesture(finger2Start);
      await tester.pump();

      // Spread outward — simulate scale ~2x.
      await touch1.moveBy(const Offset(-60, 0));
      await touch2.moveBy(const Offset(60, 0));
      await tester.pump();

      await touch1.up();
      await touch2.up();
      await tester.pumpAndSettle();

      expect(
        lastScale,
        isNotNull,
        reason: 'onSetFontScale must be called during two-finger pinch',
      );
      expect(
        lastScale!,
        greaterThan(1.0),
        reason: 'Spreading fingers should increase font scale above baseline',
      );
    });

    testWidgets(
      'one-finger drag scrolls content and does not call onSetFontScale',
      (tester) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final calls = <double>[];
        final projection = _buildTallProjection();

        await tester.pumpWidget(
          _buildSurface(projection: projection, onSetFontScale: calls.add),
        );
        await tester.pumpAndSettle();

        // Grab scroll position before drag.
        final scrollable = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        final controller = scrollable.controller!;
        final beforePixels = controller.position.pixels;

        // Single-finger drag upward (scroll content up).
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        expect(
          calls,
          isEmpty,
          reason: 'Single-finger drag must NOT trigger onSetFontScale',
        );
        expect(
          controller.position.pixels,
          greaterThan(beforePixels),
          reason: 'Single-finger drag must scroll the content',
        );
      },
    );

    testWidgets('onPersistFontScale called when pinch ends', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var persistCalls = 0;
      final projection = _buildProjection();

      await tester.pumpWidget(
        _buildSurface(
          projection: projection,
          onSetFontScale: (_) {},
          onPersistFontScale: () => persistCalls++,
        ),
      );
      await tester.pump();

      final centre = tester.getCenter(find.byType(SongReaderCompactSurface));
      final touch1 = await tester.startGesture(centre + const Offset(-20, 0));
      final touch2 = await tester.startGesture(centre + const Offset(20, 0));
      await tester.pump();
      await touch1.moveBy(const Offset(-40, 0));
      await touch2.moveBy(const Offset(40, 0));
      await tester.pump();
      await touch1.up();
      await touch2.up();
      await tester.pumpAndSettle();

      expect(persistCalls, greaterThan(0));
    });
  });
}
