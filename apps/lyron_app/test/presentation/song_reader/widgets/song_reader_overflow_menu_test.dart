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
