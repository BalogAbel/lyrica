import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
  }

  testWidgets('offers lyrics-only toggle when chords are shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: false,
            isDarkActive: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await openMenu(tester);

    expect(find.text(AppStrings.songReaderLyricsOnlyAction), findsOneWidget);
    expect(find.text(AppStrings.songReaderChordsAndLyricsAction), findsNothing);
  });

  testWidgets('offers chords-and-lyrics toggle when lyrics-only is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.lyricsOnly,
            canEditSongs: false,
            isDarkActive: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await openMenu(tester);

    expect(
      find.text(AppStrings.songReaderChordsAndLyricsAction),
      findsOneWidget,
    );
    expect(find.text(AppStrings.songReaderLyricsOnlyAction), findsNothing);
  });

  testWidgets('hides edit and delete entries when canEditSongs is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: false,
            isDarkActive: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await openMenu(tester);

    expect(find.text(AppStrings.songEditAction), findsNothing);
    expect(find.text(AppStrings.songDeleteAction), findsNothing);
  });

  testWidgets('shows edit and delete entries when canEditSongs is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: true,
            isDarkActive: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await openMenu(tester);

    expect(find.text(AppStrings.songEditAction), findsOneWidget);
    expect(find.text(AppStrings.songDeleteAction), findsOneWidget);
  });

  testWidgets('reports the selected action', (tester) async {
    final selections = <SongReaderOverflowAction>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: true,
            isDarkActive: false,
            onSelected: selections.add,
          ),
        ),
      ),
    );

    await openMenu(tester);
    await tester.tap(find.text(AppStrings.songDeleteAction));
    await tester.pumpAndSettle();

    expect(selections, [SongReaderOverflowAction.delete]);
  });

  testWidgets('offers dark view while light is active', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: false,
            isDarkActive: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await openMenu(tester);

    expect(find.text(AppStrings.songReaderDarkThemeAction), findsOneWidget);
    expect(find.text(AppStrings.songReaderLightThemeAction), findsNothing);
  });

  testWidgets('offers light view while dark is active', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: false,
            isDarkActive: true,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await openMenu(tester);

    expect(find.text(AppStrings.songReaderLightThemeAction), findsOneWidget);
    expect(find.text(AppStrings.songReaderDarkThemeAction), findsNothing);
  });

  group('Clear plan value', () {
    Future<void> pumpMenu(
      WidgetTester tester, {
      bool canEditSongs = false,
      bool canClearPlanValue = false,
      void Function(SongReaderOverflowAction action)? onSelected,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongReaderOverflowMenu(
              viewMode: SongReaderViewMode.chordsAndLyrics,
              canEditSongs: canEditSongs,
              isDarkActive: false,
              canClearPlanValue: canClearPlanValue,
              onSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      );
    }

    /// The open menu top to bottom: item texts, and `---` for each divider.
    List<String> menuEntries(WidgetTester tester) {
      final entries = <(double, String)>[
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(PopupMenuItem<SongReaderOverflowAction>),
            matching: find.byType(Text),
          ),
        ))
          (tester.getTopLeft(find.byWidget(text)).dy, text.data!),
        for (final divider in tester.elementList(find.byType(PopupMenuDivider)))
          (tester.getTopLeft(find.byWidget(divider.widget)).dy, '---'),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final entry in entries) entry.$2];
    }

    testWidgets('sits after the instrument views and before the theme, with '
        'a divider on each side', (tester) async {
      await pumpMenu(tester, canClearPlanValue: true);
      await openMenu(tester);

      expect(menuEntries(tester), [
        AppStrings.songReaderLyricsOnlyAction,
        '---',
        AppStrings.songReaderGuitarViewAction,
        AppStrings.songReaderPianoViewAction,
        '---',
        AppStrings.songReaderClearPlanValueAction,
        '---',
        AppStrings.songReaderDarkThemeAction,
      ]);
    });

    testWidgets('leaves the edit and delete entries after the theme', (
      tester,
    ) async {
      await pumpMenu(tester, canEditSongs: true, canClearPlanValue: true);
      await openMenu(tester);

      expect(menuEntries(tester), [
        AppStrings.songReaderLyricsOnlyAction,
        '---',
        AppStrings.songReaderGuitarViewAction,
        AppStrings.songReaderPianoViewAction,
        '---',
        AppStrings.songReaderClearPlanValueAction,
        '---',
        AppStrings.songReaderDarkThemeAction,
        '---',
        AppStrings.songEditAction,
        AppStrings.songDeleteAction,
      ]);
    });

    testWidgets('is absent by default, and the other entries keep their '
        'order and dividers', (tester) async {
      // The parameter is left out: this is the default.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongReaderOverflowMenu(
              viewMode: SongReaderViewMode.chordsAndLyrics,
              canEditSongs: true,
              isDarkActive: false,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await openMenu(tester);

      expect(
        find.text(AppStrings.songReaderClearPlanValueAction),
        findsNothing,
      );
      expect(menuEntries(tester), [
        AppStrings.songReaderLyricsOnlyAction,
        '---',
        AppStrings.songReaderGuitarViewAction,
        AppStrings.songReaderPianoViewAction,
        '---',
        AppStrings.songReaderDarkThemeAction,
        '---',
        AppStrings.songEditAction,
        AppStrings.songDeleteAction,
      ]);
    });

    testWidgets('emits clearPlanValue when the entry is tapped', (
      tester,
    ) async {
      final selections = <SongReaderOverflowAction>[];
      await pumpMenu(
        tester,
        canClearPlanValue: true,
        onSelected: selections.add,
      );

      await openMenu(tester);
      await tester.tap(find.text(AppStrings.songReaderClearPlanValueAction));
      await tester.pumpAndSettle();

      expect(selections, [SongReaderOverflowAction.clearPlanValue]);
    });
  });

  testWidgets('emits toggleTheme when the entry is tapped', (tester) async {
    final selections = <SongReaderOverflowAction>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderOverflowMenu(
            viewMode: SongReaderViewMode.chordsAndLyrics,
            canEditSongs: false,
            isDarkActive: false,
            onSelected: selections.add,
          ),
        ),
      ),
    );

    await openMenu(tester);
    await tester.tap(find.text(AppStrings.songReaderDarkThemeAction));
    await tester.pumpAndSettle();

    expect(selections, [SongReaderOverflowAction.toggleTheme]);
  });
}
