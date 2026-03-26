import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
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
      'explicit sign-out prevents an in-flight refresh from restoring cached authenticated access',
      () async {
        final delayedRepository = _DelayedSongRepository();
        final controller = SongCatalogController(
          store: store,
          remoteRepository: delayedRepository,
          authSessionReader: () => const AppAuthSession(
            userId: 'user-1',
            email: 'demo@lyrica.local',
          ),
          organizationReader: () async => 'org-1',
          sessionVerifier: () async => CatalogSessionStatus.verified,
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

  Object? listSongsError;
  final Map<String, Object> sourceErrors = <String, Object>{};

  @override
  Future<List<SongSummary>> listSongs() async {
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

  @override
  Future<List<SongSummary>> listSongs() async {
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
