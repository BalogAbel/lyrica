import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_summary.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyrica_app/src/presentation/planning/planning_providers.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const songId = 'reader_song';

  SongReaderResult buildResult({List<ParseDiagnostic> diagnostics = const []}) {
    return SongReaderResult(
      song: ParsedSong(
        title: 'Reader Song',
        subtitle: 'Live version',
        sourceKey: 'G',
        sections: [
          SongSection(
            kind: SongSectionKind.verse,
            label: 'Verse',
            number: 1,
            lines: [
              SongLine(
                segments: [
                  const LyricSegment(leadingChord: 'F#m', text: 'Hello'),
                  const LyricSegment(text: ' world'),
                ],
              ),
            ],
          ),
          SongSection(
            kind: SongSectionKind.chorus,
            label: 'Chorus',
            number: 2,
            lines: [
              SongLine(
                segments: [
                  const LyricSegment(leadingChord: 'A', text: 'Sing'),
                  const LyricSegment(text: ' along'),
                ],
              ),
            ],
          ),
        ],
        diagnostics: diagnostics,
      ),
    );
  }

  SongReaderResult buildScopedResult(String title) {
    return SongReaderResult(
      song: ParsedSong(
        title: title,
        sourceKey: 'G',
        sections: [
          SongSection(
            kind: SongSectionKind.verse,
            label: 'Verse',
            number: 1,
            lines: [
              SongLine(
                segments: [
                  const LyricSegment(leadingChord: 'F#m', text: 'Hello'),
                ],
              ),
            ],
          ),
        ],
        diagnostics: const [],
      ),
    );
  }

  Widget buildApp({
    required SongReaderResult result,
    CatalogSnapshotState catalogState = const CatalogSnapshotState(
      context: null,
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    ),
  }) {
    return ProviderScope(
      overrides: [
        catalogSnapshotStateProvider.overrideWithValue(catalogState),
        songLibraryReaderProvider.overrideWithProvider(
          (value) => FutureProvider.autoDispose((ref) async => result),
        ),
      ],
      child: const MaterialApp(home: SongReaderScreen(songId: songId)),
    );
  }

  Widget buildRoutedApp({
    required SongReaderResult result,
    String initialLocation = '/songs/$songId',
    CatalogSnapshotState catalogState = const CatalogSnapshotState(
      context: null,
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    ),
  }) {
    GoRouter.optionURLReflectsImperativeAPIs = true;

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
        GoRoute(
          path: '/songs/:songId',
          builder: (context, state) =>
              SongReaderScreen(songId: state.pathParameters['songId']!),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        catalogSnapshotStateProvider.overrideWithValue(catalogState),
        songLibraryListProvider.overrideWith(
          (ref) async => const [SongSummary(id: songId, title: 'Reader Song')],
        ),
        songLibraryReaderProvider.overrideWithProvider(
          (value) => FutureProvider.autoDispose((ref) async => result),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Widget buildScopedReaderApp({
    required PlanDetail planDetail,
    required Map<String, SongReaderResult> resultsBySongId,
    String initialLocation =
        '/plans/plan-1/sessions/session-1/items/item-20/songs/song-2',
    Object? planningError,
  }) {
    GoRouter.optionURLReflectsImperativeAPIs = true;

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: AppRoutes.planDetail.path,
          builder: (context, state) =>
              PlanDetailScreen(planId: state.pathParameters['planId']!),
        ),
        GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
        GoRoute(
          path: AppRoutes.planSessionSongReader.path,
          builder: (context, state) => SongReaderScreen(
            songId: state.pathParameters['songId']!,
            planId: state.pathParameters['planId']!,
            sessionId: state.pathParameters['sessionId']!,
            sessionItemId: state.pathParameters['sessionItemId']!,
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        catalogSnapshotStateProvider.overrideWithValue(
          const CatalogSnapshotState(
            context: null,
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
        ),
        planningPlanDetailProvider(planDetail.plan.id).overrideWith((ref) {
          if (planningError != null) {
            return Future<PlanDetail>.error(planningError);
          }

          return Future.value(planDetail);
        }),
        songLibraryReaderProvider.overrideWithProvider(
          (songId) => FutureProvider.autoDispose(
            (ref) async => resultsBySongId[songId]!,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Widget buildErrorApp({
    required Future<SongReaderResult> Function() loadSong,
    CatalogSnapshotState catalogState = const CatalogSnapshotState(
      context: null,
      connectionStatus: CatalogConnectionStatus.online,
      refreshStatus: CatalogRefreshStatus.idle,
      sessionStatus: CatalogSessionStatus.verified,
      hasCachedCatalog: true,
    ),
  }) {
    return ProviderScope(
      overrides: [
        catalogSnapshotStateProvider.overrideWithValue(catalogState),
        songLibraryReaderProvider.overrideWithProvider(
          (value) => FutureProvider.autoDispose((ref) => loadSong()),
        ),
      ],
      child: const MaterialApp(home: SongReaderScreen(songId: songId)),
    );
  }

  testWidgets('shows metadata, sections, and controls by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCatalogOnlineStatus), findsOneWidget);
    expect(find.text('Reader Song'), findsOneWidget);
    expect(find.text('Live version'), findsOneWidget);
    expect(find.text('Key: G'), findsOneWidget);
    expect(find.text('Verse 1'), findsOneWidget);
    expect(find.text('Chorus 2'), findsOneWidget);
    expect(find.text('F#m'), findsOneWidget);
  });

  testWidgets(
    'shows a visible back affordance while keeping catalog status visible',
    (tester) async {
      await tester.pumpWidget(buildApp(result: buildResult()));
      await tester.pumpAndSettle();

      expect(find.byTooltip(AppStrings.songReaderBackAction), findsOneWidget);
      expect(find.text(AppStrings.songCatalogOnlineStatus), findsOneWidget);
    },
  );

  testWidgets('hides chords in lyrics only mode', (tester) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lyrics only'));
    await tester.pumpAndSettle();

    expect(find.text('F#m'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('transposes rendered chords when controls change', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();

    expect(find.text('Gm'), findsOneWidget);
    expect(find.text('F#m'), findsNothing);
  });

  testWidgets('updates shared font size when controls change', (tester) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    final initialText = tester.widget<Text>(find.text('Hello'));
    final initialSize = initialText.style!.fontSize!;

    await tester.tap(find.text('A+'));
    await tester.pumpAndSettle();

    final scaledText = tester.widget<Text>(find.text('Hello'));
    final scaledSize = scaledText.style!.fontSize!;

    expect(scaledSize, greaterThan(initialSize));
  });

  testWidgets(
    'shows a non-blocking warning surface for recoverable diagnostics',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          result: buildResult(
            diagnostics: [
              ParseDiagnostic(
                severity: ParseDiagnosticSeverity.warning,
                message: 'Unknown directive',
                line: const ParseDiagnosticLineMetadata(lineNumber: 3),
                context: 'unknown:token',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('warning'), findsWidgets);
    },
  );

  testWidgets('counts only warning diagnostics in the warning surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        result: buildResult(
          diagnostics: [
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.info,
              message: 'Normalized spacing',
              line: const ParseDiagnosticLineMetadata(lineNumber: 1),
            ),
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.warning,
              message: 'Unknown directive',
              line: const ParseDiagnosticLineMetadata(lineNumber: 3),
              context: 'unknown:token',
            ),
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.error,
              message: 'Invalid token',
              line: const ParseDiagnosticLineMetadata(lineNumber: 5),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('1 recoverable warning while reading this song.'),
      findsOneWidget,
    );
    expect(
      find.text('3 recoverable warnings while reading this song.'),
      findsNothing,
    );
  });

  testWidgets('shows an unavailable state when the song cannot be found', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildErrorApp(
        loadSong: () async => throw const SongNotFoundException(songId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This song is unavailable.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets(
    'shows offline and refresh-failed catalog status while reading from cache',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          result: buildResult(),
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
    },
  );

  testWidgets(
    'keeps showing a loading state while the authenticated catalog context is still resolving',
    (tester) async {
      await tester.pumpWidget(
        buildErrorApp(
          loadSong: () async => throw SongNotFoundException(songId),
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

      expect(find.text(AppStrings.songReaderLoadingMessage), findsOneWidget);
      expect(find.text(AppStrings.songReaderUnavailableMessage), findsNothing);
    },
  );

  testWidgets(
    'shows an access denied state when backend scope blocks the song',
    (tester) async {
      await tester.pumpWidget(
        buildErrorApp(
          loadSong: () async => throw const SongAccessDeniedException(songId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have access to this song.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets('shows a retryable backend failure state when loading fails', (
    tester,
  ) async {
    var attempts = 0;

    await tester.pumpWidget(
      buildErrorApp(
        loadSong: () async {
          attempts += 1;
          if (attempts == 1) {
            throw Exception('backend unavailable');
          }

          return buildResult();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load song. Please try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Reader Song'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets(
    'handles system back by returning to the song list when opened directly',
    (tester) async {
      await tester.pumpWidget(buildRoutedApp(result: buildResult()));
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text('Reader Song'), findsOneWidget);
      expect(find.text('Song reader'), findsNothing);
    },
  );

  testWidgets('scoped reader entry shows previous and next controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScopedReaderApp(
        planDetail: _multiItemPlanDetail(),
        resultsBySongId: {
          'song-1': buildScopedResult('Song One'),
          'song-2': buildScopedResult('Song Two'),
          'song-3': buildScopedResult('Song Three'),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.scopedReaderPreviousAction), findsOneWidget);
    expect(find.text(AppStrings.scopedReaderNextAction), findsOneWidget);
  });

  testWidgets('standard reader entry hides scoped navigation controls', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.scopedReaderPreviousAction), findsNothing);
    expect(find.text(AppStrings.scopedReaderNextAction), findsNothing);
  });

  testWidgets('first and last items disable navigation at session boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScopedReaderApp(
        planDetail: _multiItemPlanDetail(),
        resultsBySongId: {
          'song-1': buildScopedResult('Song One'),
          'song-2': buildScopedResult('Song Two'),
          'song-3': buildScopedResult('Song Three'),
        },
        initialLocation:
            '/plans/plan-1/sessions/session-1/items/item-10/songs/song-1',
      ),
    );
    await tester.pumpAndSettle();

    final previousAtStart = tester.widget<OutlinedButton>(
      find.widgetWithText(
        OutlinedButton,
        AppStrings.scopedReaderPreviousAction,
      ),
    );
    final nextAtStart = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, AppStrings.scopedReaderNextAction),
    );
    expect(previousAtStart.onPressed, isNull);
    expect(nextAtStart.onPressed, isNotNull);

    await tester.tap(find.text(AppStrings.scopedReaderNextAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.scopedReaderNextAction));
    await tester.pumpAndSettle();

    final previousAtEnd = tester.widget<OutlinedButton>(
      find.widgetWithText(
        OutlinedButton,
        AppStrings.scopedReaderPreviousAction,
      ),
    );
    final nextAtEnd = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, AppStrings.scopedReaderNextAction),
    );
    expect(previousAtEnd.onPressed, isNotNull);
    expect(nextAtEnd.onPressed, isNull);
  });

  testWidgets('single-item session disables both previous and next', (
    tester,
  ) async {
    final singleItemPlan = PlanDetail(
      plan: PlanSummary(
        id: 'plan-1',
        name: 'Plan Fixture',
        description: 'Scoped reader test fixture',
        scheduledFor: null,
        updatedAt: DateTime(2026, 4, 1, 9),
      ),
      sessions: const [
        SessionSummary(
          id: 'session-1',
          name: 'Main Set',
          position: 10,
          items: [
            SessionItemSummary(
              id: 'item-10',
              position: 10,
              song: SongSummary(id: 'song-1', title: 'Song One'),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      buildScopedReaderApp(
        planDetail: singleItemPlan,
        resultsBySongId: {'song-1': buildScopedResult('Song One')},
        initialLocation:
            '/plans/plan-1/sessions/session-1/items/item-10/songs/song-1',
      ),
    );
    await tester.pumpAndSettle();

    final previous = tester.widget<OutlinedButton>(
      find.widgetWithText(
        OutlinedButton,
        AppStrings.scopedReaderPreviousAction,
      ),
    );
    final next = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, AppStrings.scopedReaderNextAction),
    );
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets(
    'repeated next actions keep a single reader stack entry before returning to plan detail',
    (tester) async {
      await tester.pumpWidget(
        buildScopedReaderApp(
          planDetail: _multiItemPlanDetail(),
          resultsBySongId: {
            'song-1': buildScopedResult('Song One'),
            'song-2': buildScopedResult('Song Two'),
            'song-3': buildScopedResult('Song Three'),
          },
          initialLocation: '/plans/plan-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('20. Song Two'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.scopedReaderNextAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.scopedReaderPreviousAction));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.planDetailTitle), findsOneWidget);
      expect(find.text('Plan Fixture'), findsOneWidget);
    },
  );

  testWidgets(
    'scoped navigation preserves view mode, transpose, and shared font scale',
    (tester) async {
      await tester.pumpWidget(
        buildScopedReaderApp(
          planDetail: _multiItemPlanDetail(),
          resultsBySongId: {
            'song-1': buildScopedResult('Song One'),
            'song-2': buildScopedResult('Song Two'),
            'song-3': buildScopedResult('Song Three'),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lyrics only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A+'));
      await tester.pumpAndSettle();

      final resizedBeforeNavigation = tester.widget<Text>(find.text('Hello'));
      final fontSizeBeforeNavigation = resizedBeforeNavigation.style!.fontSize!;

      await tester.tap(find.text(AppStrings.scopedReaderNextAction));
      await tester.pumpAndSettle();

      final resizedAfterNavigation = tester.widget<Text>(find.text('Hello'));
      final fontSizeAfterNavigation = resizedAfterNavigation.style!.fontSize!;

      expect(find.text('F#m'), findsNothing);
      expect(find.text('Gm'), findsNothing);
      expect(fontSizeAfterNavigation, fontSizeBeforeNavigation);
    },
  );

  testWidgets('invalid scoped context shows explicit scoped error state', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScopedReaderApp(
        planDetail: _multiItemPlanDetail(),
        resultsBySongId: {'song-999': buildScopedResult('Wrong Song')},
        initialLocation:
            '/plans/plan-1/sessions/session-1/items/item-20/songs/song-999',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.scopedReaderContextUnavailableMessage),
      findsOneWidget,
    );
    expect(find.text('Wrong Song'), findsNothing);
    expect(find.text(AppStrings.scopedReaderPreviousAction), findsNothing);
    expect(find.text(AppStrings.scopedReaderNextAction), findsNothing);
  });

  testWidgets(
    'scoped song-load failure shows the explicit scoped error instead of standard reader errors',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) async => _multiItemPlanDetail()),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => throw const SongNotFoundException('song-2'),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation:
                  '/plans/plan-1/sessions/session-1/items/item-20/songs/song-2',
              routes: [
                GoRoute(
                  path: AppRoutes.planDetail.path,
                  builder: (context, state) =>
                      PlanDetailScreen(planId: state.pathParameters['planId']!),
                ),
                GoRoute(
                  path: AppRoutes.planSessionSongReader.path,
                  builder: (context, state) => SongReaderScreen(
                    songId: state.pathParameters['songId']!,
                    planId: state.pathParameters['planId']!,
                    sessionId: state.pathParameters['sessionId']!,
                    sessionItemId: state.pathParameters['sessionItemId']!,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.scopedReaderContextUnavailableMessage),
        findsOneWidget,
      );
      expect(find.text(AppStrings.songReaderUnavailableMessage), findsNothing);
      expect(find.text(AppStrings.songReaderAccessDeniedMessage), findsNothing);
      expect(find.text(AppStrings.scopedReaderPreviousAction), findsNothing);
      expect(find.text(AppStrings.scopedReaderNextAction), findsNothing);
    },
  );

  testWidgets(
    'scoped reader keeps the route and shows an explicit error when planning context is unavailable',
    (tester) async {
      final router = GoRouter(
        initialLocation:
            '/plans/plan-1/sessions/session-1/items/item-20/songs/song-2',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const SongListScreen(),
          ),
          GoRoute(
            path: AppRoutes.planDetail.path,
            builder: (context, state) =>
                PlanDetailScreen(planId: state.pathParameters['planId']!),
          ),
          GoRoute(
            path: AppRoutes.planSessionSongReader.path,
            builder: (context, state) => SongReaderScreen(
              songId: state.pathParameters['songId']!,
              planId: state.pathParameters['planId']!,
              sessionId: state.pathParameters['sessionId']!,
              sessionItemId: state.pathParameters['sessionItemId']!,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            planningPlanDetailProvider('plan-1').overrideWith(
              (ref) => Future<PlanDetail>.error(Exception('unavailable')),
            ),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => buildScopedResult('Song Two'),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.scopedReaderContextUnavailableMessage),
        findsOneWidget,
      );
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        contains('/plans/plan-1/sessions/session-1/items/item-20/songs/song-2'),
      );
    },
  );

  testWidgets(
    'direct scoped entry falls back to canonical plan detail on back',
    (tester) async {
      await tester.pumpWidget(
        buildScopedReaderApp(
          planDetail: _multiItemPlanDetail(),
          resultsBySongId: {
            'song-1': buildScopedResult('Song One'),
            'song-2': buildScopedResult('Song Two'),
            'song-3': buildScopedResult('Song Three'),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.planDetailTitle), findsOneWidget);
      expect(find.text('Plan Fixture'), findsOneWidget);
    },
  );
}

PlanDetail _multiItemPlanDetail() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      name: 'Plan Fixture',
      description: 'Scoped reader test fixture',
      scheduledFor: null,
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        name: 'Main Set',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-10',
            position: 10,
            song: SongSummary(id: 'song-1', title: 'Song One'),
          ),
          SessionItemSummary(
            id: 'item-20',
            position: 20,
            song: SongSummary(id: 'song-2', title: 'Song Two'),
          ),
          SessionItemSummary(
            id: 'item-30',
            position: 30,
            song: SongSummary(id: 'song-3', title: 'Song Three'),
          ),
        ],
      ),
    ],
  );
}
