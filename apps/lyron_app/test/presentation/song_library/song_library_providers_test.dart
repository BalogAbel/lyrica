import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

void main() {
  final originalDontWarnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        originalDontWarnAboutMultipleDatabases;
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'resolves the local-first song library provider graph end to end',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => [
          {'id': 'song-1', 'slug': 'egy-ut', 'title': 'Egy út'},
        ],
        getSongRow: (id) async => {
          'id': id,
          'chordpro_source': '{title:Egy út}\n',
        },
      );

      await authController.restoreSession();

      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          appAuthListenableProvider.overrideWithValue(authController),
          songCatalogDatabaseProvider.overrideWithValue(database),
          songCatalogStoreProvider.overrideWithValue(store),
          supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => 'org-1',
          ),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(authController.dispose);
      addTearDown(database.close);

      await container.read(songCatalogControllerProvider).refreshCatalog();

      expect(
        container.read(songLibraryRepositoryProvider),
        isA<LocalFirstSongRepository>(),
      );
      expect(container.read(songLibraryParserProvider), isNotNull);
      expect(
        container.read(songLibraryTransposerProvider),
        isA<ChordTransposer>(),
      );
      expect(container.read(songLibraryServiceProvider), isNotNull);

      final songs = await container.read(songLibraryListProvider.future);
      expect(songs, isNotEmpty);
      expect(songs.first, isA<SongSummary>());

      final readerResult = await container.read(
        songLibraryReaderProvider('song-1').future,
      );

      expect(readerResult, isA<SongReaderResult>());
      expect(readerResult.song.title, 'Egy út');
    },
  );

  test('logs parser diagnostics when loading a song reader result', () async {
    final loggedDiagnostics = <ParseDiagnostic>[];
    final container = ProviderContainer(
      overrides: [
        songLibraryRepositoryProvider.overrideWithValue(_StubSongRepository()),
        activeCatalogContextProvider.overrideWithValue(
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        ),
        songLibraryParserProvider.overrideWithValue(
          _StubChordproParser(
            ParsedSong(
              title: 'Logged Song',
              sections: const [],
              diagnostics: [
                ParseDiagnostic(
                  severity: ParseDiagnosticSeverity.warning,
                  message: 'Unsupported directive',
                  line: const ParseDiagnosticLineMetadata(
                    lineNumber: 4,
                    columnNumber: 1,
                  ),
                  context: '{unknown:test}',
                ),
              ],
            ),
          ),
        ),
        songLibraryDiagnosticLoggerProvider.overrideWithValue(
          (diagnostic) => loggedDiagnostics.add(diagnostic),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      songLibraryReaderProvider('stub').future,
    );

    expect(result.song.title, 'Logged Song');
    expect(loggedDiagnostics, hasLength(1));
    expect(loggedDiagnostics.single.message, 'Unsupported directive');
    expect(loggedDiagnostics.single.context, '{unknown:test}');
  });

  test('falls back to catalog title when parsed song title is empty', () async {
    final container = ProviderContainer(
      overrides: [
        songLibraryRepositoryProvider.overrideWithValue(
          _ReaderFallbackSongRepository(),
        ),
        activeCatalogContextProvider.overrideWithValue(
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      songLibraryReaderProvider('song-1').future,
    );

    expect(result.song.title, 'Catalog Title');
  });

  test(
    'does not query catalog titles when parsed title is already present',
    () async {
      final repository = _NonEmptyTitleReaderRepository();
      final container = ProviderContainer(
        overrides: [
          songLibraryRepositoryProvider.overrideWithValue(repository),
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        songLibraryReaderProvider('song-1').future,
      );

      expect(result.song.title, 'Reader Song');
      expect(repository.getSongSummaryByIdCalls, 0);
    },
  );

  test(
    'keeps the authenticated slice on the cached read path while Supabase remains the refresh boundary',
    () async {
      final authController = AppAuthController(_SignedOutAuthRepository());
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => const [],
        getSongRow: (id) async => null,
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          appAuthListenableProvider.overrideWithValue(authController),
          supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(authController.dispose);

      expect(
        container.read(songLibraryRepositoryProvider),
        isA<LocalFirstSongRepository>(),
      );
      expect(
        container.read(supabaseSongRepositoryProvider),
        same(remoteRepository),
      );
    },
  );

  test(
    'recomputes the song list when the catalog snapshot changes after the context was already active',
    () async {
      final testCatalogStateProvider = StateProvider<CatalogSnapshotState>(
        (ref) => const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.unavailable,
          refreshStatus: CatalogRefreshStatus.refreshing,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: false,
        ),
      );
      var listCalls = 0;
      late ProviderContainer container;

      container = ProviderContainer(
        overrides: [
          catalogSnapshotStateProvider.overrideWith(
            (ref) => ref.watch(testCatalogStateProvider),
          ),
          songLibraryServiceProvider.overrideWithValue(
            _RecordingSongLibraryService(
              listSongsImpl: ({required context}) async {
                listCalls += 1;
                return container.read(testCatalogStateProvider).hasCachedCatalog
                    ? const [
                        SongSummary(
                          id: 'song-1',
                          slug: 'egy-ut',
                          title: 'Egy út',
                        ),
                      ]
                    : const [];
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(songLibraryListProvider.future), isEmpty);

      container
          .read(testCatalogStateProvider.notifier)
          .state = const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      );

      expect(await container.read(songLibraryListProvider.future), const [
        SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
      ]);
      expect(listCalls, 2);
    },
  );

  test(
    'disposing the signed-in song catalog provider stops periodic refresh polling',
    () {
      fakeAsync((async) {
        final authController = AppAuthController(_SignedInAuthRepository());
        final database = SongCatalogDatabase.inMemory();
        final store = DriftSongCatalogStore(database);
        final remoteRepository = _CountingSongRepository();
        final foregroundState = _TestAppForegroundState();

        unawaited(authController.restoreSession());
        async.flushMicrotasks();

        final container = ProviderContainer(
          overrides: [
            appAuthControllerProvider.overrideWithValue(authController),
            appAuthListenableProvider.overrideWithValue(authController),
            songCatalogDatabaseProvider.overrideWithValue(database),
            songCatalogStoreProvider.overrideWithValue(store),
            supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
            activeOrganizationReaderProvider.overrideWithValue(
              () async => 'org-1',
            ),
            catalogSessionVerifierProvider.overrideWithValue(
              () async => CatalogSessionStatus.verified,
            ),
            appForegroundStateProvider.overrideWithValue(foregroundState),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(authController.dispose);
        addTearDown(database.close);

        final subscription = container.listen(
          catalogSnapshotStateProvider,
          (previous, next) {},
          fireImmediately: true,
        );
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, greaterThanOrEqualTo(2));

        subscription.close();
        unawaited(container.pump());
        async.flushMicrotasks();

        final callsAfterDispose = remoteRepository.listSongsCalls;
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, callsAfterDispose);
      });
    },
  );

  test(
    'auth-driven sign-out while the provider stays mounted clears catalog access and cache',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => [
          {'id': 'song-1', 'slug': 'egy-ut', 'title': 'Egy út'},
        ],
        getSongRow: (id) async => {
          'id': id,
          'chordpro_source': '{title:Egy út}\n',
        },
      );

      await authController.restoreSession();

      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          appAuthListenableProvider.overrideWithValue(authController),
          songCatalogDatabaseProvider.overrideWithValue(database),
          songCatalogStoreProvider.overrideWithValue(store),
          supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => 'org-1',
          ),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
          appForegroundStateProvider.overrideWithValue(
            _TestAppForegroundState(),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(authController.dispose);
      addTearDown(database.close);

      await container.read(songCatalogControllerProvider).refreshCatalog();
      expect(
        container.read(catalogSnapshotStateProvider).hasCachedCatalog,
        isTrue,
      );

      await authController.signOut();
      await container.pump();

      final state = container.read(catalogSnapshotStateProvider);
      expect(state.context, isNull);
      expect(state.hasCachedCatalog, isFalse);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    },
  );

  test(
    'auth-driven sign-out clears cached access even before the controller resolves its context',
    () async {
      final authController = AppAuthController(_SignedInAuthRepository());
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final delayedOrganization = Completer<String?>();
      final remoteRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => const [],
        getSongRow: (id) async => null,
      );

      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
        sources: const [
          SongSource(id: 'song-1', source: '{title: Cached Song}'),
        ],
        refreshedAt: DateTime.utc(2026, 3, 29, 12),
      );

      await authController.restoreSession();

      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWithValue(authController),
          appAuthListenableProvider.overrideWithValue(authController),
          songCatalogDatabaseProvider.overrideWithValue(database),
          songCatalogStoreProvider.overrideWithValue(store),
          supabaseSongRepositoryProvider.overrideWithValue(remoteRepository),
          activeOrganizationReaderProvider.overrideWithValue(
            () => delayedOrganization.future,
          ),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
          appForegroundStateProvider.overrideWithValue(
            _TestAppForegroundState(),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(authController.dispose);
      addTearDown(database.close);

      final subscription = container.listen(
        catalogSnapshotStateProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await authController.signOut();
      await container.pump();

      expect(container.read(catalogSnapshotStateProvider).context, isNull);
      expect(
        container.read(catalogSnapshotStateProvider).hasCachedCatalog,
        isFalse,
      );
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );

      delayedOrganization.complete('org-1');
      await container.pump();
    },
  );
}

class _StubSongRepository implements SongCatalogReadRepository {
  int getSongSourceCalls = 0;

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
  }) async {
    getSongSourceCalls += 1;
    return const SongSource(id: 'stub', source: 'source');
  }

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    return null;
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    return null;
  }
}

