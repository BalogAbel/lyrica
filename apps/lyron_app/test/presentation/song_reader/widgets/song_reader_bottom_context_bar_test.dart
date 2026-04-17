import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  testWidgets('shows current title with optional previous and next labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SongReaderBottomContextBar(
            currentTitle: 'Current Song',
            previousTitle: 'Before',
            nextTitle: 'After',
          ),
        ),
      ),
    );

    expect(find.text('Current Song'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.text(AppStrings.scopedReaderCurrentSongLabel), findsOneWidget);
  });

  testWidgets('previous and next segments use full hit targets', (
    tester,
  ) async {
    var previousTapCount = 0;
    var nextTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderBottomContextBar(
            currentTitle: 'Current Song',
            previousTitle: 'Before',
            nextTitle: 'After',
            onPreviousTap: () => previousTapCount += 1,
            onNextTap: () => nextTapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(SongReaderBottomContextBar.previousSegmentKey));
    await tester.pump();
    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pump();

    expect(previousTapCount, 1);
    expect(nextTapCount, 1);
  });

  testWidgets('stays renderable with only the current song title', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SongReaderBottomContextBar(currentTitle: 'Current Song'),
        ),
      ),
    );

    expect(find.text('Current Song'), findsOneWidget);
    expect(find.byType(SongReaderBottomContextBar), findsOneWidget);
  });

  testWidgets('disabled neighbor segments render with reduced opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SongReaderBottomContextBar(currentTitle: 'Current Song'),
        ),
      ),
    );

    final opacityWidgets = tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byType(SongReaderBottomContextBar),
            matching: find.byType(Opacity),
          ),
        )
        .toList();

    expect(opacityWidgets, isNotEmpty);
    expect(
      opacityWidgets
          .where(
            (widget) =>
                widget.opacity ==
                SongReaderBottomContextBar.disabledSegmentOpacity,
          )
          .length,
      2,
    );
  });
}
