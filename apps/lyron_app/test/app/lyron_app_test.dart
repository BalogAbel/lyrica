import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';

import '../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  testWidgets(
    'shows auth bootstrap loading before session restoration completes',
    (tester) async {
      final completer = Completer<AppAuthSession?>();
      await tester.pumpWidget(
        _testProviderScope(
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
      _testProviderScope(
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
                {'id': 'song-1', 'slug': 'egy-ut', 'title': 'Egy út'},
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
          planningSyncControllerProvider.overrideWith(
            (ref) => _NoopPlanningSyncController(),
          ),
          hasUnsyncedPlanningMutationsProvider.overrideWith(
            (ref) async => false,
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
                  {'id': 'song-1', 'slug': 'egy-ut', 'title': 'Egy út'},
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
            planningSyncControllerProvider.overrideWith(
              (ref) => _NoopPlanningSyncController(),
            ),
            hasUnsyncedPlanningMutationsProvider.overrideWith(
              (ref) async => false,
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

ProviderScope _testProviderScope({
  required Widget child,
  List<Override> overrides = const [],
}) {
  final database = SongCatalogDatabase.inMemory();
  addTearDown(database.close);
  return ProviderScope(
    overrides: [
      songCatalogDatabaseProvider.overrideWithValue(database),
      ...overrides,
    ],
    child: child,
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

class _NoopPlanningSyncController extends PlanningSyncController {
  _NoopPlanningSyncController()
    : super(
        localStore: () => _NoopPlanningLocalStore(),
        remoteRepository: () => const _NoopPlanningRemoteRepository(),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      );

  @override
  Future<void> handleExplicitSignOut() async {}
}

class _NoopPlanningLocalStore implements PlanningLocalStore {
  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async => false;

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async => null;

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async => null;

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) async => null;

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async => null;

  Future<List<CachedPlanRecord>> readPlans({
    required String userId,
    required String organizationId,
  }) async => const [];

  Future<List<CachedSessionRecord>> readSessions({
    required String userId,
    required String organizationId,
  }) async => const [];

  Future<List<CachedSessionItemRecord>> readSessionItems({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;
}

class _NoopPlanningRemoteRepository implements PlanningRemoteRefreshRepository {
  const _NoopPlanningRemoteRepository();

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    return const PlanningSyncPayload(plans: [], sessions: [], items: []);
  }
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