class _StubChordproParser extends ChordproParser {
  _StubChordproParser(this._result);

  final ParsedSong _result;

  @override
  ParsedSong parse(String source) => _result;
}

class _ReaderFallbackSongRepository implements SongCatalogReadRepository {
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
  }) async {
    return const SongSource(
      id: 'song-1',
      source: '{subtitle:From source without title}\nLine',
    );
  }

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    return const SongSummary(id: 'song-1', title: 'Catalog Title');
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    return null;
  }
}

class _NonEmptyTitleReaderRepository implements SongCatalogReadRepository {
  int getSongSummaryByIdCalls = 0;

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
  }) async {
    return const SongSource(id: 'song-1', source: '{title:Reader Song}\nLine');
  }

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    getSongSummaryByIdCalls += 1;
    return const SongSummary(id: 'song-1', title: 'Catalog Title');
  }

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async {
    return null;
  }
}

class _RecordingSongLibraryService extends SongLibraryService {
  _RecordingSongLibraryService({required this.listSongsImpl})
    : super(_NoopSongRepository());

  final Future<List<SongSummary>> Function({
    required ActiveCatalogContext context,
  })
  listSongsImpl;

  @override
  Future<List<SongSummary>> listSongs({required ActiveCatalogContext context}) {
    return listSongsImpl(context: context);
  }
}

class _CountingSongRepository extends SupabaseSongRepository {
  _CountingSongRepository()
    : super.testing(
        listSongsRows: () async => [
          {'id': 'song-1', 'slug': 'egy-ut', 'title': 'Egy út'},
        ],
        getSongRow: (id) async => {
          'id': id,
          'chordpro_source': '{title:Egy út}\n',
        },
      );

  int listSongsCalls = 0;

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    return super.listSongs();
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
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
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

class _SignedInAuthRepository implements AuthRepository {
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

class _SignedOutAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;

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

class _TestAppForegroundState implements AppForegroundState {
  _TestAppForegroundState({bool isForeground = true})
    : _isForeground = isForeground;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isForeground;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> watchForeground() => _controller.stream;

  void setForeground(bool value) {
    _isForeground = value;
    _controller.add(value);
  }
}
