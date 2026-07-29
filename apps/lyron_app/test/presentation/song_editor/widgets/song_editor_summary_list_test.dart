import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_controller.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_summary_list.dart';

void main() {
  testWidgets('renders every projected summary field', (tester) async {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
    );
    final projection = SongEditorProjection(state: controller.state);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SongEditorSummaryList(projection: projection)),
      ),
    );

    expect(find.text('Heart of Worship'), findsOneWidget);
    expect(find.text('Matt Redman'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('72 bpm'), findsOneWidget);
    expect(find.text('worship, acoustic'), findsOneWidget);
    expect(find.text('Transpose +1 · Capo 2'), findsOneWidget);
  });

  testWidgets('falls back to placeholder text for missing metadata', (
    tester,
  ) async {
    final controller = SongEditorController(
      source: '''
{title: }

[D]Untitled line
''',
    );
    final projection = SongEditorProjection(state: controller.state);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SongEditorSummaryList(projection: projection)),
      ),
    );

    expect(find.text('Untitled song'), findsOneWidget);
    expect(find.text('Unknown artist'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });
}
