import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_tab_bar.dart';

void main() {
  testWidgets('renders a choice chip per tab and marks the selected one', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongEditorTabBar(
            selectedTab: SongEditorTab.source,
            onSelectedTab: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);

    final sourceChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Source'),
    );
    final overviewChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Overview'),
    );

    expect(sourceChip.selected, isTrue);
    expect(overviewChip.selected, isFalse);
  });

  testWidgets('reports the tapped tab through onSelectedTab', (tester) async {
    SongEditorTab? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongEditorTabBar(
            selectedTab: SongEditorTab.overview,
            onSelectedTab: (tab) => selected = tab,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Preview'));
    await tester.pump();

    expect(selected, SongEditorTab.preview);
  });
}
