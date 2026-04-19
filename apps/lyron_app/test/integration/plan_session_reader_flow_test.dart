import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

import '../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signed-in users can open a scoped reader from plan detail and navigate within the session',
    (tester) async {
      final repository = _StaticAuthRepository(
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
        initialLocation: '/plans',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWithValue(controller),
            appAuthListenableProvider.overrideWithValue(controller),
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
            activeCatalogContextProvider.overrideWithValue(
              const ActiveCatalogContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
            planningPlanListProvider.overrideWith(
              (ref) async => [_planSummaryFixture()],
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) async => _planDetailFixture()),
            songLibraryListProvider.overrideWith(
              (ref) async => [
                _songSummaryFixture('song-1'),
                _songSummaryFixture('song-2'),
              ],
            ),
            songLibrarySongByIdProvider(
              'song-1',
            ).overrideWith((ref) async => _songSummaryFixture('song-1')),
            songLibrarySongByIdProvider(
              'song-2',
            ).overrideWith((ref) async => _songSummaryFixture('song-2')),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => _songResultFor(songId),
              ),
            ),
          ],
          child: LyronApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sunday Morning'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-session-item-item-1')));
      await tester.pumpAndSettle();

      expect(find.text('Repeated Song'), findsWidgets);
      expect(find.text(AppStrings.scopedReaderNextAction), findsOneWidget);

      await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
      await tester.pumpAndSettle();

      expect(find.text('Second Song'), findsWidgets);
    },
  );

  testWidgets('scoped reader direct entry resolves by session and song slug', (
    tester,
  ) async {
    final repository = _StaticAuthRepository(
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
          '/plans/plan-1/sessions/session-1/items/songs/repeated-song',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
          catalogSnapshotStateProvider.overrideWithValue(
            const CatalogSnapshotState(
              context: null,
              connectionStatus: CatalogConnectionStatus.online,
              refreshStatus: CatalogRefreshStatus.idle,
              sessionStatus: CatalogSessionStatus.verified,
              hasCachedCatalog: true,
            ),
          ),
          planningPlanListProvider.overrideWith(
            (ref) async => [_planSummaryFixture()],
          ),
          planningPlanDetailProvider(
            'plan-1',
          ).overrideWith((ref) async => _planDetailFixture()),
          songLibraryListProvider.overrideWith(
            (ref) async => [
              _songSummaryFixture('song-1'),
              _songSummaryFixture('song-2'),
            ],
          ),
          songLibrarySongByIdProvider(
            'song-1',
          ).overrideWith((ref) async => _songSummaryFixture('song-1')),
          songLibrarySongByIdProvider(
            'song-2',
          ).overrideWith((ref) async => _songSummaryFixture('song-2')),
          songLibraryReaderProvider.overrideWithProvider(
            (songId) => FutureProvider.autoDispose(
              (ref) async => _songResultFor(songId),
            ),
          ),
        ],
        child: LyronApp(router: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repeated Song'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pumpAndSettle();

    expect(find.text('Second Song'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Second Song'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.previousSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Repeated Song'), findsWidgets);
  });

  testWidgets(
    'returning from the scoped reader keeps the previously opened item visible in plan detail',
    (tester) async {
      final repository = _StaticAuthRepository(
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
        initialLocation: '/plans/plan-1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWithValue(controller),
            appAuthListenableProvider.overrideWithValue(controller),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            planningPlanListProvider.overrideWith(
              (ref) async => [_planSummaryFixture()],
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) async => _longPlanDetailFixture()),
            songLibraryListProvider.overrideWith(
              (ref) async => [
                for (final index in List<int>.generate(30, (i) => i + 1))
                  _songSummaryFixture('song-$index'),
              ],
            ),
            songLibrarySongByIdProvider(
              'song-25',
            ).overrideWith((ref) async => _songSummaryFixture('song-25')),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => _songResultFor(songId),
              ),
            ),
          ],
          child: LyronApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      final item25 = find.byKey(const ValueKey('plan-session-item-item-25'));
      await tester.ensureVisible(item25);
      await tester.pumpAndSettle();
      await tester.tap(item25, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Repeated Song 25'), findsWidgets);

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text('25. Repeated Song 25'), findsOneWidget);
    },
  );

  testWidgets(
    'session-scoped direct entry shows a tombstone when the canonical song is gone',
    (tester) async {
      final repository = _StaticAuthRepository(
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
            '/plans/plan-1/sessions/session-1/items/songs/repeated-song',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWithValue(controller),
            appAuthListenableProvider.overrideWithValue(controller),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            planningPlanListProvider.overrideWith(
              (ref) async => [_planSummaryFixture()],
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) async => _planDetailFixture()),
            songLibraryListProvider.overrideWith((ref) async => const []),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => throw const SongNotFoundException('song-1'),
              ),
            ),
          ],
          child: LyronApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Repeated Song'), findsWidgets);
      expect(find.text(AppStrings.routeNotFoundMessage), findsNothing);
    },
  );
}

class _StaticAuthRepository implements AuthRepository {
  _StaticAuthRepository({this.restoredSession});

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

PlanSummary _planSummaryFixture() {
  return PlanSummary(
    id: 'plan-1',
    name: 'Sunday Morning',
    description: 'Single-session Sunday fixture',
    scheduledFor: DateTime(2026, 4, 5, 8, 30),
    updatedAt: DateTime(2026, 3, 31, 8),
  );
}

PlanDetail _planDetailFixture() {
  return PlanDetail(
    plan: _planSummaryFixture(),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        name: 'Main Set',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-1',
            position: 10,
            song: SongSummary(
              id: 'song-1',
              slug: 'repeated-song',
              title: 'Repeated Song',
            ),
          ),
          SessionItemSummary(
            id: 'item-2',
            position: 20,
            song: SongSummary(
              id: 'song-2',
              slug: 'second-song',
              title: 'Second Song',
            ),
          ),
        ],
      ),
    ],
  );
}

SongReaderResult _songResultFor(String songId) {
  final title = switch (songId) {
    'song-2' => 'Second Song',
    'song-25' => 'Repeated Song 25',
    _ => 'Repeated Song',
  };

  return SongReaderResult(
    song: ParsedSong(
      title: title,
      sourceKey: 'C',
      sections: const [],
      diagnostics: const [],
    ),
  );
}

SongSummary _songSummaryFixture(String songId) {
  final (slug, title) = switch (songId) {
    'song-2' => ('second-song', 'Second Song'),
    'song-25' => ('repeated-song-25', 'Repeated Song 25'),
    _ => ('repeated-song', 'Repeated Song'),
  };

  return SongSummary(id: songId, slug: slug, title: title);
}

PlanDetail _longPlanDetailFixture() {
  return PlanDetail(
    plan: _planSummaryFixture(),
    sessions: [
      SessionSummary(
        id: 'session-1',
        name: 'Main Set',
        position: 10,
        items: List.generate(
          30,
          (index) => SessionItemSummary(
            id: 'item-${index + 1}',
            position: index + 1,
            song: SongSummary(
              id: 'song-${index + 1}',
              slug: index + 1 == 25
                  ? 'repeated-song-25'
                  : 'repeated-song-${index + 1}',
              title: 'Repeated Song ${index + 1}',
            ),
          ),
          growable: false,
        ),
      ),
    ],
  );
}
