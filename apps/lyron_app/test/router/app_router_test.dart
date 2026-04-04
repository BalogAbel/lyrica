import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/router/slug_route_resolvers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  test('list, sign-in, planning, and reader route constants remain stable', () {
    expect(AppRoutes.bootstrap.path, '/bootstrap');
    expect(AppRoutes.home.path, '/');
    expect(AppRoutes.signIn.path, '/sign-in');
    expect(AppRoutes.planList.path, '/plans');
    expect(AppRoutes.planDetail.path, '/plans/:planSlug');
    expect(
      AppRoutes.planSessionSongReader.path,
      '/plans/:planSlug/sessions/:sessionSlug/items/:sessionItemId/songs/:songSlug',
    );
    expect(AppRoutes.songReader.path, '/songs/:songSlug');
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
        email: 'demo@lyron.local',
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
            (ref) async => const [
              SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
            ],
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
          planningPlanListProvider.overrideWith(
            (ref) async => [
              PlanSummary(
                id: 'plan-2',
                slug: 'plan-2',
                name: 'Other Plan',
                description: 'Single-session Sunday fixture',
                scheduledFor: DateTime(2026, 4, 5, 8, 30),
                updatedAt: DateTime(2026, 3, 31, 8),
              ),
            ],
          ),
        ],
        child: Consumer(
          builder: (context, ref, child) => MaterialApp.router(
            routerConfig: createAppRouter(
              authController: controller,
              refreshListenable: controller,
              initialLocation: '/songs/blocked-song',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Song reader'), findsNothing);
  });

  testWidgets('signed-out users cannot open the scoped reader route directly', (
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
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepository(planDetail: _planDetailFixture()),
          ),
          planningSyncStateProvider.overrideWithValue(
            const PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: null,
            ),
          ),
          planningPlanDetailBySlugProvider(
            'missing-plan',
          ).overrideWith((ref) => Future<PlanDetail?>.value(null)),
        ],
        child: Consumer(
          builder: (context, ref, child) => MaterialApp.router(
            routerConfig: createAppRouter(
              authController: controller,
              refreshListenable: controller,
              initialLocation:
                  '/plans/sunday-morning/sessions/main-set/items/item-1/songs/egy-ut',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Song reader'), findsNothing);
  });

  testWidgets('signed-out users are redirected away from planning routes', (
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
              initialLocation: AppRoutes.planList.path,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text(AppStrings.planListTitle), findsNothing);
  });

  testWidgets('signed-in users can reach the planning list route', (
    WidgetTester tester,
  ) async {
    final repository = _TestAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      ),
    );
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final router = createAppRouter(
      authController: controller,
      refreshListenable: controller,
      initialLocation: AppRoutes.planList.path,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
          planningPlanListProvider.overrideWith(
            (ref) async => [
              PlanSummary(
                id: 'plan-1',
                slug: 'sunday-morning',
                name: 'Sunday Morning',
                description: 'Single-session Sunday fixture',
                scheduledFor: DateTime(2026, 4, 5, 8, 30),
                updatedAt: DateTime(2026, 3, 31, 8),
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planListTitle), findsOneWidget);
    expect(find.text('Sunday Morning'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.toString(), '/plans');
  });

  testWidgets('signed-in users can reach the plan detail route', (
    WidgetTester tester,
  ) async {
    final repository = _TestAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      ),
    );
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final router = createAppRouter(
      authController: controller,
      refreshListenable: controller,
      initialLocation: AppRoutes.planDetail.path.replaceFirst(
        ':planSlug',
        'sunday-morning',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
          planningPlanListProvider.overrideWith(
            (ref) async => [
              PlanSummary(
                id: 'plan-1',
                slug: 'sunday-morning',
                name: 'Sunday Morning',
                description: 'Single-session Sunday fixture',
                scheduledFor: DateTime(2026, 4, 5, 8, 30),
                updatedAt: DateTime(2026, 3, 31, 8),
              ),
            ],
          ),
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepository(planDetail: _planDetailFixture()),
          ),
          planningPlanDetailProvider(
            'plan-1',
          ).overrideWith((ref) async => _planDetailFixture()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planDetailTitle), findsOneWidget);
    expect(find.text('Sunday Morning'), findsOneWidget);
    expect(find.text('Main Set'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/plans/sunday-morning',
    );
  });

  testWidgets(
    'signed-in users see a not-found surface for an invalid plan slug',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
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
            planningPlanDetailBySlugProvider(
              'missing-plan',
            ).overrideWith((ref) async => null),
          ],
          child: const MaterialApp(
            home: PlanSlugRouteResolver(planSlug: 'missing-plan'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.planDetailTitle), findsNothing);
      expect(find.text('Sunday Morning'), findsNothing);
    },
  );

  testWidgets(
    'signed-in users see a not-found surface for an invalid song slug',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
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
            songLibrarySongBySlugProvider(
              'missing-song',
            ).overrideWith((ref) async => null),
          ],
          child: const MaterialApp(
            home: SongSlugRouteResolver(songSlug: 'missing-song'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsNothing);
    },
  );

  testWidgets('signed-in users can land on the scoped reader route directly', (
    WidgetTester tester,
  ) async {
    final repository = _TestAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      ),
    );
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final router = createAppRouter(
      authController: controller,
      refreshListenable: controller,
      initialLocation:
          '/plans/sunday-morning/sessions/main-set/items/item-1/songs/egy-ut',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
          planningPlanListProvider.overrideWith(
            (ref) async => [
              PlanSummary(
                id: 'plan-1',
                slug: 'sunday-morning',
                name: 'Sunday Morning',
                description: 'Single-session Sunday fixture',
                scheduledFor: DateTime(2026, 4, 5, 8, 30),
                updatedAt: DateTime(2026, 3, 31, 8),
              ),
            ],
          ),
          songLibraryListProvider.overrideWith(
            (ref) async => const [
              SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
            ],
          ),
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepository(planDetail: _planDetailFixture()),
          ),
          planningSyncStateProvider.overrideWithValue(
            const PlanningSyncState(
              userId: 'user-1',
              organizationId: 'org-1',
              accessStatus: PlanningAccessStatus.signedIn,
              refreshStatus: PlanningRefreshStatus.idle,
              hasLocalPlanningData: true,
              lastRefreshedAt: null,
            ),
          ),
          planningPlanDetailBySlugProvider(
            'sunday-morning',
          ).overrideWith((ref) async => _planDetailFixture()),
          planningPlanDetailProvider(
            'plan-1',
          ).overrideWith((ref) async => _planDetailFixture()),
          songLibrarySongBySlugProvider('egy-ut').overrideWith(
            (ref) async => const SongSummary(
              id: 'song-1',
              slug: 'egy-ut',
              title: 'Egy út',
            ),
          ),
          songLibraryServiceProvider.overrideWithValue(
            _FakeSongLibraryService(
              songsBySlug: const {
                'egy-ut': SongSummary(
                  id: 'song-1',
                  slug: 'egy-ut',
                  title: 'Egy út',
                ),
              },
            ),
          ),
          catalogSnapshotStateProvider.overrideWithValue(
            const CatalogSnapshotState(
              context: null,
              connectionStatus: CatalogConnectionStatus.online,
              refreshStatus: CatalogRefreshStatus.idle,
              sessionStatus: CatalogSessionStatus.verified,
              hasCachedCatalog: true,
            ),
          ),
          songLibraryReaderProvider.overrideWithProvider(
            (songId) => FutureProvider.autoDispose(
              (ref) async => SongReaderResult(
                song: ParsedSong(
                  title: 'Egy út',
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
    expect(find.text(AppStrings.scopedReaderPreviousAction), findsOneWidget);
    expect(find.text(AppStrings.scopedReaderNextAction), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/plans/sunday-morning/sessions/main-set/items/item-1/songs/egy-ut',
    );
  });

  testWidgets(
    'signed-in users see a not-found surface for an invalid session slug',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
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
            planningPlanListProvider.overrideWith(
              (ref) async => [
                PlanSummary(
                  id: 'plan-1',
                  slug: 'sunday-morning',
                  name: 'Sunday Morning',
                  description: 'Single-session Sunday fixture',
                  scheduledFor: DateTime(2026, 4, 5, 8, 30),
                  updatedAt: DateTime(2026, 3, 31, 8),
                ),
              ],
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) async => _planDetailFixture()),
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
                SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
              ],
            ),
          ],
          child: const MaterialApp(
            home: PlanSessionSongSlugRouteResolver(
              planSlug: 'sunday-morning',
              sessionSlug: 'missing-session',
              sessionItemId: 'item-1',
              songSlug: 'egy-ut',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsNothing);
    },
  );

  testWidgets(
    'scoped reader route stays loading while catalog context is refreshing',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
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
            planningPlanListProvider.overrideWith(
              (ref) async => [
                PlanSummary(
                  id: 'plan-1',
                  slug: 'sunday-morning',
                  name: 'Sunday Morning',
                  description: 'Single-session Sunday fixture',
                  scheduledFor: DateTime(2026, 4, 5, 8, 30),
                  updatedAt: DateTime(2026, 3, 31, 8),
                ),
              ],
            ),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.refreshing,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            songLibraryListProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(
            home: PlanSessionSongSlugRouteResolver(
              planSlug: 'sunday-morning',
              sessionSlug: 'main-set',
              sessionItemId: 'item-1',
              songSlug: 'egy-ut',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.songReaderLoadingMessage), findsOneWidget);
      expect(find.text(AppStrings.routeNotFoundMessage), findsNothing);
    },
  );

  testWidgets(
    'auth restore keeps the canonical scoped reader route for direct entry',
    (WidgetTester tester) async {
      final completer = Completer<AppAuthSession?>();
      final repository = _DelayedAuthRepository(completer.future);
      final controller = AppAuthController(repository);
      addTearDown(controller.dispose);
      unawaited(controller.restoreSession());
      final router = createAppRouter(
        authController: controller,
        refreshListenable: controller,
        initialLocation:
            '/plans/sunday-morning/sessions/main-set/items/item-1/songs/egy-ut',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWithValue(controller),
            appAuthListenableProvider.overrideWithValue(controller),
            planningPlanListProvider.overrideWith(
              (ref) async => [
                PlanSummary(
                  id: 'plan-1',
                  slug: 'sunday-morning',
                  name: 'Sunday Morning',
                  description: 'Single-session Sunday fixture',
                  scheduledFor: DateTime(2026, 4, 5, 8, 30),
                  updatedAt: DateTime(2026, 3, 31, 8),
                ),
              ],
            ),
            songLibraryListProvider.overrideWith(
              (ref) async => const [
                SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
              ],
            ),
            planningRepositoryProvider.overrideWithValue(
              _FakePlanningRepository(planDetail: _planDetailFixture()),
            ),
            planningSyncStateProvider.overrideWithValue(
              const PlanningSyncState(
                userId: 'user-1',
                organizationId: 'org-1',
                accessStatus: PlanningAccessStatus.signedIn,
                refreshStatus: PlanningRefreshStatus.idle,
                hasLocalPlanningData: true,
                lastRefreshedAt: null,
              ),
            ),
            planningPlanDetailBySlugProvider(
              'sunday-morning',
            ).overrideWith((ref) async => _planDetailFixture()),
            songLibrarySongBySlugProvider('egy-ut').overrideWith(
              (ref) async => const SongSummary(
                id: 'song-1',
                slug: 'egy-ut',
                title: 'Egy út',
              ),
            ),
            songLibraryServiceProvider.overrideWithValue(
              _FakeSongLibraryService(
                songsBySlug: const {
                  'egy-ut': SongSummary(
                    id: 'song-1',
                    slug: 'egy-ut',
                    title: 'Egy út',
                  ),
                },
              ),
            ),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => SongReaderResult(
                  song: ParsedSong(
                    title: 'Egy út',
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
      await tester.pump();

      expect(find.text('Restoring session...'), findsOneWidget);

      completer.complete(
        const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/plans/sunday-morning/sessions/main-set/items/item-1/songs/egy-ut',
      );
    },
  );

  testWidgets(
    'direct reader entry falls back to the song list without a back loop',
    (WidgetTester tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        ),
      );
      final controller = AppAuthController(repository);
      await controller.restoreSession();
      addTearDown(controller.dispose);

      final router = createAppRouter(
        authController: controller,
        refreshListenable: controller,
        initialLocation: '/songs/blocked-song',
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
                SongSummary(
                  id: 'blocked',
                  slug: 'blocked-song',
                  title: 'Blocked Song',
                ),
              ],
            ),
            songLibraryServiceProvider.overrideWithValue(
              _FakeSongLibraryService(
                songsBySlug: const {
                  'blocked-song': SongSummary(
                    id: 'blocked',
                    slug: 'blocked-song',
                    title: 'Blocked Song',
                  ),
                },
              ),
            ),
            songLibrarySongBySlugProvider('blocked-song').overrideWith(
              (ref) async => const SongSummary(
                id: 'blocked',
                slug: 'blocked-song',
                title: 'Blocked Song',
              ),
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
        '/songs/blocked-song',
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

class _FakePlanningRepository implements PlanningRepository {
  _FakePlanningRepository({required this.planDetail});

  final PlanDetail planDetail;

  @override
  Future<PlanDetail> getPlanDetail(String planId) async => planDetail;

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) async {
    return planSlug == planDetail.plan.slug ? planDetail : null;
  }

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async {
    return planSlug == planDetail.plan.slug ? planDetail.plan : null;
  }

  @override
  Future<List<PlanSummary>> listPlans() async => [planDetail.plan];
}

class _FakeSongLibraryService extends SongLibraryService {
  _FakeSongLibraryService({required this.songsBySlug})
    : super(_NoopSongRepository());

  final Map<String, SongSummary> songsBySlug;

  @override
  Future<List<SongSummary>> listSongs({
    required ActiveCatalogContext context,
  }) async {
    return songsBySlug.values.toList();
  }

  @override
  Future<SongSource> getSongSource({
    required ActiveCatalogContext context,
    required String songId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required ActiveCatalogContext context,
    required String songSlug,
  }) async {
    return songsBySlug[songSlug];
  }
}

class _NoopSongRepository implements SongCatalogReadRepository {
  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) {
    throw UnimplementedError();
  }
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

PlanDetail _planDetailFixture() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'sunday-morning',
      name: 'Sunday Morning',
      description: 'Single-session Sunday fixture',
      scheduledFor: DateTime(2026, 4, 5, 8, 30),
      updatedAt: DateTime(2026, 3, 31, 8),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        slug: 'main-set',
        name: 'Main Set',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-1',
            position: 10,
            song: SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
          ),
          SessionItemSummary(
            id: 'item-2',
            position: 20,
            song: SongSummary(id: 'song-2', slug: 'masodik', title: 'Masodik'),
          ),
        ],
      ),
    ],
  );
}
