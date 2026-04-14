import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart';

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
}
