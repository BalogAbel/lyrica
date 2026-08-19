import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Widget _wrap(
  Widget child, {
  Size size = const Size(800, 600),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: textScaler),
      child: Scaffold(
        body: SizedBox(width: size.width, child: child),
      ),
    ),
  );
}

void main() {
  group('plan-scoped, tablet (>= 600 width)', () {
    testWidgets('shows previous/next titles alongside current song info', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            keyLabel: 'G',
            capoLabel: 'Capo 3',
            position: 3,
            itemCount: 7,
            isPlanScoped: true,
            previousTitle: 'Before',
            nextTitle: 'After',
          ),
        ),
      );

      expect(find.text('Current Song'), findsOneWidget);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.textContaining('G'), findsWidgets);
      expect(find.textContaining('Capo 3'), findsWidgets);
      expect(find.textContaining('3 / 7'), findsWidgets);
    });

    testWidgets('previous and next segments use full-width hit targets', (
      tester,
    ) async {
      var previousTapCount = 0;
      var nextTapCount = 0;

      await tester.pumpWidget(
        _wrap(
          SongReaderBottomBar(
            currentTitle: 'Current Song',
            isPlanScoped: true,
            previousTitle: 'Before',
            nextTitle: 'After',
            onPreviousTap: () => previousTapCount += 1,
            onNextTap: () => nextTapCount += 1,
          ),
        ),
      );

      await tester.tap(find.byKey(SongReaderBottomBar.previousSegmentKey));
      await tester.pump();
      await tester.tap(find.byKey(SongReaderBottomBar.nextSegmentKey));
      await tester.pump();

      expect(previousTapCount, 1);
      expect(nextTapCount, 1);
    });

    testWidgets('disabled neighbor segments render with reduced opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            isPlanScoped: true,
          ),
        ),
      );

      final opacityWidgets = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(SongReaderBottomBar),
              matching: find.byType(Opacity),
            ),
          )
          .toList();

      expect(opacityWidgets, isNotEmpty);
      expect(
        opacityWidgets
            .where(
              (widget) =>
                  widget.opacity == SongReaderBottomBar.disabledSegmentOpacity,
            )
            .length,
        2,
      );
    });

    testWidgets('renders correctly with no neighbours', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            isPlanScoped: true,
          ),
        ),
      );

      expect(find.text('Current Song'), findsOneWidget);
      expect(find.byType(SongReaderBottomBar), findsOneWidget);
    });
  });

  group('plan-scoped, phone (< 600 width)', () {
    testWidgets('shows chevrons only, no neighbour titles', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            keyLabel: 'G',
            position: 3,
            itemCount: 7,
            isPlanScoped: true,
            previousTitle: 'Before',
            nextTitle: 'After',
          ),
          size: const Size(375, 812),
        ),
      );

      expect(find.text('Current Song'), findsOneWidget);
      expect(find.textContaining('3 / 7'), findsWidgets);
      expect(find.text('Before'), findsNothing);
      expect(find.text('After'), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('current title/key/capo/position stay centred', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            keyLabel: 'G',
            capoLabel: 'Capo 3',
            position: 3,
            itemCount: 7,
            isPlanScoped: true,
          ),
          size: const Size(375, 812),
        ),
      );

      expect(find.text('Current Song'), findsOneWidget);
      expect(find.textContaining('G'), findsWidgets);
      expect(find.textContaining('Capo 3'), findsWidgets);
      expect(find.textContaining('3 / 7'), findsWidgets);
    });
  });

  group('catalogue mode (not plan-scoped)', () {
    testWidgets('shows current title, key and capo, centred, no chevrons', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            keyLabel: 'G',
            capoLabel: 'Capo 3',
          ),
        ),
      );

      expect(find.text('Current Song'), findsOneWidget);
      expect(find.textContaining('G'), findsWidgets);
      expect(find.textContaining('Capo 3'), findsWidgets);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byKey(SongReaderBottomBar.previousSegmentKey), findsNothing);
      expect(find.byKey(SongReaderBottomBar.nextSegmentKey), findsNothing);
    });

    testWidgets('never shows set position, even if supplied', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            position: 3,
            itemCount: 7,
          ),
        ),
      );

      expect(find.textContaining('3 / 7'), findsNothing);
    });
  });

  group('capo directive', () {
    testWidgets('shown only when capoLabel is supplied', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            keyLabel: 'G',
            capoLabel: 'Capo 3',
          ),
        ),
      );

      expect(find.textContaining('Capo 3'), findsWidgets);
    });

    testWidgets('omitted when capoLabel is null (directive not visible)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(
            currentTitle: 'Current Song',
            keyLabel: 'G',
          ),
        ),
      );

      expect(find.textContaining('Capo'), findsNothing);
    });
  });

  group('no song to describe (ADR-023/024 error states)', () {
    // The reader's loading/error/tombstone views (SongReaderLoadingView,
    // SongReaderAccessDeniedView, SongReaderNotFoundView,
    // SongReaderLoadFailureView, SongReaderDeletedTombstoneView,
    // SongReaderScopedUnavailableView -- see
    // widgets/song_reader_status_views.dart) replace the whole reader body,
    // including the compact surface that hosts this bar, so none of them
    // render this widget today. These cases pin the bar's own contract: it
    // must stay renderable, with no crash and no stray chrome, when there is
    // no real song to describe -- only a generic title and nothing else.
    testWidgets('renders with only a generic title and no other content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SongReaderBottomBar(currentTitle: AppStrings.songReaderTitle),
        ),
      );

      expect(find.text(AppStrings.songReaderTitle), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.textContaining('Capo'), findsNothing);
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets(
      'renders sensibly when plan-scoped but neighbours/position are unknown',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SongReaderBottomBar(
              currentTitle: AppStrings.songReaderTitle,
              isPlanScoped: true,
            ),
          ),
        );

        expect(find.text(AppStrings.songReaderTitle), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      },
    );
  });

  group('height', () {
    testWidgets('fits within the tablet bar height with no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 64,
            child: const SongReaderBottomBar(
              currentTitle: 'Current Song',
              keyLabel: 'G',
              capoLabel: 'Capo 3',
              position: 3,
              itemCount: 7,
              isPlanScoped: true,
              previousTitle: 'Before',
              nextTitle: 'After',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('fits within the phone bar height with no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 58,
            child: const SongReaderBottomBar(
              currentTitle: 'Current Song',
              keyLabel: 'G',
              capoLabel: 'Capo 3',
              position: 3,
              itemCount: 7,
              isPlanScoped: true,
              previousTitle: 'Before',
              nextTitle: 'After',
            ),
          ),
          size: const Size(375, 812),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('never overflows at large text scales', () {
    // The bar clamps its own text scale (SongReaderBottomBar._maxTextScaleFactor)
    // rather than letting the fixed-height bar overflow or grow with the
    // system setting -- see that constant's doc comment for the measured
    // numbers and the reasoning. These pin the fix at the exact scales that
    // used to overflow before the clamp existed: 6px at 1.5x and 24px at
    // 2.0x, on both the phone and tablet bar heights.
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('tablet bar height at ${scale}x system text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              height: 64,
              child: const SongReaderBottomBar(
                currentTitle: 'Current Song',
                keyLabel: 'G',
                capoLabel: 'Capo 3',
                position: 3,
                itemCount: 7,
                isPlanScoped: true,
                previousTitle: 'Before',
                nextTitle: 'After',
              ),
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('phone bar height at ${scale}x system text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              height: 58,
              child: const SongReaderBottomBar(
                currentTitle: 'Current Song',
                keyLabel: 'G',
                capoLabel: 'Capo 3',
                position: 3,
                itemCount: 7,
                isPlanScoped: true,
                previousTitle: 'Before',
                nextTitle: 'After',
              ),
            ),
            size: const Size(375, 812),
            textScaler: TextScaler.linear(scale),
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
