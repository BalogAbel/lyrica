import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyrica_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SongCatalogController', () {
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;
    late _FakeSongRepository remoteRepository;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
      remoteRepository = _FakeSongRepository();
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'first successful refresh creates an active cached snapshot',
      () async {
        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.context,
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        );
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.online,
        );
        expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
        expect(controller.state.sessionStatus, CatalogSessionStatus.verified);
        expect(controller.state.hasCachedCatalog, isTrue);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [
            SongSummary(id: 'song-1', title: 'Alpha'),
            SongSummary(id: 'song-2', title: 'Beta'),
          ],
        );
      },
    );

    test('keeps the previous active snapshot when refresh fails', () async {
      final controller = SongCatalogController(
        store: store,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyrica.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      await controller.refreshCatalog();
      remoteRepository.listSongsError = const SocketException('offline');

      await controller.refreshCatalog();

      expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
      expect(
        controller.state.connectionStatus,
        CatalogConnectionStatus.offlineCached,
      );
      expect(controller.state.hasCachedCatalog, isTrue);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        const [
          SongSummary(id: 'song-1', title: 'Alpha'),
          SongSummary(id: 'song-2', title: 'Beta'),
        ],
      );
    });

    test(
      'cached summaries remain available when connectivity is lost',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async =>
              CatalogSessionStatus.unverifiableDueToConnectivity,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.offlineCached,
        );
        expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
        expect(
          controller.state.sessionStatus,
          CatalogSessionStatus.unverifiableDueToConnectivity,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [SongSummary(id: 'song-1', title: 'Cached Song')],
        );
      },
    );

    test(
      'falls back to the cached organization context when connectivity loss prevents remote resolution',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async =>
              throw const SocketException('offline'),
          sessionVerifier: () async =>
              CatalogSessionStatus.unverifiableDueToConnectivity,
        );

        await controller.refreshCatalog();

        expect(
          controller.state.context,
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        );
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.offlineCached,
        );
        expect(controller.state.hasCachedCatalog, isTrue);
      },
    );

    test(
      'confirmed session expiry blocks cached authenticated reading',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.expired,
        );

        await controller.refreshCatalog();

        expect(controller.state.context, isNull);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.unavailable,
        );
        expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
        expect(controller.state.hasCachedCatalog, isFalse);
      },
    );

    test(
      'authorization failure while resolving the active organization degrades to expired access instead of throwing',
      () async {
        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => throw const PostgrestException(
            message: 'permission denied',
            code: '42501',
          ),
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await expectLater(controller.refreshCatalog(), completes);

        expect(controller.state.context, isNull);
        expect(controller.state.sessionStatus, CatalogSessionStatus.expired);
        expect(
          controller.state.connectionStatus,
          CatalogConnectionStatus.unavailable,
        );
      },
    );

    test('explicit sign-out deletes the cached catalog', () async {
      final controller = SongCatalogController(
        store: store,
        remoteRepository: remoteRepository,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyrica.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      await controller.refreshCatalog();
      await controller.handleExplicitSignOut();

      expect(controller.state.context, isNull);
      expect(controller.state.hasCachedCatalog, isFalse);
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    });

    test(
      'explicit sign-out clears cached access even when the active context was not yet loaded',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Cached Song')],
          sources: const [
            SongSource(id: 'song-1', source: '{title: Cached Song}'),
          ],
          refreshedAt: DateTime.utc(2026, 3, 25, 10),
        );

        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => throw const PostgrestException(
            message: 'permission denied',
            code: '42501',
          ),
          sessionVerifier: () async => CatalogSessionStatus.verified,
        );

        await controller.handleExplicitSignOut();

        expect(controller.state.context, isNull);
        expect(controller.state.hasCachedCatalog, isFalse);
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
      'explicit sign-out prevents an in-flight refresh from restoring cached authenticated access',
      () async {
        final delayedRepository = _DelayedSongRepository();
        final foregroundState = _TestAppForegroundState();
        final controller = SongCatalogController(
          store: store,
          remoteRepository: delayedRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
        );

        final refreshFuture = controller.refreshCatalog();
        await delayedRepository.listSongsStarted.future;

        await controller.handleExplicitSignOut();
        delayedRepository.completeWith(
          const [SongSummary(id: 'song-1', title: 'Alpha')],
          const {'song-1': SongSource(id: 'song-1', source: '{title: Alpha}')},
        );
        await refreshFuture;

        expect(controller.state.context, isNull);
        expect(controller.state.hasCachedCatalog, isFalse);
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
      'ignores a periodic trigger while a manual refresh is already in flight',
      () {
        fakeAsync((async) {
          final delayedRepository = _DelayedSongRepository();
          final foregroundState = _TestAppForegroundState();
          final controller = SongCatalogController(
            store: store,
            remoteRepository: delayedRepository,
            authSessionReader: () => const AppAuthSession(
              userId: 'user-1',
              email: 'demo@lyrica.local',
            ),
            organizationReader: () async => 'org-1',
            sessionVerifier: () async => CatalogSessionStatus.verified,
            foregroundState: foregroundState,
            refreshInterval: const Duration(minutes: 5),
          );
          addTearDown(controller.dispose);

          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();

          expect(delayedRepository.listSongsCalls, 1);

          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();

          expect(delayedRepository.listSongsCalls, 1);
          delayedRepository.completeWith(
            const [SongSummary(id: 'song-1', title: 'Alpha')],
            const {
              'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
            },
          );
          async.flushMicrotasks();

          expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
          expect(controller.state.hasCachedCatalog, isTrue);
        });
      },
    );

    test('runs periodic refresh only after the configured cadence', () {
      fakeAsync((async) {
        final foregroundState = _TestAppForegroundState();
        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(minutes: 5),
        );

        async.elapse(const Duration(minutes: 4, seconds: 59));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 0);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);

        controller.dispose();
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);
      });
    });

    test(
      'runs periodic refresh only while the app stays in the foreground',
      () {
        fakeAsync((async) {
          final foregroundState = _TestAppForegroundState(isForeground: false);
          final controller = SongCatalogController(
            store: store,
            remoteRepository: remoteRepository,
            authSessionReader: () => const AppAuthSession(
              userId: 'user-1',
              email: 'demo@lyrica.local',
            ),
            organizationReader: () async => 'org-1',
            sessionVerifier: () async => CatalogSessionStatus.verified,
            foregroundState: foregroundState,
            refreshInterval: const Duration(minutes: 5),
          );
          addTearDown(controller.dispose);

          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(remoteRepository.listSongsCalls, 0);

          foregroundState.setForeground(true);
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(remoteRepository.listSongsCalls, 1);

          foregroundState.setForeground(false);
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(remoteRepository.listSongsCalls, 1);
        });
      },
    );

    test('stops periodic refresh after explicit sign-out', () {
      fakeAsync((async) {
        final foregroundState = _TestAppForegroundState();
        AppAuthSession? session = const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyrica.local',
        );
        final controller = SongCatalogController(
          store: store,
          remoteRepository: remoteRepository,
          authSessionReader: () => session,
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
          foregroundState: foregroundState,
          refreshInterval: const Duration(minutes: 5),
        );
        addTearDown(controller.dispose);

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);

        session = null;
        unawaited(controller.handleExplicitSignOut());
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(remoteRepository.listSongsCalls, 1);
      });
    });

    test(
      'a stale in-flight refresh still prevents overlapping refresh work after explicit sign-out',
      () {
        fakeAsync((async) {
          final delayedRepository = _MultiPhaseSongRepository();
          final foregroundState = _TestAppForegroundState();
          AppAuthSession? session = const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          );
          final controller = SongCatalogController(
            store: store,
            remoteRepository: delayedRepository,
            authSessionReader: () => session,
            organizationReader: () async => 'org-1',
            sessionVerifier: () async => CatalogSessionStatus.verified,
            foregroundState: foregroundState,
            refreshInterval: const Duration(minutes: 5),
          );
          addTearDown(controller.dispose);

          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();
          expect(delayedRepository.listSongsCalls, 1);

          session = null;
          unawaited(controller.handleExplicitSignOut());
          async.flushMicrotasks();

          session = const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          );
          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();

          expect(delayedRepository.listSongsCalls, 1);

          delayedRepository.completeRequest(0);
          async.flushMicrotasks();

          unawaited(controller.refreshCatalog());
          async.flushMicrotasks();
          expect(delayedRepository.listSongsCalls, 2);

          delayedRepository.completeRequest(1);
          async.flushMicrotasks();
        });
      },
    );
  });
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository()
    : _songs = const [
        SongSummary(id: 'song-1', title: 'Alpha'),
        SongSummary(id: 'song-2', title: 'Beta'),
      ],
      _sources = const {
        'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
        'song-2': SongSource(id: 'song-2', source: '{title: Beta}'),
      };

  final List<SongSummary> _songs;
  final Map<String, SongSource> _sources;

  int listSongsCalls = 0;
  Object? listSongsError;
  final Map<String, Object> sourceErrors = <String, Object>{};

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    final error = listSongsError;
    if (error != null) {
      throw error;
    }

    return _songs;
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final error = sourceErrors[id];
    if (error != null) {
      throw error;
    }

    return _sources[id]!;
  }
}

