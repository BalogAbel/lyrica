import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/router/slug_route_resolvers.dart';

/// A catalog refresh emits a new `CatalogSnapshotState`, which reloads
/// `songLibraryListProvider` (and a failed reload can also error it). The
/// scoped reader route must keep the mounted reader while a previously loaded
/// value exists, because the reader State owns the temporary key layer: a
/// remount would silently drop the musician's temporary transpose/capo
/// (PS5 clears it only on a song change or on leaving the reader).
class _NoopPreferencesStore implements SongReaderPreferencesStore {
  @override
  Future<double?> readZoom({
    required String userId,
    required String songId,
  }) async => null;

  @override
  Future<void> writeZoom({
    required String userId,
    required String songId,
    required double zoom,
  }) async {}
}

class _Tick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _tickProvider = NotifierProvider<_Tick, int>(_Tick.new);

/// Makes one of the three route inputs fail on its next (re)load.
class _Fails extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final _songListFailsProvider = NotifierProvider<_Fails, bool>(_Fails.new);
final _planListFailsProvider = NotifierProvider<_Fails, bool>(_Fails.new);
final _planDetailFailsProvider = NotifierProvider<_Fails, bool>(_Fails.new);

PlanDetail _detail() => PlanDetail(
  plan: PlanSummary(
    id: 'plan-1',
    slug: 'plan-fixture',
    name: 'Plan',
    description: '',
    scheduledFor: null,
    updatedAt: DateTime(2026, 4, 1),
  ),
  sessions: const [
    SessionSummary(
      id: 'session-1',
      slug: 'main-set',
      name: 'Main',
      position: 10,
      items: [
        SessionItemSummary(
          id: 'item-10',
          position: 10,
          song: SongSummary(id: 'song-1', slug: 'song-one', title: 'Song One'),
        ),
      ],
    ),
  ],
);

String _text(WidgetTester tester, String key) {
  final keyed = tester.widget(find.byKey(Key(key)));
  if (keyed is Text) {
    return keyed.data!;
  }
  return tester
      .widget<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .data!;
}

Future<GoRouter> _pumpScopedReader(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation:
        '/plans/plan-fixture/sessions/main-set/items/songs/song-one',
    routes: [
      GoRoute(
        path: AppRoutes.planSessionSongReader.path,
        builder: (context, state) => PlanSessionSongSlugRouteResolver(
          planSlug: state.pathParameters['planSlug']!,
          sessionSlug: state.pathParameters['sessionSlug']!,
          songSlug: state.pathParameters['songSlug']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  final detail = _detail();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        songReaderPreferencesStoreProvider.overrideWith(
          (_) async => _NoopPreferencesStore(),
        ),
        // A catalog refresh flips the refresh status, so every tick emits a
        // genuinely different snapshot state (the state has no value equality).
        catalogSnapshotStateProvider.overrideWith((ref) {
          final tick = ref.watch(_tickProvider);
          return CatalogSnapshotState(
            context: const ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: tick.isOdd
                ? CatalogRefreshStatus.refreshing
                : CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          );
        }),
        activeCatalogContextProvider.overrideWithValue(null),
        activePlanningContextProvider.overrideWithValue(null),
        planningPlanListProvider.overrideWith((ref) async {
          final fails = ref.watch(_planListFailsProvider);
          if (fails) {
            throw StateError('plan list failed');
          }
          return [detail.plan];
        }),
        // Mirrors production: the list rebuilds with the catalog snapshot. The
        // delay keeps the reload visible to a frame.
        songLibraryListProvider.overrideWith((ref) async {
          ref.watch(catalogSnapshotStateProvider);
          final fails = ref.watch(_songListFailsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (fails) {
            throw StateError('catalog refresh failed');
          }
          return const [
            SongSummary(id: 'song-1', slug: 'song-one', title: 'Song One'),
          ];
        }),
        planningPlanDetailProvider('plan-1').overrideWith((ref) async {
          final fails = ref.watch(_planDetailFailsProvider);
          if (fails) {
            throw StateError('plan detail failed');
          }
          return detail;
        }),
        songLibraryReaderProvider.overrideWith(
          (ref, songId) async => SongReaderResult(
            song: ParsedSong(
              title: 'Song One',
              sourceKey: 'G',
              sections: const [],
              diagnostics: const [],
            ),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SongReaderScreen)));

void main() {
  testWidgets(
    'a catalog refresh keeps the scoped reader mounted with its temporary key',
    (tester) async {
      await _pumpScopedReader(tester);
      final before = tester.state(find.byType(SongReaderScreen));
      await tester.tap(find.byKey(const Key('song-reader-transpose-up')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'song-reader-transpose-value'), '+1');
      expect(_text(tester, 'song-reader-transpose-source'), 'Temporary');

      _container(tester).read(_tickProvider.notifier).bump();
      await tester.pump();
      expect(
        find.byType(SongReaderScreen),
        findsOneWidget,
        reason: 'the reload frame must not swap the reader for a scaffold',
      );
      await tester.pumpAndSettle();

      expect(
        identical(tester.state(find.byType(SongReaderScreen)), before),
        isTrue,
        reason: 'a remount would drop the reader-owned temporary key',
      );
      expect(_text(tester, 'song-reader-transpose-value'), '+1');
      expect(_text(tester, 'song-reader-transpose-source'), 'Temporary');
    },
  );

  for (final failure in <(String, NotifierProvider<_Fails, bool>)>[
    ('the song list', _songListFailsProvider),
    ('the plan list', _planListFailsProvider),
    ('the plan detail', _planDetailFailsProvider),
  ]) {
    testWidgets(
      'a failed reload of ${failure.$1} keeps the scoped reader and its '
      'temporary key',
      (tester) async {
        await _pumpScopedReader(tester);
        final before = tester.state(find.byType(SongReaderScreen));
        await tester.tap(find.byKey(const Key('song-reader-transpose-up')));
        await tester.pumpAndSettle();

        _container(tester).read(failure.$2.notifier).set(true);
        await tester.pumpAndSettle();

        expect(find.byType(SongReaderScreen), findsOneWidget);
        expect(
          identical(tester.state(find.byType(SongReaderScreen)), before),
          isTrue,
        );
        expect(_text(tester, 'song-reader-transpose-value'), '+1');
        expect(_text(tester, 'song-reader-transpose-source'), 'Temporary');
      },
    );
  }
}
