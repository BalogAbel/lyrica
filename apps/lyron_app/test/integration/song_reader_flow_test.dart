import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'boots into the signed-in song list, opens the reader, and redirects to sign in when the session expires',
    (tester) async {
      final authRepository = _StreamingAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        ),
      );
      final songRepository = _StaticSongRepository(
        summaries: const [SongSummary(id: 'egy_ut', title: 'Egy út')],
        sources: const {
          'egy_ut': SongSource(
            id: 'egy_ut',
            source:
                '{title:Egy út}\n'
                '{subtitle:One Way}\n'
                '{key:B}\n'
                '{comment:<Verse 1>}\n'
                '[B] Leteszem az eletem\n',
          ),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepository),
            songLibraryRepositoryProvider.overrideWithValue(songRepository),
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
          ],
          child: LyronApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lyron Chords'), findsOneWidget);
      expect(find.text('Egy út'), findsOneWidget);

      await tester.tap(find.text('Egy út'));
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(find.text('Egy út'), findsWidgets);
      expect(find.text('One Way'), findsOneWidget);
      expect(find.text('Key: B'), findsOneWidget);
      expect(find.text('Verse 1'), findsOneWidget);
      expect(find.textContaining('Leteszem'), findsWidgets);

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text('Song reader'), findsNothing);
      expect(find.text('Egy út'), findsOneWidget);

      await tester.tap(find.text('Egy út'));
      await tester.pumpAndSettle();

      authRepository.expireSession();
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(
        find.text('Your session expired. Please sign in again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'boots directly into the reader and falls back to the song list on back',
    (tester) async {
      final authRepository = _StreamingAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        ),
      );
      final authController = AppAuthController(authRepository);
      await authController.restoreSession();
      addTearDown(authController.dispose);

      final songRepository = _StaticSongRepository(
        summaries: const [SongSummary(id: 'egy_ut', title: 'Egy út')],
        sources: const {
          'egy_ut': SongSource(
            id: 'egy_ut',
            source:
                '{title:Egy út}\n'
                '{subtitle:One Way}\n'
                '{key:B}\n'
                '{comment:<Verse 1>}\n'
                '[B] Leteszem az eletem\n',
          ),
        },
      );
      final router = createAppRouter(
        authController: authController,
        refreshListenable: authController,
        initialLocation: '/songs/egy_ut',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepository),
            appAuthControllerProvider.overrideWithValue(authController),
            appAuthListenableProvider.overrideWithValue(authController),
            songLibraryRepositoryProvider.overrideWithValue(songRepository),
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
          ],
          child: LyronApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(find.text('One Way'), findsOneWidget);

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text('Song reader'), findsNothing);
      expect(find.text('Egy út'), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isFalse);
      expect(find.text('Song reader'), findsNothing);
      expect(find.text('Egy út'), findsOneWidget);
    },
  );
}

class _StreamingAuthRepository implements AuthRepository {
  _StreamingAuthRepository({this.restoredSession});

  final AppAuthSession? restoredSession;
  final _controller = StreamController<AppAuthSession?>.broadcast();

  void expireSession() {
    _controller.add(null);
  }

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final session = AppAuthSession(userId: 'user-1', email: email);
    _controller.add(session);
    return session;
  }

  @override
  Future<void> signOut() async {
    _controller.add(null);
  }
}

class _StaticSongRepository implements SongCatalogReadRepository {
  const _StaticSongRepository({required this.summaries, required this.sources});

  final List<SongSummary> summaries;
  final Map<String, SongSource> sources;

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async => summaries;

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => sources[songId]!;
}
