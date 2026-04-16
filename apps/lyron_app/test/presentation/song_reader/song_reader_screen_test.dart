import 'package:collection/collection.dart';
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
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_title_bar.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

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

  SongReaderResult buildTallResult() {
    return SongReaderResult(
      song: ParsedSong(
        title: 'Tall Reader Song',
        sourceKey: 'G',
        sections: [
          for (var sectionIndex = 1; sectionIndex <= 6; sectionIndex += 1)
            SongSection(
              kind: SongSectionKind.verse,
              label: 'Verse',
              number: sectionIndex,
              lines: [
                for (var lineIndex = 0; lineIndex < 3; lineIndex += 1)
                  SongLine(
                    segments: [
                      const LyricSegment(leadingChord: 'G', text: 'Line '),
                      LyricSegment(
                        text:
                            '$sectionIndex-$lineIndex long lyric long lyric long lyric',
                      ),
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
    SongLibraryService? songLibraryService,
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
        activeCatalogContextProvider.overrideWithValue(catalogState.context),
        if (songLibraryService != null)
          songLibraryServiceProvider.overrideWithValue(songLibraryService),
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
        activeCatalogContextProvider.overrideWithValue(catalogState.context),
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
        '/plans/plan-fixture/sessions/main-set/items/songs/song-two',
    Object? planningError,
  }) {
    GoRouter.optionURLReflectsImperativeAPIs = true;

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: AppRoutes.planDetail.path,
          builder: (context, state) => PlanDetailScreen(
            planId: _planIdForSlug(
              planDetail,
              state.pathParameters['planSlug']!,
            ),
          ),
        ),
        GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
        GoRoute(
          path: AppRoutes.planSessionSongReader.path,
          builder: (context, state) {
            final planSlug = state.pathParameters['planSlug']!;
            final sessionSlug = state.pathParameters['sessionSlug']!;
            final songSlug = state.pathParameters['songSlug']!;
            final sessionItemId = _sessionItemIdForScopedRoute(
              planDetail,
              sessionSlug: sessionSlug,
              songSlug: songSlug,
            );

            return SongReaderScreen(
              songId: _songIdForScopedRoute(
                planDetail,
                sessionSlug: sessionSlug,
                songSlug: songSlug,
              ),
              planId: _planIdForSlug(planDetail, planSlug),
              sessionId: _sessionIdForSlug(planDetail, sessionSlug),
              sessionItemId: sessionItemId,
              warmPlanDetail: planDetail,
            );
          },
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
        activeCatalogContextProvider.overrideWithValue(null),
        songLibraryListProvider.overrideWith((ref) async {
          return [
            for (final session in planDetail.sessions)
              for (final item in session.items) item.song,
          ];
        }),
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
        activeCatalogContextProvider.overrideWithValue(catalogState.context),
        songLibraryReaderProvider.overrideWithProvider(
          (value) => FutureProvider.autoDispose((ref) => loadSong()),
        ),
      ],
      child: const MaterialApp(home: SongReaderScreen(songId: songId)),
    );
  }

  Future<void> pumpWithViewport(
    WidgetTester tester, {
    required Size size,
    required Widget child,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
  }

  testWidgets('shows metadata, sections, and controls by default', (
    tester,
  ) async {
    await pumpWithViewport(
      tester,
      size: const Size(1440, 1200),
      child: buildApp(result: buildResult()),
    );

    expect(find.text('Reader Song'), findsWidgets);
    expect(find.text('Live version'), findsOneWidget);
    expect(find.text('Key: G'), findsOneWidget);
    expect(find.text('Verse 1'), findsOneWidget);
    expect(find.text('Chorus 2'), findsOneWidget);
    expect(find.text('F#m'), findsOneWidget);
  });

  testWidgets(
    'compact reader uses immersive header and hides overlay by default',
    (tester) async {
      await pumpWithViewport(
        tester,
        size: const Size(800, 1200),
        child: buildApp(result: buildResult()),
      );

      expect(find.byType(SongReaderBottomContextBar), findsNothing);
      expect(find.byType(SongReaderTitleBar), findsNothing);
      expect(find.byType(SongReaderCompactOverlay), findsOneWidget);
      expect(find.byType(SongReaderExpandedContextPanel), findsNothing);
      expect(find.byType(SongReaderExpandedToolsPanel), findsNothing);
      expect(find.byTooltip(AppStrings.songReaderBackAction), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.text('Song reader'), findsNothing);
      expect(find.text('Lyrics only'), findsNothing);
      expect(find.text('Reader Song'), findsWidgets);
      expect(
        find.byKey(const Key('song-reader-section-grid-columns-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('compact reader reveals overlay through direct interaction', (
    tester,
  ) async {
    await pumpWithViewport(
      tester,
      size: const Size(800, 1200),
      child: buildApp(result: buildResult()),
    );

    final compactSurface = find.byType(SongReaderCompactSurface);
    final compactSurfaceCenter = tester.getCenter(compactSurface);

    await tester.tapAt(compactSurfaceCenter);
    await tester.pump();

    expect(find.text('Lyrics only'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);

    await tester.tapAt(compactSurfaceCenter);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Lyrics only'), findsNothing);
    expect(find.text('+1'), findsNothing);
  });

  testWidgets('expanded reader shows side panels and no compact overlay', (
    tester,
  ) async {
    await pumpWithViewport(
      tester,
      size: const Size(1440, 1200),
      child: buildApp(result: buildResult()),
    );

    expect(find.byType(SongReaderExpandedContextPanel), findsOneWidget);
    expect(find.byType(SongReaderTitleBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(SongReaderExpandedSurface)).width,
      greaterThan(960),
    );
    expect(find.byType(SongReaderExpandedToolsPanel), findsOneWidget);
    expect(find.byType(SongReaderCompactOverlay), findsNothing);
    expect(find.byType(SongReaderBottomContextBar), findsNothing);
    expect(find.text('Lyrics only'), findsOneWidget);
    final titleRect = tester.getRect(find.byType(SongReaderTitleBar));
    final expandedRect = tester.getRect(find.byType(SongReaderExpandedSurface));
    expect(titleRect.left, greaterThan(expandedRect.left + 200));
    expect(titleRect.right, lessThan(expandedRect.right - 280));
    expect(
      find.byKey(const Key('song-reader-section-grid-columns-1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'expanded reader switches to two columns when one-column content overflows',
    (tester) async {
      await pumpWithViewport(
        tester,
        size: const Size(1440, 1200),
        child: buildApp(result: buildTallResult()),
      );

      expect(
        find.byKey(const Key('song-reader-section-grid-columns-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('switches shell when viewport width changes at runtime', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    expect(find.byType(SongReaderBottomContextBar), findsNothing);
    expect(find.byType(SongReaderExpandedSurface), findsNothing);

    tester.view.physicalSize = const Size(1440, 1200);
    await tester.pumpAndSettle();

    expect(find.byType(SongReaderExpandedSurface), findsOneWidget);
    expect(find.byType(SongReaderBottomContextBar), findsNothing);
  });

  testWidgets('double tap in compact mode toggles auto-fit used after resize', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(result: buildTallResult()));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1440, 1200);
    await tester.pumpAndSettle();
    expect(find.byType(SongReaderExpandedSurface), findsOneWidget);
    expect(
      find.byKey(const Key('song-reader-section-grid-columns-2')),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(800, 1200);
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(SongReaderCompactSurface));
    final firstTap = await tester.startGesture(center);
    await firstTap.up();
    await tester.pump(const Duration(milliseconds: 40));
    final secondTap = await tester.startGesture(center);
    await secondTap.up();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1440, 1200);
    await tester.pumpAndSettle();

    expect(find.byType(SongReaderExpandedSurface), findsOneWidget);
    expect(
      find.byKey(const Key('song-reader-section-grid-columns-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('song-reader-section-grid-columns-2')),
      findsNothing,
    );
  });

  testWidgets('compact overlay hides after inactivity timeout', (tester) async {
    await pumpWithViewport(
      tester,
      size: const Size(800, 1200),
      child: buildApp(result: buildResult()),
    );

    await tester.tapAt(tester.getCenter(find.byType(SongReaderCompactSurface)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Lyrics only'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Lyrics only'), findsNothing);
  });

  testWidgets('compact overlay timeout resets after control interaction', (
    tester,
  ) async {
    await pumpWithViewport(
      tester,
      size: const Size(800, 1200),
      child: buildApp(result: buildResult()),
    );

    await tester.tapAt(tester.getCenter(find.byType(SongReaderCompactSurface)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Lyrics only'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Lyrics only'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Lyrics only'), findsNothing);
  });

  testWidgets('compact reader moves edit and delete into overflow menu', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    expect(find.byTooltip(AppStrings.songReaderBackAction), findsOneWidget);
    expect(find.text(AppStrings.songEditAction), findsNothing);
    expect(find.text(AppStrings.songDeleteAction), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songEditAction), findsOneWidget);
    expect(find.text(AppStrings.songDeleteAction), findsOneWidget);
  });

  testWidgets('delete blocked locally shows an explicit dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        result: buildResult(),
        songLibraryService: _BlockingSongLibraryService(),
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

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songDeleteAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songDeleteBlockedMessage), findsOneWidget);
  });

  testWidgets('editing a conflicted row shows the explicit resolution dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        result: buildResult(),
        songLibraryService: _ConflictRejectingSongLibraryService(),
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

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songEditAction));
    await tester.pumpAndSettle();

    final sourceField = tester.widget<TextField>(find.byType(TextField).last);
    expect(sourceField.maxLines, isNull);

    await tester.tap(find.text(AppStrings.songSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songConflictTitle), findsOneWidget);
    expect(find.text(AppStrings.songConflictMessage), findsOneWidget);
  });

  testWidgets(
    'deleting a conflicted row shows the explicit resolution dialog',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          result: buildResult(),
          songLibraryService: _ConflictRejectingSongLibraryService(),
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

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.songDeleteAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.songConflictTitle), findsOneWidget);
      expect(find.text(AppStrings.songConflictMessage), findsOneWidget);
    },
  );

  testWidgets('hides chords in lyrics only mode', (tester) async {
    await pumpWithViewport(
      tester,
      size: const Size(1440, 1200),
      child: buildApp(result: buildResult()),
    );

    await tester.tap(find.text('Lyrics only'));
    await tester.pumpAndSettle();

    expect(find.text('F#m'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('transposes rendered chords when controls change', (
    tester,
  ) async {
    await pumpWithViewport(
      tester,
      size: const Size(1440, 1200),
      child: buildApp(result: buildResult()),
    );

    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();

    expect(find.text('Gm'), findsOneWidget);
    expect(find.text('F#m'), findsNothing);
  });

  testWidgets('updates shared font size when controls change', (tester) async {
    await pumpWithViewport(
      tester,
      size: const Size(1440, 1200),
      child: buildApp(result: buildResult()),
    );

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
      await pumpWithViewport(
        tester,
        size: const Size(1440, 1200),
        child: buildApp(
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

      expect(find.textContaining('warning'), findsWidgets);
    },
  );

  testWidgets('counts only warning diagnostics in the warning surface', (
    tester,
  ) async {
    await pumpWithViewport(
      tester,
      size: const Size(1440, 1200),
      child: buildApp(
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
    'reader success shell hides catalog connectivity status surfaces',
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

      expect(find.text(AppStrings.songCatalogOnlineStatus), findsNothing);
      expect(find.text(AppStrings.songCatalogOfflineStatus), findsNothing);
      expect(find.text(AppStrings.songCatalogRefreshingStatus), findsNothing);
      expect(
        find.text(AppStrings.songCatalogRefreshFailedStatus),
        findsNothing,
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

    expect(find.byType(SongReaderTitleBar), findsNothing);
    expect(find.text('Reader Song'), findsWidgets);
    expect(attempts, 2);
  });

  testWidgets(
    'handles system back by returning to the song list when opened directly',
    (tester) async {
      await tester.pumpWidget(buildRoutedApp(result: buildResult()));
      await tester.pumpAndSettle();

      expect(find.text('Reader Song'), findsWidgets);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text('Reader Song'), findsOneWidget);
      expect(find.text('Song reader'), findsNothing);
    },
  );

  testWidgets('scoped compact reader shows bottom context bar only', (
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

    expect(find.byType(SongReaderBottomContextBar), findsOneWidget);
    expect(find.text(AppStrings.scopedReaderPreviousAction), findsOneWidget);
    expect(find.text(AppStrings.scopedReaderNextAction), findsOneWidget);
  });

  testWidgets(
    'scoped compact mode falls back to parsed title when selected item title is empty',
    (tester) async {
      await tester.pumpWidget(
        buildScopedReaderApp(
          planDetail: _multiItemPlanDetailWithSongTwoTitle(''),
          resultsBySongId: {
            'song-1': buildScopedResult('Song One'),
            'song-2': buildScopedResult('Reader Song'),
            'song-3': buildScopedResult('Song Three'),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SongReaderBottomContextBar, 'Reader Song'),
        findsOneWidget,
      );
    },
  );

  testWidgets('standard reader entry hides scoped navigation controls', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    expect(find.byType(SongReaderBottomContextBar), findsNothing);
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
            '/plans/plan-fixture/sessions/main-set/items/songs/song-one',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Song One'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.previousSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Song One'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Song Two'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Song Three'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Song Three'), findsWidgets);
  });

  testWidgets('single-item session disables both previous and next', (
    tester,
  ) async {
    final singleItemPlan = PlanDetail(
      plan: PlanSummary(
        id: 'plan-1',
        slug: 'plan-fixture',
        name: 'Plan Fixture',
        description: 'Scoped reader test fixture',
        scheduledFor: null,
        updatedAt: DateTime(2026, 4, 1, 9),
      ),
      sessions: const [
        SessionSummary(
          id: 'session-1',
          slug: 'main-set',
          name: 'Main Set',
          position: 10,
          items: [
            SessionItemSummary(
              id: 'item-10',
              position: 10,
              song: SongSummary(
                id: 'song-1',
                slug: 'song-one',
                title: 'Song One',
              ),
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
            '/plans/plan-fixture/sessions/main-set/items/songs/song-one',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SongReaderBottomContextBar.previousSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Song One'), findsWidgets);

    await tester.tap(find.byKey(SongReaderBottomContextBar.nextSegmentKey));
    await tester.pumpAndSettle();
    expect(find.text('Song One'), findsWidgets);
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
          initialLocation: '/plans/plan-fixture',
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
      await pumpWithViewport(
        tester,
        size: const Size(1440, 1200),
        child: buildScopedReaderApp(
          planDetail: _multiItemPlanDetail(),
          resultsBySongId: {
            'song-1': buildScopedResult('Song One'),
            'song-2': buildScopedResult('Song Two'),
            'song-3': buildScopedResult('Song Three'),
          },
        ),
      );

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
            '/plans/plan-fixture/sessions/main-set/items/songs/song-999',
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
                  '/plans/plan-fixture/sessions/main-set/items/songs/song-two',
              routes: [
                GoRoute(
                  path: AppRoutes.planDetail.path,
                  builder: (context, state) => PlanDetailScreen(
                    planId: _planIdForSlug(
                      _multiItemPlanDetail(),
                      state.pathParameters['planSlug']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: AppRoutes.planSessionSongReader.path,
                  builder: (context, state) => SongReaderScreen(
                    songId: _songIdForScopedRoute(
                      _multiItemPlanDetail(),
                      sessionSlug: state.pathParameters['sessionSlug']!,
                      songSlug: state.pathParameters['songSlug']!,
                    ),
                    sessionItemId: _sessionItemIdForScopedRoute(
                      _multiItemPlanDetail(),
                      sessionSlug: state.pathParameters['sessionSlug']!,
                      songSlug: state.pathParameters['songSlug']!,
                    ),
                    planId: _planIdForSlug(
                      _multiItemPlanDetail(),
                      state.pathParameters['planSlug']!,
                    ),
                    sessionId: _sessionIdForSlug(
                      _multiItemPlanDetail(),
                      state.pathParameters['sessionSlug']!,
                    ),
                    warmPlanDetail: _multiItemPlanDetail(),
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
            '/plans/plan-fixture/sessions/main-set/items/songs/song-two',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const SongListScreen(),
          ),
          GoRoute(
            path: AppRoutes.planDetail.path,
            builder: (context, state) => PlanDetailScreen(
              planId: _planIdForSlug(
                _multiItemPlanDetail(),
                state.pathParameters['planSlug']!,
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.planSessionSongReader.path,
            builder: (context, state) => SongReaderScreen(
              songId: _songIdForScopedRoute(
                _multiItemPlanDetail(),
                sessionSlug: state.pathParameters['sessionSlug']!,
                songSlug: state.pathParameters['songSlug']!,
              ),
              sessionItemId: _sessionItemIdForScopedRoute(
                _multiItemPlanDetail(),
                sessionSlug: state.pathParameters['sessionSlug']!,
                songSlug: state.pathParameters['songSlug']!,
              ),
              planId: _planIdForSlug(
                _multiItemPlanDetail(),
                state.pathParameters['planSlug']!,
              ),
              sessionId: _sessionIdForSlug(
                _multiItemPlanDetail(),
                state.pathParameters['sessionSlug']!,
              ),
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
        contains('/plans/plan-fixture/sessions/main-set/items/songs/song-two'),
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
      slug: 'plan-fixture',
      name: 'Plan Fixture',
      description: 'Scoped reader test fixture',
      scheduledFor: null,
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        slug: 'main-set',
        name: 'Main Set',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-10',
            position: 10,
            song: SongSummary(
              id: 'song-1',
              slug: 'song-one',
              title: 'Song One',
            ),
          ),
          SessionItemSummary(
            id: 'item-20',
            position: 20,
            song: SongSummary(
              id: 'song-2',
              slug: 'song-two',
              title: 'Song Two',
            ),
          ),
          SessionItemSummary(
            id: 'item-30',
            position: 30,
            song: SongSummary(
              id: 'song-3',
              slug: 'song-three',
              title: 'Song Three',
            ),
          ),
        ],
      ),
    ],
  );
}

PlanDetail _multiItemPlanDetailWithSongTwoTitle(String songTwoTitle) {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'plan-fixture',
      name: 'Plan Fixture',
      description: 'Scoped reader test fixture',
      scheduledFor: null,
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: [
      SessionSummary(
        id: 'session-1',
        slug: 'main-set',
        name: 'Main Set',
        position: 10,
        items: [
          const SessionItemSummary(
            id: 'item-10',
            position: 10,
            song: SongSummary(
              id: 'song-1',
              slug: 'song-one',
              title: 'Song One',
            ),
          ),
          SessionItemSummary(
            id: 'item-20',
            position: 20,
            song: SongSummary(
              id: 'song-2',
              slug: 'song-two',
              title: songTwoTitle,
            ),
          ),
          const SessionItemSummary(
            id: 'item-30',
            position: 30,
            song: SongSummary(
              id: 'song-3',
              slug: 'song-three',
              title: 'Song Three',
            ),
          ),
        ],
      ),
    ],
  );
}

String _planIdForSlug(PlanDetail planDetail, String planSlug) {
  if (planDetail.plan.slug == planSlug) {
    return planDetail.plan.id;
  }

  return planSlug;
}

String _sessionIdForSlug(PlanDetail planDetail, String sessionSlug) {
  final session = planDetail.sessions.where((candidate) {
    return candidate.slug == sessionSlug;
  }).firstOrNull;

  return session?.id ?? sessionSlug;
}

String _songIdForScopedRoute(
  PlanDetail planDetail, {
  required String sessionSlug,
  required String songSlug,
}) {
  final session = planDetail.sessions.where((candidate) {
    return candidate.slug == sessionSlug;
  }).firstOrNull;
  final song = session?.items
      .map((candidate) => candidate.song)
      .where((candidate) => candidate.slug == songSlug)
      .firstOrNull;

  return song?.id ?? songSlug;
}

String _sessionItemIdForScopedRoute(
  PlanDetail planDetail, {
  required String sessionSlug,
  required String songSlug,
}) {
  final session = planDetail.sessions.where((candidate) {
    return candidate.slug == sessionSlug;
  }).firstOrNull;
  final item = session?.items.where((candidate) {
    return candidate.song.id ==
        _songIdForScopedRoute(
          planDetail,
          sessionSlug: sessionSlug,
          songSlug: songSlug,
        );
  }).firstOrNull;

  return item?.id ?? songSlug;
}

class _BlockingSongLibraryService extends SongLibraryService {
  _BlockingSongLibraryService()
    : super(_ReaderFakeSongRepository(), _ReaderFakeSongRepository());

  @override
  Future<SongMutationRecord> deleteSong({
    required ActiveCatalogContext context,
    required String songId,
  }) async {
    throw SongDeleteBlockedException(songId);
  }

  @override
  Future<SongSource> getSongSource({
    required ActiveCatalogContext context,
    required String songId,
  }) async {
    return const SongSource(id: 'reader_song', source: '{title: Reader Song}');
  }
}

class _ConflictRejectingSongLibraryService extends SongLibraryService {
  _ConflictRejectingSongLibraryService()
    : super(_ReaderFakeSongRepository(), _ReaderFakeSongRepository());

  @override
  Future<SongMutationRecord> updateSong({
    required ActiveCatalogContext context,
    required String songId,
    required String title,
    required String chordproSource,
  }) async {
    throw SongConflictResolutionRequiredException(songId);
  }

  @override
  Future<SongMutationRecord> deleteSong({
    required ActiveCatalogContext context,
    required String songId,
  }) async {
    throw SongConflictResolutionRequiredException(songId);
  }

  @override
  Future<SongSource> getSongSource({
    required ActiveCatalogContext context,
    required String songId,
  }) async {
    return const SongSource(id: 'reader_song', source: '{title: Reader Song}');
  }
}

class _ReaderFakeSongRepository
    implements SongCatalogReadRepository, SongMutationStore {
  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async => 'reader-song';

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
  }) async =>
      const SongSource(id: 'reader_song', source: '{title: Reader Song}');

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => const SongSummary(id: 'reader_song', title: 'Reader Song');

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async => const SongSummary(id: 'reader_song', title: 'Reader Song');

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async => const [SongSummary(id: 'reader_song', title: 'Reader Song')];

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
