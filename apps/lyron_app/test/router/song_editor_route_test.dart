// TODO(auth-invite-sso): stub updated when song editor route tests rewritten
// ignore_for_file: non_abstract_class_inherits_abstract_member, override_on_non_overriding_member
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
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
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_providers.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_screen.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/router/slug_route_resolvers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('song editor route constant remains stable', () {
    expect(AppRoutes.songEditor.path, '/songs/:songSlug/edit');
  });

  testWidgets('signed-in users can land on the editor route directly', (
    tester,
  ) async {
    final repository = _TestAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      ),
    );
    final controller = AppAuthController(repository);
    await controller.restoreSession();

    final router = createAppRouter(
      authController: controller,
      refreshListenable: controller,
      initialLocation: '/songs/egy-ut/edit',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWith((_) => controller),
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
          songLibraryServiceProvider.overrideWithValue(
            SongLibraryService(
              _TestSongCatalogReadRepository(
                source: const SongSource(
                  id: 'song-1',
                  source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
                ),
              ),
            ),
          ),
          songEditorRouteDataProvider('egy-ut').overrideWith(
            (ref) async => const SongEditorRouteData(
              songId: 'song-1',
              songSlug: 'egy-ut',
              source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit song'), findsOneWidget);
    expect(find.text('Canonical source'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      contains('Heart of Worship'),
    );
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('editor back button returns to song view', (tester) async {
    final repository = _TestAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      ),
    );
    final controller = AppAuthController(repository);
    await controller.restoreSession();

    final router = createAppRouter(
      authController: controller,
      refreshListenable: controller,
      initialLocation: '/songs/egy-ut/edit',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWith((_) => controller),
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
          songLibraryServiceProvider.overrideWithValue(
            SongLibraryService(
              _TestSongCatalogReadRepository(
                source: const SongSource(
                  id: 'song-1',
                  source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
                ),
              ),
            ),
          ),
          songLibraryListProvider.overrideWith(
            (ref) async => const [
              SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Reader Song'),
            ],
          ),
          songLibraryReaderProvider.overrideWithProvider(
            (songId) => FutureProvider.autoDispose(
              (ref) async => SongReaderResult(
                song: ParsedSong(
                  title: 'Reader Song',
                  sourceKey: 'D',
                  sections: [
                    SongSection(
                      kind: SongSectionKind.verse,
                      label: 'Verse',
                      number: 1,
                      lines: [
                        LyricLine(
                          segments: [const LyricSegment(text: 'Reader body')],
                        ),
                      ],
                    ),
                  ],
                  diagnostics: const [],
                ),
              ),
            ),
          ),
          songEditorRouteDataProvider('egy-ut').overrideWith(
            (ref) async => const SongEditorRouteData(
              songId: 'song-1',
              songSlug: 'egy-ut',
              source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('song-editor-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('Reader Song'), findsWidgets);
    expect(find.text('Edit song'), findsNothing);
  });

  testWidgets('editor back button pops when the route can pop', (tester) async {
    final observer = _RecordingNavigatorObserver();
    const source = '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''';

    GoRouter.optionURLReflectsImperativeAPIs = true;
    final router = GoRouter(
      initialLocation: '/songs/egy-ut',
      observers: [observer],
      routes: [
        GoRoute(
          path: '/songs/:songSlug',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const Text('Reader Song'),
                  TextButton(
                    onPressed: () {
                      context.push(
                        '/songs/${state.pathParameters['songSlug']}/edit',
                      );
                    },
                    child: const Text('Edit song'),
                  ),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/songs/:songSlug/edit',
          builder: (context, state) => SongEditorScreen.edit(
            songId: 'song-1',
            songSlug: state.pathParameters['songSlug']!,
            initialSource: source,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeCatalogContextProvider.overrideWithValue(null)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit song'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('song-editor-back-button')));
    await tester.pumpAndSettle();

    expect(observer.popCount, 1);
    expect(observer.replaceCount, 0);
    expect(find.text('Reader Song'), findsOneWidget);
    expect(find.text('Edit song'), findsOneWidget);
  });

  testWidgets('save returns to song view', (tester) async {
    final store = await _pumpEditorAndReturnToSongView(
      tester,
      actionLabel: 'Save',
      editedSource: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
[A]and I sing louder
''',
    );

    expect(store.lastUpsertedRecord, isNotNull);
    expect(store.lastUpsertedRecord!.id, 'song-1');
    expect(store.lastUpsertedRecord!.slug, 'egy-ut');
    expect(store.lastUpsertedRecord!.chordproSource, contains('sing louder'));
  });

  testWidgets('cancel returns to song view', (tester) async {
    final store = await _pumpEditorAndReturnToSongView(
      tester,
      actionLabel: 'Cancel',
      confirmDiscard: true,
      editedSource: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
[A]and I sing louder
''',
    );

    expect(store.lastUpsertedRecord, isNull);
  });

  testWidgets('save shows conflict dialog when the song diverged', (
    tester,
  ) async {
    final store = await _pumpEditorAndReturnToSongView(
      tester,
      actionLabel: 'Save',
      editedSource: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
[A]and I sing louder
''',
      existingRecord: const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'egy-ut',
        title: 'Heart of Worship',
        chordproSource: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
        version: 8,
        baseVersion: 7,
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.conflict,
        conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
      ),
      expectSongViewReturn: false,
    );

    expect(find.text(AppStrings.songConflictTitle), findsOneWidget);
    expect(find.text(AppStrings.songConflictMessage), findsOneWidget);
    expect(find.text('Edit song'), findsOneWidget);
    expect(store.lastUpsertedRecord, isNull);
  });

  testWidgets(
    'signed-in users see loading while the editor context is refreshing',
    (tester) async {
      final repository = _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        ),
      );
      final controller = AppAuthController(repository);
      await controller.restoreSession();

      final router = createAppRouter(
        authController: controller,
        refreshListenable: controller,
        initialLocation: '/songs/egy-ut/edit',
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            appAuthControllerProvider.overrideWith((_) => controller),
            appAuthListenableProvider.overrideWithValue(controller),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.refreshing,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: false,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.text('Loading song...'), findsOneWidget);
      expect(find.text('The requested page was not found.'), findsNothing);
    },
  );

  testWidgets('signed-out users are redirected away from the editor route', (
    tester,
  ) async {
    final repository = _TestAuthRepository();
    final controller = AppAuthController(repository);
    await controller.restoreSession();

    final router = createAppRouter(
      authController: controller,
      refreshListenable: controller,
      initialLocation: '/songs/blocked-song/edit',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWith((_) => controller),
          appAuthListenableProvider.overrideWithValue(controller),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Edit song'), findsNothing);
  });

  testWidgets('missing editor slugs fall back to the not-found scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          songEditorRouteDataProvider(
            'missing-song',
          ).overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: SongEditorSlugRouteResolver(songSlug: 'missing-song'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The requested page was not found.'), findsOneWidget);
    expect(find.text('Edit song'), findsNothing);
  });
}

Future<_RecordingSongMutationStore> _pumpEditorAndReturnToSongView(
  WidgetTester tester, {
  required String actionLabel,
  String? editedSource,
  SongMutationRecord? existingRecord,
  bool expectSongViewReturn = true,
  bool confirmDiscard = false,
}) async {
  final repository = _TestAuthRepository(
    restoredSession: const AppAuthSession(
      userId: 'user-1',
      email: 'demo@lyron.local',
    ),
  );
  final controller = AppAuthController(repository);
  await controller.restoreSession();

  final router = createAppRouter(
    authController: controller,
    refreshListenable: controller,
    initialLocation: '/songs/egy-ut/edit',
  );
  addTearDown(router.dispose);
  final mutationStore = _RecordingSongMutationStore(
    existingRecord:
        existingRecord ??
        const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'egy-ut',
          title: 'Heart of Worship',
          chordproSource: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
          version: 7,
          baseVersion: 7,
          syncStatus: SongSyncStatus.synced,
        ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        appAuthControllerProvider.overrideWith((_) => controller),
        appAuthListenableProvider.overrideWithValue(controller),
        activeCatalogContextProvider.overrideWithValue(
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
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
        songLibraryServiceProvider.overrideWithValue(
          SongLibraryService(
            _TestSongCatalogReadRepository(
              source: const SongSource(
                id: 'song-1',
                source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
              ),
            ),
            mutationStore,
          ),
        ),
        songLibraryListProvider.overrideWith(
          (ref) async => const [
            SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Reader Song'),
          ],
        ),
        songLibraryReaderProvider.overrideWithProvider(
          (songId) => FutureProvider.autoDispose(
            (ref) async => SongReaderResult(
              song: ParsedSong(
                title: 'Reader Song',
                sourceKey: 'D',
                sections: [
                  SongSection(
                    kind: SongSectionKind.verse,
                    label: 'Verse',
                    number: 1,
                    lines: [
                      LyricLine(
                        segments: [const LyricSegment(text: 'Reader body')],
                      ),
                    ],
                  ),
                ],
                diagnostics: const [],
              ),
            ),
          ),
        ),
        songEditorRouteDataProvider('egy-ut').overrideWith(
          (ref) async => const SongEditorRouteData(
            songId: 'song-1',
            songSlug: 'egy-ut',
            source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  if (editedSource != null) {
    await tester.enterText(find.byType(TextField), editedSource);
    await tester.pumpAndSettle();
  }

  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();

  if (confirmDiscard) {
    expect(find.text(AppStrings.songEditorDiscardChangesTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.songEditorDiscardAction));
    await tester.pumpAndSettle();
  }

  if (expectSongViewReturn) {
    expect(find.text('Reader Song'), findsWidgets);
    expect(find.text('Edit song'), findsNothing);
  }

  return mutationStore;
}

class _TestAuthRepository implements AuthRepository {
  _TestAuthRepository({this.restoredSession});

  final AppAuthSession? restoredSession;

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

  @override
  Stream<AppAuthSession?> watchSession() async* {
    yield restoredSession;
  }

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _TestSongCatalogReadRepository implements SongCatalogReadRepository {
  _TestSongCatalogReadRepository({required this.source});

  final SongSource source;

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => source;

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => SongSummary(id: source.id, slug: 'egy-ut', title: 'Egy út');

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async => SongSummary(id: source.id, slug: songSlug, title: 'Egy út');
}

class _RecordingSongMutationStore implements SongMutationStore {
  _RecordingSongMutationStore({required this.existingRecord});

  final SongMutationRecord existingRecord;
  SongMutationRecord? lastUpsertedRecord;

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}

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
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) async => true;

  // docs/specs/2026-08-06-in-flight-create-cancellation.md (D1/D3): this
  // fake is never driven through SongMutationSyncController.syncPendingSongs
  // in this file, so these stubs are never exercised -- applied
  // unconditionally like reconcileSyncedSong above.
  @override
  Future<int?> markCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) async => expectedRevision + 1;

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) async => false;

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    return songId == existingRecord.id ? existingRecord : null;
  }

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
  Future<bool> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) async => true;

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    lastUpsertedRecord = record;
  }

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  var popCount = 0;
  var replaceCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaceCount += 1;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
