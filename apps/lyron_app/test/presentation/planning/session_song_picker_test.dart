import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker_state.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildLauncher({required List<SongSummary> eligibleSongs}) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  unawaited(
                    showSessionSongPicker(
                      context: context,
                      eligibleSongs: eligibleSongs,
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          );
        },
      ),
    );
  }

  testWidgets('search narrows eligible songs and shows no-results copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLauncher(
        eligibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      'alp',
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      'zzz',
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.sessionItemSongPickerNoResultsMessage),
      findsOneWidget,
    );
  });

  testWidgets('shows explicit no-eligible copy when no songs can be added', (
    tester,
  ) async {
    await tester.pumpWidget(buildLauncher(eligibleSongs: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.sessionItemSongPickerEmptyMessage),
      findsOneWidget,
    );
  });

  testWidgets('sorts eligible songs by title in the picker', (tester) async {
    await tester.pumpWidget(
      buildLauncher(
        eligibleSongs: const [
          SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) {
          return (tile.title as Text).data;
        })
        .toList(growable: false);

    expect(titles, orderedEquals(const ['Alpha', 'Beta', 'Gamma']));
  });

  testWidgets('reopening picker starts with empty query', (tester) async {
    await tester.pumpWidget(
      buildLauncher(
        eligibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      'alp',
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('session-song-picker-search-field')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('compact picker uses sheet chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionSongPicker(
          compact: true,
          eligibleSongs: const [
            SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          ],
          onPick: (_) => true,
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsOneWidget,
    );
  });

  testWidgets('loading picker shows explicit loading copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionSongPicker(
          compact: false,
          phase: SessionSongPickerPhase.loading,
          eligibleSongs: const [
            SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          ],
          onPick: (_) => true,
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.sessionItemSongPickerLoadingMessage),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsOneWidget,
    );
  });

  testWidgets('unavailable picker shows explicit unavailable copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionSongPicker(
          compact: false,
          phase: SessionSongPickerPhase.unavailable,
          eligibleSongs: const [
            SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          ],
          onPick: (_) => true,
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.sessionItemSongPickerUnavailableMessage),
      findsOneWidget,
    );
  });

  testWidgets('add in progress picker shows explicit progress copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionSongPicker(
          compact: false,
          phase: SessionSongPickerPhase.addInProgress,
          eligibleSongs: const [
            SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          ],
          onPick: (_) => true,
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.sessionItemSongPickerAddInProgressMessage),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsOneWidget,
    );
  });

  testWidgets('escape dismisses the picker', (tester) async {
    await tester.pumpWidget(
      buildLauncher(
        eligibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsNothing,
    );
  });

  testWidgets('onPick exception closes the wide picker', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showSessionSongPicker(
                        context: context,
                        eligibleSongs: const [
                          SongSummary(
                            id: 'song-1',
                            slug: 'alpha',
                            title: 'Alpha',
                          ),
                        ],
                        onPick: (_) {
                          throw StateError('boom');
                        },
                      ),
                    );
                  },
                  child: const Text('Open picker'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('session-song-option-song-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsNothing,
    );
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets(
    'wide picker future waits for add callback after closing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final addCompleter = Completer<bool>();
      var resultCompleted = false;
      SongSummary? pickedSong;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      unawaited(
                        showSessionSongPicker(
                          context: context,
                          eligibleSongs: const [
                            SongSummary(
                              id: 'song-1',
                              slug: 'alpha',
                              title: 'Alpha',
                            ),
                          ],
                          onPick: (_) => addCompleter.future,
                        ).then((value) {
                          resultCompleted = true;
                          pickedSong = value;
                        }),
                      );
                    },
                    child: const Text('Open picker'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('session-song-option-song-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('session-song-picker-body')),
        findsNothing,
      );
      expect(resultCompleted, isFalse);

      addCompleter.complete(true);
      await tester.pumpAndSettle();

      expect(resultCompleted, isTrue);
      expect(pickedSong?.id, 'song-1');
    },
  );

  testWidgets('enter activates a focused picker row', (tester) async {
    SongSummary pickedSong = const SongSummary(
      id: 'song-0',
      slug: 'unset',
      title: 'Unset',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showSessionSongPicker(
                        context: context,
                        eligibleSongs: const [
                          SongSummary(
                            id: 'song-1',
                            slug: 'alpha',
                            title: 'Alpha',
                          ),
                        ],
                      ).then((value) {
                        if (value != null) {
                          pickedSong = value;
                        }
                      }),
                    );
                  },
                  child: const Text('Open picker'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('session-song-picker-search-field')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(pickedSong.id, 'song-1');
    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsNothing,
    );
  });
}
