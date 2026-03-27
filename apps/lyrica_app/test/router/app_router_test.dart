import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/router/app_router.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

void main() {
  test('list, sign-in, and reader route constants remain stable', () {
    expect(AppRoutes.bootstrap.path, '/bootstrap');
    expect(AppRoutes.home.path, '/');
    expect(AppRoutes.signIn.path, '/sign-in');
    expect(AppRoutes.songReader.path, '/songs/:songId');
  });

  testWidgets('signed-out users land on the sign-in route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_TestAuthRepository()),
        ],
        child: Consumer(
          builder: (context, ref, child) =>
              MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Egy út'), findsNothing);
  });

  testWidgets(
    'initializing users stay on bootstrap loading until auth restore completes',
    (WidgetTester tester) async {
      final completer = Completer<AppAuthSession?>();
      final repository = _DelayedAuthRepository(completer.future);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: Consumer(
            builder: (context, ref, child) =>
                MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Restoring session...'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      completer.complete(null);
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
    },
  );

  testWidgets('signed-in users are redirected away from the sign-in route', (
    WidgetTester tester,
  ) async {
    final repository = _TestAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyrica.local',
      ),
    );
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          catalogSnapshotStateProvider.overrideWithValue(
            const CatalogSnapshotState(
              context: ActiveCatalogContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
              connectionStatus: CatalogConnectionStatus.online,
              refreshStatus: CatalogRefreshStatus.idle,
              sessionStatus: CatalogSessionStatus.verified,
              hasCachedCatalog: true,
            ),
          ),
          songLibraryListProvider.overrideWith(
            (ref) async => const [SongSummary(id: 'egy_ut', title: 'Egy út')],
          ),
        ],
        child: Consumer(
          builder: (context, ref, child) => MaterialApp.router(
            routerConfig: createAppRouter(
              authController: controller,
              refreshListenable: controller,
              initialLocation: AppRoutes.signIn.path,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Egy út'), findsOneWidget);
  });

  testWidgets('signed-out users cannot open the reader route directly', (
    WidgetTester tester,
  ) async {
    final repository = _TestAuthRepository();
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
        ],
        child: Consumer(
          builder: (context, ref, child) => MaterialApp.router(
            routerConfig: createAppRouter(
              authController: controller,
              refreshListenable: controller,
              initialLocation: '/songs/blocked',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Song reader'), findsNothing);
  });

  testWidgets(
    'direct reader entry falls back to the song list without a back loop',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyrica.local',
        ),
      );
      final controller = AppAuthController(repository);
      await controller.restoreSession();
      addTearDown(controller.dispose);

      final router = createAppRouter(
        authController: controller,
        refreshListenable: controller,
        initialLocation: '/songs/blocked',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWithValue(controller),
            appAuthListenableProvider.overrideWithValue(controller),
            activeCatalogContextProvider.overrideWithValue(
              const ActiveCatalogContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: ActiveCatalogContext(
                  userId: 'user-1',
                  organizationId: 'org-1',
                ),
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            songLibraryListProvider.overrideWith(
              (ref) async => const [
                SongSummary(id: 'blocked', title: 'Blocked Song'),
              ],
            ),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => SongReaderResult(
                  song: ParsedSong(
                    title: 'Blocked Song',
                    sourceKey: 'C',
                    sections: const [],
                    diagnostics: const [],
                  ),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/songs/blocked',
      );

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text('Blocked Song'), findsOneWidget);
      expect(find.text('Song reader'), findsNothing);
      expect(router.routeInformationProvider.value.uri.toString(), '/');

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isFalse);
      expect(find.text('Song reader'), findsNothing);
      expect(router.routeInformationProvider.value.uri.toString(), '/');
    },
  );
}

class _TestAuthRepository implements AuthRepository {
  _TestAuthRepository({this.restoredSession});

  final AppAuthSession? restoredSession;

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

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

class _DelayedAuthRepository implements AuthRepository {
  _DelayedAuthRepository(this._restoreFuture);

  final Future<AppAuthSession?> _restoreFuture;

  @override
  Future<AppAuthSession?> restoreSession() => _restoreFuture;

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
