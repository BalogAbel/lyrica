import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/presentation/song_library/song_library_providers.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({
    required List<SongSummary> songs,
    Completer<List<SongSummary>>? loadingCompleter,
  }) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SongListScreen(),
        ),
        GoRoute(
          path: '/songs/:songId',
          builder: (context, state) {
            final songId = state.pathParameters['songId']!;
            return Material(
              child: Text('reader:$songId'),
            );
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        songLibraryListProvider.overrideWith((ref) {
          if (loadingCompleter != null) {
            return loadingCompleter.future;
          }

          return Future.value(songs);
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shows song titles only', (tester) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', title: 'Egy út'),
          SongSummary(id: 'felkel_a_nap', title: 'Felkel a nap'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Egy út'), findsOneWidget);
    expect(find.text('Felkel a nap'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));

    final firstTile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(firstTile.subtitle, isNull);
    expect(firstTile.leading, isNull);
    expect(firstTile.trailing, isNull);
  });

  testWidgets('navigates to the reader route when a title is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', title: 'Egy út'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Egy út'));
    await tester.pumpAndSettle();

    expect(find.text('reader:egy_ut'), findsOneWidget);
  });

  testWidgets('shows an explicit loading state while songs load', (
    tester,
  ) async {
    final completer = Completer<List<SongSummary>>();

    await tester.pumpWidget(
      buildApp(
        songs: const [],
        loadingCompleter: completer,
      ),
    );
    await tester.pump();

    expect(find.text('Loading songs...'), findsOneWidget);
  });

  testWidgets('shows an explicit empty state when no songs are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No songs available.'), findsOneWidget);
  });
}
