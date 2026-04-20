import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';
import 'package:lyron_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();
  setUp(() async {
    await closeSharedDatabases();
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({
    List<SongSummary> songs = const [],
    CatalogSnapshotState? initialCatalogState,
    StateProvider<CatalogSnapshotState>? mutableCatalogStateProvider,
    Completer<List<SongSummary>>? loadingCompleter,
    Future<List<SongSummary>> Function()? listSongs,
    FutureOr<List<SongSummary>> Function(ActiveCatalogContext? context)?
    songsForContext,
    SongCatalogController? catalogController,
    PlanningSyncController? planningSyncController,
    SongLibraryService? songLibraryService,
    SongMutationSyncController? songMutationSyncController,
    List<SongMutationRecord>? mutationEntries,
    Future<List<SongMutationRecord>> Function()? loadMutationEntries,
    FutureOr<List<SongMutationRecord>> Function(ActiveCatalogContext? context)?
    mutationEntriesForContext,
    bool? hasUnsyncedChanges,
    bool? hasUnsyncedPlanningMutations,
    CatalogSnapshotState catalogState = const CatalogSnapshotState(
      context: null,
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    ),
  }) {
    final effectiveCatalogState = initialCatalogState ?? catalogState;
    final authRepository = _TestAuthRepository();
    final authController = AppAuthController(authRepository);
    addTearDown(authController.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
        GoRoute(
          path: AppRoutes.planList.path,
          builder: (context, state) =>
              const Material(child: Text('plans:list')),
        ),
        GoRoute(
          path: '/songs/:songSlug',
          builder: (context, state) {
            final songSlug = state.pathParameters['songSlug']!;
            return Material(child: Text('reader:$songSlug'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    return isolatedSongCatalogProviderScope(
      overrides: [
        appAuthControllerProvider.overrideWithValue(authController),
        appAuthListenableProvider.overrideWithValue(authController),
        if (catalogController != null)
          songCatalogControllerProvider.overrideWith(
            (ref) => catalogController,
          ),
        if (planningSyncController != null)
          planningSyncControllerProvider.overrideWith(
            (ref) => planningSyncController,
          ),
        if (songLibraryService != null)
          songLibraryServiceProvider.overrideWithValue(songLibraryService),
        if (songMutationSyncController != null)
          songMutationSyncControllerProvider.overrideWithValue(
            songMutationSyncController,
          ),
        if (loadMutationEntries != null)
          songMutationEntriesProvider.overrideWith(
            (ref) => loadMutationEntries(),
          ),
        if (mutationEntriesForContext != null)
          songMutationEntriesProvider.overrideWith((ref) async {
            final entries = mutationEntriesForContext(
              ref.watch(activeCatalogContextProvider),
            );
            if (entries is Future<List<SongMutationRecord>>) {
              return entries;
            }
            return entries;
          }),
        if (mutationEntries != null)
          songMutationEntriesProvider.overrideWith(
            (ref) async => mutationEntries,
          ),
        if (hasUnsyncedChanges != null)
          hasUnsyncedSongMutationsProvider.overrideWith(
            (ref) async => hasUnsyncedChanges,
          ),
        if (hasUnsyncedPlanningMutations != null)
          hasUnsyncedPlanningMutationsProvider.overrideWith(
            (ref) async => hasUnsyncedPlanningMutations,
          ),
        if (mutableCatalogStateProvider != null)
          catalogSnapshotStateProvider.overrideWith(
            (ref) => ref.watch(mutableCatalogStateProvider),
          )
        else
          catalogSnapshotStateProvider.overrideWithValue(effectiveCatalogState),
        if (mutableCatalogStateProvider != null)
          activeCatalogContextProvider.overrideWith(
            (ref) => ref.watch(mutableCatalogStateProvider).context,
          )
        else
          activeCatalogContextProvider.overrideWithValue(
            effectiveCatalogState.context,
          ),
        songLibraryListProvider.overrideWith((ref) {
          if (songsForContext != null) {
            final songs = songsForContext(
              ref.watch(activeCatalogContextProvider),
            );
            if (songs is Future<List<SongSummary>>) {
              return songs;
            }
            return Future.value(songs);
          }

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
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
          SongSummary(
            id: 'felkel_a_nap',
            slug: 'felkel-a-nap',
            title: 'Felkel a nap',
          ),
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
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Egy út'));
    await tester.pumpAndSettle();

    expect(find.text('reader:egy-ut'), findsOneWidget);
  });

  testWidgets('returns to the song list after opening a song from the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Egy út'));
    await tester.pumpAndSettle();

    expect(find.text('reader:egy-ut'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('reader:egy-ut'), findsNothing);
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
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
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

  testWidgets('shows a visible refresh action alongside sign out', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(AppStrings.songCatalogRefreshAction), findsOneWidget);
    expect(find.text(AppStrings.songCreateAction), findsOneWidget);
    expect(find.text(AppStrings.planningEntryAction), findsOneWidget);
    expect(find.text(AppStrings.signOutAction), findsOneWidget);
  });

  testWidgets('search narrows titles and shows explicit no-results copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(
            id: 'song-1',
            slug: 'amazing-grace',
            title: 'Amazing Grace',
          ),
          SongSummary(
            id: 'song-2',
            slug: 'great-is-thy-faithfulness',
            title: 'Great Is Thy Faithfulness',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('song-list-search-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('song-list-search-field')),
      '  grace  ',
    );
    await tester.pumpAndSettle();

    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Great Is Thy Faithfulness'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('song-list-search-field')),
      'zzz',
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songListNoResultsMessage), findsOneWidget);
    expect(find.text('Amazing Grace'), findsNothing);
  });

  testWidgets('shows loading while mutation entries resolve', (tester) async {
    final mutationEntriesCompleter = Completer<List<SongMutationRecord>>();

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        loadMutationEntries: () => mutationEntriesCompleter.future,
      ),
    );
    await tester.pump();

    expect(
      find.text(AppStrings.songListMutationStatusLoadingMessage),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text(AppStrings.songListNoResultsMessage), findsNothing);
  });

  testWidgets(
    'preserves cached songs while active catalog switches and list reloads',
    (tester) async {
      final catalogStateProvider = StateProvider<CatalogSnapshotState>(
        (ref) => const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      );
      final org2SongsCompleter = Completer<List<SongSummary>>();

      await tester.pumpWidget(
        buildApp(
          mutableCatalogStateProvider: catalogStateProvider,
          songsForContext: (context) {
            return switch (context?.organizationId) {
              'org-1' => const [
                SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
                SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
              ],
              _ => org2SongsCompleter.future,
            };
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SongListScreen)),
      );
      container
          .read(catalogStateProvider.notifier)
          .state = const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      );
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text(AppStrings.songListLoadingMessage), findsNothing);

      org2SongsCompleter.complete(const []);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.songListEmptyMessage), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsNothing);
    },
  );

  testWidgets('keeps cached songs visible when refresh later fails', (
    tester,
  ) async {
    final catalogStateProvider = StateProvider<CatalogSnapshotState>(
      (ref) => CatalogSnapshotState(
        context: const ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      ),
    );
    FutureOr<List<SongSummary>> Function(ActiveCatalogContext?) songsLoader =
        (_) => const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ];

    await tester.pumpWidget(
      buildApp(
        mutableCatalogStateProvider: catalogStateProvider,
        songsForContext: (context) => songsLoader(context),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SongListScreen)),
    );

    songsLoader = (_) => Future<List<SongSummary>>.error(StateError('boom'));
    container.invalidate(songLibraryListProvider);
    container.read(catalogStateProvider.notifier).state = container
        .read(catalogStateProvider)
        .copyWith(refreshStatus: CatalogRefreshStatus.failed);
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      find.text(AppStrings.songCatalogRefreshFailedStatus),
      findsOneWidget,
    );
    expect(find.text(AppStrings.songListLoadFailureMessage), findsNothing);
  });

  testWidgets('shows a narrow warning when mutation entries fail', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        loadMutationEntries: () =>
            Future<List<SongMutationRecord>>.error(StateError('boom')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.songListMutationStatusFailedMessage),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('clears cached mutation entries when active catalog changes', (
    tester,
  ) async {
    final catalogStateProvider = StateProvider<CatalogSnapshotState>(
      (ref) => const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      ),
    );
    final org2MutationEntriesCompleter = Completer<List<SongMutationRecord>>();

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        mutableCatalogStateProvider: catalogStateProvider,
        mutationEntriesForContext: (context) {
          return switch (context?.organizationId) {
            'org-1' => [
              const SongMutationRecord(
                id: 'song-1',
                organizationId: 'org-1',
                slug: 'alpha',
                title: 'Alpha',
                chordproSource: '{title: Alpha}',
                version: 2,
                baseVersion: 1,
                syncStatus: SongSyncStatus.pendingUpdate,
              ),
            ],
            _ => org2MutationEntriesCompleter.future,
          };
        },
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SongListScreen)),
    );
    Finder rowText(String text) => find.descendant(
      of: find.byKey(const ValueKey('song-library-results-list')),
      matching: find.text(text),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('song-list-filter-control')),
        matching: find.text('Pending sync'),
      ),
    );
    await tester.pumpAndSettle();

    expect(rowText('Alpha'), findsOneWidget);
    expect(rowText('Beta'), findsNothing);

    container
        .read(catalogStateProvider.notifier)
        .state = const CatalogSnapshotState(
      context: ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2'),
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('song-list-filter-control')),
        matching: find.text('Pending sync'),
      ),
    );
    await tester.pump();

    expect(rowText('Alpha'), findsNothing);
    expect(
      find.text(AppStrings.songListMutationStatusLoadingMessage),
      findsOneWidget,
    );

    org2MutationEntriesCompleter.complete(const []);
    await tester.pumpAndSettle();

    expect(rowText('Alpha'), findsNothing);
    expect(find.text(AppStrings.songListNoResultsMessage), findsOneWidget);
  });

  testWidgets('filter controls narrow songs by local mutation status', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
          SongSummary(id: 'song-4', slug: 'delta', title: 'Delta'),
          SongSummary(id: 'song-5', slug: 'coda', title: 'Coda'),
        ],
        mutationEntries: const [
          SongMutationRecord(
            id: 'song-2',
            organizationId: 'org-1',
            slug: 'beta',
            title: 'Beta',
            chordproSource: '{title: Beta}',
            version: 2,
            baseVersion: 1,
            syncStatus: SongSyncStatus.pendingUpdate,
          ),
          SongMutationRecord(
            id: 'song-3',
            organizationId: 'org-1',
            slug: 'gamma',
            title: 'Gamma',
            chordproSource: '{title: Gamma}',
            version: 3,
            baseVersion: 2,
            syncStatus: SongSyncStatus.conflict,
          ),
          SongMutationRecord(
            id: 'song-4',
            organizationId: 'org-1',
            slug: 'delta',
            title: 'Delta',
            chordproSource: '{title: Delta}',
            version: 4,
            baseVersion: null,
            syncStatus: SongSyncStatus.pendingCreate,
          ),
          SongMutationRecord(
            id: 'song-5',
            organizationId: 'org-1',
            slug: 'coda',
            title: 'Coda',
            chordproSource: '{title: Coda}',
            version: 5,
            baseVersion: 4,
            syncStatus: SongSyncStatus.pendingDelete,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    Finder rowText(String text) => find.descendant(
      of: find.byKey(const ValueKey('song-library-results-list')),
      matching: find.text(text),
    );

    expect(rowText('Alpha'), findsOneWidget);
    expect(rowText('Beta'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Pending sync'), findsOneWidget);
    expect(find.text('Conflicts'), findsOneWidget);

    Future<void> tapFilterLabel(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('song-list-filter-control')),
          matching: find.text(label),
        ),
      );
    }

    await tapFilterLabel('Pending sync');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<SongLibraryBrowseFilter>>(
            find.byKey(const ValueKey('song-list-filter-control')),
          )
          .selected,
      {SongLibraryBrowseFilter.pendingSync},
    );

    expect(rowText('Alpha'), findsNothing);
    expect(rowText('Beta'), findsOneWidget);
    expect(rowText('Gamma'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('song-library-results-list')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(rowText('Delta'), findsOneWidget);
    expect(rowText('Coda'), findsOneWidget);

    await tapFilterLabel('Conflicts');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<SongLibraryBrowseFilter>>(
            find.byKey(const ValueKey('song-list-filter-control')),
          )
          .selected,
      {SongLibraryBrowseFilter.conflicts},
    );

    expect(rowText('Alpha'), findsNothing);
    expect(rowText('Beta'), findsNothing);
    expect(rowText('Gamma'), findsOneWidget);

    await tapFilterLabel('All');
    await tester.pumpAndSettle();

    expect(rowText('Alpha'), findsOneWidget);
    expect(rowText('Beta'), findsOneWidget);
  });

  testWidgets('search state survives reader navigation and back navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(
            id: 'song-1',
            slug: 'amazing-grace',
            title: 'Amazing Grace',
          ),
          SongSummary(
            id: 'song-2',
            slug: 'great-is-thy-faithfulness',
            title: 'Great Is Thy Faithfulness',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('song-list-search-field')),
      'grace',
    );
    await tester.pumpAndSettle();

    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Great Is Thy Faithfulness'), findsNothing);

    await tester.tap(find.text('Amazing Grace'));
    await tester.pumpAndSettle();

    expect(find.text('reader:amazing-grace'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('song-list-search-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('song-list-search-field')),
          )
          .controller
          ?.text,
      'grace',
    );
    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Great Is Thy Faithfulness'), findsNothing);
  });

  testWidgets('search state resets when active catalog changes', (
    tester,
  ) async {
    final catalogStateProvider = StateProvider<CatalogSnapshotState>(
      (ref) => const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      ),
    );

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(
            id: 'song-1',
            slug: 'amazing-grace',
            title: 'Amazing Grace',
          ),
          SongSummary(
            id: 'song-2',
            slug: 'great-is-thy-faithfulness',
            title: 'Great Is Thy Faithfulness',
          ),
        ],
        mutableCatalogStateProvider: catalogStateProvider,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SongListScreen)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('song-list-search-field')),
      'grace',
    );
    await tester.pumpAndSettle();
    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Great Is Thy Faithfulness'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('song-list-filter-control')),
        matching: find.text('Pending sync'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<SongLibraryBrowseFilter>>(
            find.byKey(const ValueKey('song-list-filter-control')),
          )
          .selected,
      {SongLibraryBrowseFilter.pendingSync},
    );

    container
        .read(catalogStateProvider.notifier)
        .state = const CatalogSnapshotState(
      context: ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2'),
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('song-list-search-field')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<SegmentedButton<SongLibraryBrowseFilter>>(
            find.byKey(const ValueKey('song-list-filter-control')),
          )
          .selected,
      {SongLibraryBrowseFilter.all},
    );
    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Great Is Thy Faithfulness'), findsOneWidget);
  });

  testWidgets('search state resets when signing out', (tester) async {
    final catalogStateProvider = StateProvider<CatalogSnapshotState>(
      (ref) => const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      ),
    );

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(
            id: 'song-1',
            slug: 'amazing-grace',
            title: 'Amazing Grace',
          ),
          SongSummary(
            id: 'song-2',
            slug: 'great-is-thy-faithfulness',
            title: 'Great Is Thy Faithfulness',
          ),
        ],
        mutableCatalogStateProvider: catalogStateProvider,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SongListScreen)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('song-list-search-field')),
      'grace',
    );
    await tester.pumpAndSettle();
    expect(find.text('Amazing Grace'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('song-list-filter-control')),
        matching: find.text('Pending sync'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<SongLibraryBrowseFilter>>(
            find.byKey(const ValueKey('song-list-filter-control')),
          )
          .selected,
      {SongLibraryBrowseFilter.pendingSync},
    );

    container
        .read(catalogStateProvider.notifier)
        .state = const CatalogSnapshotState(
      context: null,
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: false,
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('song-list-search-field')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<SegmentedButton<SongLibraryBrowseFilter>>(
            find.byKey(const ValueKey('song-list-filter-control')),
          )
          .selected,
      {SongLibraryBrowseFilter.all},
    );
  });

  testWidgets('shows a warning before sign out when unsynced changes exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        hasUnsyncedChanges: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);
    expect(find.text(AppStrings.unsyncedSignOutMessage), findsOneWidget);
  });

  testWidgets(
    'shows a warning before sign out when planning mutations are unsynced',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          songs: const [
            SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
          ],
          hasUnsyncedChanges: false,
          hasUnsyncedPlanningMutations: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.signOutAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);
      expect(find.text(AppStrings.unsyncedSignOutMessage), findsOneWidget);
    },
  );

  testWidgets('sign out clears planning state before auth sign-out', (
    tester,
  ) async {
    final events = <String>[];
    final authRepository = _RecordingAuthRepository(events);
    final authController = AppAuthController(authRepository);
    addTearDown(authController.dispose);
    await authController.restoreSession();
    final songCatalogDatabase = SongCatalogDatabase.inMemory();
    addTearDown(() => songCatalogDatabase.close());
    final songCatalogController = _NoopSongCatalogController(
      songCatalogDatabase,
    );
    final planningSyncController = _RecordingPlanningSyncController(events);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      isolatedSongCatalogProviderScope(
        songCatalogDatabase: songCatalogDatabase,
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          appAuthListenableProvider.overrideWithValue(authController),
          songCatalogControllerProvider.overrideWith(
            (ref) => songCatalogController,
          ),
          planningSyncControllerProvider.overrideWith(
            (ref) => planningSyncController,
          ),
          hasUnsyncedSongMutationsProvider.overrideWith((ref) async => false),
          hasUnsyncedPlanningMutationsProvider.overrideWith(
            (ref) async => false,
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
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          songLibraryListProvider.overrideWith(
            (ref) async => const [
              SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();

    expect(events, ['planning-sign-out', 'auth-sign-out']);
  });

  testWidgets('create action opens the song editor and saves locally', (
    tester,
  ) async {
    final service = _RecordingSongLibraryService();

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        songLibraryService: service,
        catalogState: const CatalogSnapshotState(
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
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songCreateAction));
    await tester.pumpAndSettle();

    final titleField = find.byKey(const ValueKey('song-editor-title-field'));
    final sourceField = find.byKey(const ValueKey('song-editor-source-field'));
    expect(titleField, findsOneWidget);
    expect(sourceField, findsOneWidget);

    final sourceFieldWidget = tester.widget<TextField>(sourceField);
    expect(sourceFieldWidget.maxLines, isNull);

    await tester.enterText(titleField, 'New Song');
    await tester.enterText(sourceField, '{title: New Song}');
    await tester.tap(find.text(AppStrings.songSaveAction));
    await tester.pumpAndSettle();

    expect(service.createdTitle, 'New Song');
  });

  testWidgets('shows conflict actions for conflicted song mutations', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        mutationEntries: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'conflict-song',
            title: 'Conflict Song',
            chordproSource: '{title: Conflict Song}',
            version: 4,
            baseVersion: 3,
            syncStatus: SongSyncStatus.conflict,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conflict Song'), findsOneWidget);
    expect(find.text(AppStrings.songKeepMineAction), findsOneWidget);
    expect(find.text(AppStrings.songDiscardMineAction), findsOneWidget);
  });

  testWidgets('shows a surfaced error when keep mine fails', (tester) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        songMutationSyncController: _ThrowingSongMutationSyncController(
          const SongMutationSyncException(
            SongMutationSyncErrorCode.dependencyBlocked,
          ),
        ),
        mutationEntries: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'conflict-song',
            title: 'Conflict Song',
            chordproSource: '{title: Conflict Song}',
            version: 4,
            baseVersion: 3,
            syncStatus: SongSyncStatus.conflict,
            conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
          ),
        ],
        catalogState: const CatalogSnapshotState(
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
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songKeepMineAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songDeleteBlockedMessage), findsOneWidget);
  });

  testWidgets('shows raw error message when sync code is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        mutationEntries: const [
          SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'stuck-song',
            title: 'Stuck Song',
            chordproSource: '{title: Stuck Song}',
            version: 4,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingUpdate,
            errorCode: null,
            errorMessage: 'Stored plain sync error',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stored plain sync error'), findsOneWidget);
  });

  testWidgets('reloads conflict entries after keep mine failure', (
    tester,
  ) async {
    var loadCalls = 0;

    Future<List<SongMutationRecord>> loadEntries() async {
      loadCalls += 1;
      return [
        SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'conflict-song',
          title: 'Conflict Song',
          chordproSource: '{title: Conflict Song}',
          version: 4,
          baseVersion: 3,
          syncStatus: SongSyncStatus.conflict,
          conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
          errorCode: loadCalls > 1
              ? SongMutationSyncErrorCode.dependencyBlocked
              : null,
        ),
      ];
    }

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        songMutationSyncController: _ThrowingSongMutationSyncController(
          const SongMutationSyncException(
            SongMutationSyncErrorCode.dependencyBlocked,
          ),
        ),
        loadMutationEntries: loadEntries,
        catalogState: const CatalogSnapshotState(
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
    );
    await tester.pumpAndSettle();

    expect(loadCalls, 1);

    await tester.tap(find.text(AppStrings.songKeepMineAction));
    await tester.pumpAndSettle();

    expect(loadCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('navigates to the planning area from the song list', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.planningEntryAction));
    await tester.pumpAndSettle();

    expect(find.text('plans:list'), findsOneWidget);
  });

  testWidgets('tapping the refresh action triggers one catalog refresh', (
    tester,
  ) async {
    final database = SongCatalogDatabase.inMemory();
    final store = DriftSongCatalogStore(database);
    final remoteRepository = _CountingSongRepository();
    final controller = SongCatalogController(
      store: store,
      remoteRepository: remoteRepository,
      authSessionReader: () =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      organizationReader: () async => 'org-1',
      sessionVerifier: () async => CatalogSessionStatus.verified,
      foregroundState: _StaticForegroundState(isForeground: false),
    );
    addTearDown(database.close);

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        catalogController: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(AppStrings.songCatalogRefreshAction));
    await tester.pumpAndSettle();

    expect(remoteRepository.listSongsCalls, 1);
  });

  testWidgets('disables the refresh action while a refresh is in progress', (
    tester,
  ) async {
    final database = SongCatalogDatabase.inMemory();
    final store = DriftSongCatalogStore(database);
    final remoteRepository = _CountingSongRepository();
    final controller = SongCatalogController(
      store: store,
      remoteRepository: remoteRepository,
      authSessionReader: () =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      organizationReader: () async => 'org-1',
      sessionVerifier: () async => CatalogSessionStatus.verified,
      foregroundState: _StaticForegroundState(isForeground: false),
    );
    addTearDown(database.close);

    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        catalogController: controller,
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

    final refreshButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(refreshButton.onPressed, isNull);

    await tester.tap(find.byTooltip(AppStrings.songCatalogRefreshAction));
    await tester.pumpAndSettle();

    expect(remoteRepository.listSongsCalls, 0);
  });

  testWidgets('shows a persistent refreshing status surface', (tester) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
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

            return const [
              SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
            ];
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
    return const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local');
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

class _RecordingAuthRepository extends _TestAuthRepository {
  _RecordingAuthRepository(this.events);

  final List<String> events;

  @override
  Future<void> signOut() async {
    events.add('auth-sign-out');
  }
}

class _RecordingPlanningSyncController extends PlanningSyncController {
  _RecordingPlanningSyncController(this.events)
    : super(
        localStore: () => _NoopPlanningLocalStore(),
        remoteRepository: () => const _NoopPlanningRemoteRepository(),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      );

  final List<String> events;

  @override
  Future<void> handleExplicitSignOut() async {
    events.add('planning-sign-out');
  }
}

class _NoopSongCatalogController extends SongCatalogController {
  _NoopSongCatalogController(SongCatalogDatabase database)
    : super(
        store: DriftSongCatalogStore(database),
        remoteRepository: _CountingSongRepository(),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        foregroundState: const _StaticForegroundState(isForeground: false),
      );

  @override
  Future<void> handleExplicitSignOut() async {}
}

class _NoopPlanningRemoteRepository implements PlanningRemoteRefreshRepository {
  const _NoopPlanningRemoteRepository();

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    return const PlanningSyncPayload(plans: [], sessions: [], items: []);
  }
}