class _DelayedSongRepository implements SongRepository {
  final Completer<void> listSongsStarted = Completer<void>();
  final Completer<List<SongSummary>> _songsCompleter =
      Completer<List<SongSummary>>();
  Map<String, SongSource> _sources = const {};
  int listSongsCalls = 0;

  @override
  Future<List<SongSummary>> listSongs() async {
    listSongsCalls += 1;
    if (!listSongsStarted.isCompleted) {
      listSongsStarted.complete();
    }

    return _songsCompleter.future;
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final songs = await _songsCompleter.future;
    assert(songs.any((song) => song.id == id));
    return _sources[id]!;
  }

  void completeWith(List<SongSummary> songs, Map<String, SongSource> sources) {
    _sources = sources;
    if (!_songsCompleter.isCompleted) {
      _songsCompleter.complete(songs);
    }
  }
}

class _MultiPhaseSongRepository implements SongRepository {
  int listSongsCalls = 0;
  final List<Completer<List<SongSummary>>> _songRequests =
      <Completer<List<SongSummary>>>[];
  Map<String, SongSource> _sources = const {
    'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
  };

  @override
  Future<List<SongSummary>> listSongs() {
    listSongsCalls += 1;
    final completer = Completer<List<SongSummary>>();
    _songRequests.add(completer);
    return completer.future;
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    return _sources[id]!;
  }

  void completeRequest(
    int requestIndex, {
    List<SongSummary> songs = const [SongSummary(id: 'song-1', title: 'Alpha')],
    Map<String, SongSource> sources = const {
      'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
    },
  }) {
    _sources = sources;
    final completer = _songRequests[requestIndex];
    if (!completer.isCompleted) {
      completer.complete(songs);
    }
  }
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
