import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({
    List<SongSummary> songs = const [],
    Completer<List<SongSummary>>? loadingCompleter,
    Future<List<SongSummary>> Function()? listSongs,
    CatalogSnapshotState catalogState = const CatalogSnapshotState(
      context: null,
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    ),
  }) {
    final authController = AppAuthController(_TestAuthRepository());
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
        GoRoute(
          path: '/songs/:songId',
          builder: (context, state) {
            final songId = state.pathParameters['songId']!;
            return Material(child: Text('reader:$songId'));
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        appAuthControllerProvider.overrideWithValue(authController),
        appAuthListenableProvider.overrideWithValue(authController),
        catalogSnapshotStateProvider.overrideWithValue(catalogState),
        songLibraryListProvider.overrideWith((ref) {
          if (listSongs != null) {
            return listSongs();
          }

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
        catalogState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCatalogOnlineStatus), findsOneWidget);
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
        songs: const [SongSummary(id: 'egy_ut', title: 'Egy út')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Egy út'));
    await tester.pumpAndSettle();

    expect(find.text('reader:egy_ut'), findsOneWidget);
  });

  testWidgets('returns to the song list after opening a song from the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [SongSummary(id: 'egy_ut', title: 'Egy út')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Egy út'));
    await tester.pumpAndSettle();

    expect(find.text('reader:egy_ut'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('reader:egy_ut'), findsNothing);
    expect(find.text('Egy út'), findsOneWidget);
    expect(find.byType(SongListScreen), findsOneWidget);
  });

  testWidgets('shows an explicit loading state while songs load', (
    tester,
  ) async {
    final completer = Completer<List<SongSummary>>();

    await tester.pumpWidget(
      buildApp(songs: const [], loadingCompleter: completer),
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
        catalogState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No songs available.'), findsOneWidget);
  });

  testWidgets('shows persistent offline and refresh-failed status surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [SongSummary(id: 'egy_ut', title: 'Egy út')],
        catalogState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.offlineCached,
          refreshStatus: CatalogRefreshStatus.failed,
          sessionStatus: CatalogSessionStatus.unverifiableDueToConnectivity,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCatalogOfflineStatus), findsOneWidget);
    expect(
      find.text(AppStrings.songCatalogRefreshFailedStatus),
      findsOneWidget,
    );
  });

  testWidgets('shows a persistent refreshing status surface', (tester) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [SongSummary(id: 'egy_ut', title: 'Egy út')],
        catalogState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.refreshing,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCatalogRefreshingStatus), findsOneWidget);
  });

  testWidgets('shows an unavailable state when no cached catalog exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [],
        catalogState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.unavailable,
          refreshStatus: CatalogRefreshStatus.failed,
          sessionStatus: CatalogSessionStatus.unverifiableDueToConnectivity,
          hasCachedCatalog: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCatalogUnavailableMessage), findsOneWidget);
    expect(find.text(AppStrings.songListEmptyMessage), findsNothing);
  });

  testWidgets(
    'keeps showing a loading state while the authenticated catalog context is still resolving',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          songs: const [],
          catalogState: const CatalogSnapshotState(
            context: null,
            connectionStatus: CatalogConnectionStatus.unavailable,
            refreshStatus: CatalogRefreshStatus.refreshing,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.songListLoadingMessage), findsOneWidget);
      expect(find.text(AppStrings.songCatalogUnavailableMessage), findsNothing);
    },
  );

  testWidgets(
    'shows a retryable backend failure state while list loading fails',
    (tester) async {
      var attempts = 0;

      await tester.pumpWidget(
        buildApp(
          listSongs: () async {
            attempts += 1;
            if (attempts == 1) {
              throw Exception('backend unavailable');
            }

            return const [SongSummary(id: 'egy_ut', title: 'Egy út')];
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to load songs. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Egy út'), findsOneWidget);
      expect(attempts, 2);
    },
  );
}

class _TestAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async {
    return const AppAuthSession(userId: 'user-1', email: 'demo@lyrica.local');
  }

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}
