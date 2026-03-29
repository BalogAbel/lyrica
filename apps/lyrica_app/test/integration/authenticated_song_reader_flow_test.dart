import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyrica_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _serviceRoleKey = String.fromEnvironment('SERVICE_ROLE_KEY');
const _demoOrganizationId = '11111111-1111-1111-1111-111111111111';
const _manualRefreshSongId = '33333333-3333-3333-3333-333333333335';

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
    'authenticates against local Supabase and reads only scoped songs',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final repository = SupabaseSongRepository(client);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
      });

      await client.auth.signOut();
      final authResponse = await client.auth.signInWithPassword(
        email: 'demo@lyrica.local',
        password: 'LyricaDemo123!',
      );

      expect(authResponse.session, isNotNull);
      expect(client.auth.currentSession, isNotNull);

      final songs = await repository.listSongs();
      expect(
        songs.map((song) => song.title).toList(growable: false),
        unorderedEquals(const [
          'A forrásnál',
          'A mi Istenünk (Leborulok előtted)',
          'Egy út',
        ]),
      );
      expect(songs, hasLength(3));

      final source = await repository.getSongSource(
        '33333333-3333-3333-3333-333333333335',
      );
      expect(source.id, '33333333-3333-3333-3333-333333333335');
      expect(source.source, contains('{title:Egy út}'));
      expect(source.source, contains('{subtitle:One Way}'));

      await expectLater(
        () => repository.getSongSource('33333333-3333-3333-3333-333333333336'),
        throwsA(isA<SongNotFoundException>()),
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'manual refresh updates the active catalog after backend changes',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final serviceRoleClient = SupabaseClient(config.url, _serviceRoleKey);
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final localRepository = LocalFirstSongRepository(store);

      addTearDown(() async {
        await _restoreSong(serviceRoleClient);
        await client.auth.signOut();
        await client.dispose();
        await serviceRoleClient.dispose();
        await database.close();
      });

      await _signInDemoUser(client);
      final controller = SongCatalogController(
        store: store,
        remoteRepository: SupabaseSongRepository(client),
        authSessionReader: _currentSessionReader(client),
        organizationReader: _organizationReader(client),
        sessionVerifier: () async => CatalogSessionStatus.verified,
        foregroundState: const _StaticForegroundState(isForeground: false),
      );
      addTearDown(controller.dispose);

      await controller.refreshCatalog();
      await _captureOriginalSong(serviceRoleClient);
      await _updateSong(
        serviceRoleClient,
        title: 'Egy út (Manual Refresh)',
        chordproSource: '{title:Egy út (Manual Refresh)}\n{subtitle:Manual}\n',
      );

      await controller.refreshCatalog();

      final songs = await localRepository.listSongs(
        userId: client.auth.currentSession!.user.id,
        organizationId: _demoOrganizationId,
      );
      expect(
        songs.any((song) => song.title == 'Egy út (Manual Refresh)'),
        isTrue,
      );

      final source = await localRepository.getSongSource(
        userId: client.auth.currentSession!.user.id,
        organizationId: _demoOrganizationId,
        songId: _manualRefreshSongId,
      );
      expect(source.source, contains('{title:Egy út (Manual Refresh)}'));
    },
    skip:
        _supabaseUrl.isEmpty ||
        _supabaseAnonKey.isEmpty ||
        _serviceRoleKey.isEmpty,
  );

  test(
    'periodic refresh updates the active catalog after backend changes',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final serviceRoleClient = SupabaseClient(config.url, _serviceRoleKey);
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);
      final localRepository = LocalFirstSongRepository(store);

      addTearDown(() async {
        await _restoreSong(serviceRoleClient);
        await client.auth.signOut();
        await client.dispose();
        await serviceRoleClient.dispose();
        await database.close();
      });

      await _signInDemoUser(client);
      final controller = SongCatalogController(
        store: store,
        remoteRepository: SupabaseSongRepository(client),
        authSessionReader: _currentSessionReader(client),
        organizationReader: _organizationReader(client),
        sessionVerifier: () async => CatalogSessionStatus.verified,
        foregroundState: const _StaticForegroundState(isForeground: true),
        refreshInterval: const Duration(milliseconds: 25),
      );
      addTearDown(controller.dispose);

      await controller.refreshCatalog();
      await _captureOriginalSong(serviceRoleClient);
      await _updateSong(
        serviceRoleClient,
        title: 'Egy út (Periodic Refresh)',
        chordproSource:
            '{title:Egy út (Periodic Refresh)}\n{subtitle:Periodic}\n',
      );

      await _eventually(() async {
        final songs = await localRepository.listSongs(
          userId: client.auth.currentSession!.user.id,
          organizationId: _demoOrganizationId,
        );
        return songs.any((song) => song.title == 'Egy út (Periodic Refresh)');
      });

      final source = await localRepository.getSongSource(
        userId: client.auth.currentSession!.user.id,
        organizationId: _demoOrganizationId,
        songId: _manualRefreshSongId,
      );
      expect(source.source, contains('{title:Egy út (Periodic Refresh)}'));
    },
    skip:
        _supabaseUrl.isEmpty ||
        _supabaseAnonKey.isEmpty ||
        _serviceRoleKey.isEmpty,
  );
}

class _PassthroughHttpOverrides extends HttpOverrides {}

Map<String, dynamic>? _originalSongRow;

Future<void> _signInDemoUser(SupabaseClient client) async {
  await client.auth.signOut();
  final authResponse = await client.auth.signInWithPassword(
    email: 'demo@lyrica.local',
    password: 'LyricaDemo123!',
  );
  expect(authResponse.session, isNotNull);
}

Future<void> _captureOriginalSong(SupabaseClient serviceRoleClient) async {
  _originalSongRow ??= await serviceRoleClient
      .from('songs')
      .select('id, title, chordpro_source')
      .eq('id', _manualRefreshSongId)
      .single();
}

Future<void> _restoreSong(SupabaseClient serviceRoleClient) async {
  final originalSongRow = _originalSongRow;
  if (originalSongRow == null) {
    return;
  }

  await serviceRoleClient
      .from('songs')
      .update({
        'title': originalSongRow['title'],
        'chordpro_source': originalSongRow['chordpro_source'],
      })
      .eq('id', _manualRefreshSongId);
}

Future<void> _updateSong(
  SupabaseClient serviceRoleClient, {
  required String title,
  required String chordproSource,
}) {
  return serviceRoleClient
      .from('songs')
      .update({'title': title, 'chordpro_source': chordproSource})
      .eq('id', _manualRefreshSongId);
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

Future<void> _eventually(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }

    await Future<void>.delayed(step);
  }

  fail('Condition was not met within $timeout.');
}

class _StaticForegroundState implements AppForegroundState {
  const _StaticForegroundState({required this.isForeground});

  @override
  final bool isForeground;

  @override
  Stream<bool> watchForeground() => const Stream<bool>.empty();
}
