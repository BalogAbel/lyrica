import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyrica_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() {
  late HttpOverrides? originalHttpOverrides;

  setUpAll(() {
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PassthroughHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  test(
    'keeps the cached catalog readable after the persistent cache is reopened offline',
    () async {
      final previousDontWarn =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousDontWarn;
      });

      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final tempDir = await Directory.systemTemp.createTemp(
        'local-first-song-reader-flow',
      );
      final dbFile = File(p.join(tempDir.path, 'song_catalog.sqlite'));
      var database = SongCatalogDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      var store = DriftSongCatalogStore(database);
      var localRepository = LocalFirstSongRepository(store);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
        await database.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await client.auth.signOut();
      await client.auth.signInWithPassword(
        email: 'demo@lyrica.local',
        password: 'LyricaDemo123!',
      );
      final userId = client.auth.currentSession!.user.id;

      final onlineController = SongCatalogController(
        store: store,
        remoteRepository: SupabaseSongRepository(client),
        authSessionReader: _currentSessionReader(client),
        organizationReader: _organizationReader(client),
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      await onlineController.refreshCatalog();

      await database.close();
      database = SongCatalogDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      store = DriftSongCatalogStore(database);
      localRepository = LocalFirstSongRepository(store);

      final cachedSongs = await localRepository.listSongs(
        userId: userId,
        organizationId: '11111111-1111-1111-1111-111111111111',
      );
      expect(
        cachedSongs.map((song) => song.title).toList(growable: false),
        unorderedEquals(const [
          'A forrásnál',
          'A mi Istenünk (Leborulok előtted)',
          'Egy út',
        ]),
      );

      final offlineController = SongCatalogController(
        store: store,
        remoteRepository: _ThrowingSongRepository(
          const SocketException('offline'),
        ),
        authSessionReader: _currentSessionReader(client),
        organizationReader: () async => throw const SocketException('offline'),
        sessionVerifier: () async =>
            CatalogSessionStatus.unverifiableDueToConnectivity,
      );

      await offlineController.refreshCatalog();

      expect(
        offlineController.state.connectionStatus,
        CatalogConnectionStatus.offlineCached,
      );
      expect(
        offlineController.state.refreshStatus,
        CatalogRefreshStatus.failed,
      );
      expect(offlineController.state.hasCachedCatalog, isTrue);

      final cachedSource = await localRepository.getSongSource(
        userId: userId,
        organizationId: '11111111-1111-1111-1111-111111111111',
        songId: '33333333-3333-3333-3333-333333333335',
      );
      expect(cachedSource.source, contains('{title:Egy út}'));
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'explicit sign-out removes cached authenticated access immediately',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final localRepository = LocalFirstSongRepository(store);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
        await database.close();
      });

      await client.auth.signOut();
      await client.auth.signInWithPassword(
        email: 'demo@lyrica.local',
        password: 'LyricaDemo123!',
      );
      final userId = client.auth.currentSession!.user.id;

      final controller = SongCatalogController(
        store: store,
        remoteRepository: SupabaseSongRepository(client),
        authSessionReader: _currentSessionReader(client),
        organizationReader: _organizationReader(client),
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );

      await controller.refreshCatalog();
      await controller.handleExplicitSignOut();
      await client.auth.signOut();

      expect(
        await localRepository.listSongs(
          userId: userId,
          organizationId: '11111111-1111-1111-1111-111111111111',
        ),
        isEmpty,
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'successful refresh hard replaces the previous cached snapshot',
    () async {
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final localRepository = LocalFirstSongRepository(store);

      addTearDown(database.close);

      final initialController = SongCatalogController(
        store: store,
        remoteRepository: _StaticSongRepository(
          songs: const [
            SongSummary(id: 'song-1', title: 'Alpha'),
            SongSummary(id: 'song-2', title: 'Beta'),
          ],
          sources: const {
            'song-1': SongSource(id: 'song-1', source: '{title: Alpha}'),
            'song-2': SongSource(id: 'song-2', source: '{title: Beta}'),
          },
        ),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyrica.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );
      await initialController.refreshCatalog();

      final replacementController = SongCatalogController(
        store: store,
        remoteRepository: _StaticSongRepository(
          songs: const [SongSummary(id: 'song-2', title: 'Beta')],
          sources: const {
            'song-2': SongSource(id: 'song-2', source: '{title: Beta}'),
          },
        ),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyrica.local'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
      );
      await replacementController.refreshCatalog();

      expect(
        await localRepository.listSongs(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        const [SongSummary(id: 'song-2', title: 'Beta')],
      );
      await expectLater(
        () => localRepository.getSongSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        ),
        throwsA(isA<Exception>()),
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );
}

AppAuthSessionReader _currentSessionReader(SupabaseClient client) {
  return () {
    final session = client.auth.currentSession;
    final email = session?.user.email;
    if (session == null || email == null || email.isEmpty) {
      return null;
    }

    return AppAuthSession(userId: session.user.id, email: email);
  };
}

ActiveOrganizationReader _organizationReader(SupabaseClient client) {
  return () async {
    final response = await client.rpc('current_organization_ids');
    if (response is! List || response.isEmpty) {
      return null;
    }

    return response.first as String;
  };
}

class _ThrowingSongRepository implements SongRepository {
  const _ThrowingSongRepository(this._error);

  final Object _error;

  @override
  Future<List<SongSummary>> listSongs() async => throw _error;

  @override
  Future<SongSource> getSongSource(String id) async => throw _error;
}

class _StaticSongRepository implements SongRepository {
  const _StaticSongRepository({required this.songs, required this.sources});

  final List<SongSummary> songs;
  final Map<String, SongSource> sources;

  @override
  Future<List<SongSummary>> listSongs() async => songs;

  @override
  Future<SongSource> getSongSource(String id) async => sources[id]!;
}

class _PassthroughHttpOverrides extends HttpOverrides {}