class _NoopPlanningLocalStore implements PlanningLocalStore {
  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async => false;

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) async => null;

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async => null;

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async => null;

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async => null;

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}
}

class _RecordingSongLibraryService extends SongLibraryService {
  _RecordingSongLibraryService()
    : super(_SongMutationTestRepository(), _SongMutationTestRepository());

  String? createdTitle;

  @override
  Future<SongMutationRecord> createSong({
    required ActiveCatalogContext context,
    required String title,
    required String chordproSource,
  }) async {
    createdTitle = title;
    return SongMutationRecord(
      id: 'created-song',
      organizationId: context.organizationId,
      slug: 'created-song',
      title: title,
      chordproSource: chordproSource,
      version: 1,
      baseVersion: null,
      syncStatus: SongSyncStatus.pendingCreate,
    );
  }
}

class _ThrowingSongMutationSyncController extends SongMutationSyncController {
  _ThrowingSongMutationSyncController(this._error)
    : super(
        store: _SongMutationTestRepository(),
        remoteRepository: _UnusedSongMutationRemoteRepository(),
      );

  final SongMutationSyncException _error;

  @override
  Future<void> keepMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    throw _error;
  }

  @override
  Future<void> discardMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    throw _error;
  }
}

class _SongMutationTestRepository
    implements SongCatalogReadRepository, SongMutationStore {
  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async => 'created-song';

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => const SongSource(id: 'song-1', source: '{title: Song}');

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => const SongSummary(id: 'song-1', title: 'Song');

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async => const SongSummary(id: 'song-1', title: 'Song');

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async => const [SongSummary(id: 'song-1', title: 'Song')];

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => null;

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {}

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) async {}

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}
}

class _CountingSongRepository implements SongRepository {
  int listSongsCalls = 0;

  @override
  Future<SongSource> getSongSource(String id) async {
    return SongSource(id: id, source: '{title: $id}');
  }

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    return const [
      SongSummary(
        id: 'song-1',
        slug: 'refreshed-song',
        title: 'Refreshed Song',
      ),
    ];
  }
}

class _UnusedSongMutationRemoteRepository
    implements SongMutationRemoteRepository {
  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();
}

class _StaticForegroundState implements AppForegroundState {
  const _StaticForegroundState({required this.isForeground});

  @override
  final bool isForeground;

  @override
  Stream<bool> watchForeground() => const Stream<bool>.empty();
}
