import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

void main() {
  testWidgets(
    'shows auth bootstrap loading before session restoration completes',
    (tester) async {
      final completer = Completer<AppAuthSession?>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              _DelayedAuthRepository(completer.future),
            ),
          ],
          child: LyronApp(),
        ),
      );
      await tester.pump();

      expect(find.text('Restoring session...'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      completer.complete(null);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('boots into sign in through the shared app router', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_TestAuthRepository()),
        ],
        child: LyronApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lyron Chords'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('A forrásnál'), findsNothing);
    expect(find.text('A mi Istenünk (Leborulok előtted)'), findsNothing);
    expect(find.text('Egy út'), findsNothing);
  });

  testWidgets('explicit sign-out removes cached authenticated access', (
    tester,
  ) async {
    final authRepository = _SignedInAuthRepository();
    final database = SongCatalogDatabase.inMemory();
    final store = DriftSongCatalogStore(database);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          songCatalogDatabaseProvider.overrideWithValue(database),
          songCatalogStoreProvider.overrideWithValue(store),
          supabaseSongRepositoryProvider.overrideWithValue(
            SupabaseSongRepository.testing(
              listSongsRows: () async => [
                {'id': 'song-1', 'title': 'Egy út'},
              ],
              getSongRow: (id) async => {
                'id': id,
                'chordpro_source': '{title:Egy út}\n',
              },
            ),
          ),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => 'org-1',
          ),
          catalogSessionVerifierProvider.overrideWithValue(
            () async => CatalogSessionStatus.verified,
          ),
        ],
        child: LyronApp(),
      ),
    );
    addTearDown(database.close);

    await tester.pumpAndSettle();

    expect(find.text('Egy út'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(
      await store.readActiveSummaries(
        userId: 'user-1',
        organizationId: 'org-1',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'signing in again after explicit sign-out refreshes the catalog in the same app session',
    (tester) async {
      final authRepository = _InteractiveAuthRepository();
      final database = SongCatalogDatabase.inMemory();
      final store = DriftSongCatalogStore(database);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepository),
            songCatalogDatabaseProvider.overrideWithValue(database),
            songCatalogStoreProvider.overrideWithValue(store),
            supabaseSongRepositoryProvider.overrideWithValue(
              SupabaseSongRepository.testing(
                listSongsRows: () async => [
                  {'id': 'song-1', 'title': 'Egy út'},
                ],
                getSongRow: (id) async => {
                  'id': id,
                  'chordpro_source': '{title:Egy út}\n',
                },
              ),
            ),
            activeOrganizationReaderProvider.overrideWithValue(
              () async => 'org-1',
            ),
            catalogSessionVerifierProvider.overrideWithValue(
              () async => CatalogSessionStatus.verified,
            ),
          ],
          child: LyronApp(),
        ),
      );
      addTearDown(database.close);
      addTearDown(authRepository.dispose);

      await tester.pumpAndSettle();

      expect(find.text('Egy út'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Egy út'), findsOneWidget);
    },
  );
}

class _TestAuthRepository implements AuthRepository {
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

class _DelayedAuthRepository implements AuthRepository {
  _DelayedAuthRepository(this._restoreFuture);

  final Future<AppAuthSession?> _restoreFuture;

  @override
  Future<AppAuthSession?> restoreSession() => _restoreFuture;

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

class _InteractiveAuthRepository implements AuthRepository {
  _InteractiveAuthRepository()
    : _controller = StreamController<AppAuthSession?>.broadcast();

  final StreamController<AppAuthSession?> _controller;
  AppAuthSession? _session = const AppAuthSession(
    userId: 'user-1',
    email: 'demo@lyron.local',
  );

  @override
  Future<AppAuthSession?> restoreSession() async => _session;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final session = AppAuthSession(userId: 'user-1', email: email);
    _session = session;
    _controller.add(session);
    return session;
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _controller.add(null);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
