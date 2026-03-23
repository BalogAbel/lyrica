import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';
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
}

class _PassthroughHttpOverrides extends HttpOverrides {}
