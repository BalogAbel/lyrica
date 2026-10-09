// Sign-out pending-work guard
// (docs/specs/2026-10-07-sign-out-pending-work-guard.md): an explicit
// sign-out must never delete the signing-out user's unsynced work without a
// warning, whichever sign-out control was used and whether or not a read
// context is established.
//
// The whole app runs: LyronApp with its real router, membership gate,
// AppAuthController, LocalDataLifecycle, purge listeners, the real gotrue
// client and Drift in-memory stores. Only the network is replaced: by default
// by an HTTP client that never answers (see offline_first_startup_gate_test.dart
// for why that is the one deterministic network shape under widget-test fake
// time). User A's identity is on file. Without a persisted session the app
// cold-starts into sessionExpired(A); with a persisted, still valid session
// it starts signedIn(A), and a sign-out then calls the backend through the
// replaced client (SO3, offline sign-out).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

const _userA = 'user-a';
const _orgA = 'org-a';

/// Counts the backend session revocations (`/auth/v1/logout`), so a test can
/// prove a sign-out really sent its revocation: without the count, a skipped
/// revocation would keep the offline tests green.
abstract class _CountingHttpClient extends http.BaseClient {
  int logoutRequests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path == '/auth/v1/logout') {
      logoutRequests += 1;
    }
    return respond(request);
  }

  Future<http.StreamedResponse> respond(http.BaseRequest request);
}

class _HangingHttpClient extends _CountingHttpClient {
  @override
  Future<http.StreamedResponse> respond(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

/// The backend is unreachable: every request to `/auth/v1/` (including
/// gotrue's `/auth/v1/logout`, the backend revocation of a sign-out) fails at
/// once, the way an offline device's requests do. gotrue turns it into an
/// AuthRetryableFetchException without a status code. PostgREST RPCs and
/// writes (anything but GET and HEAD) fail the same way: they are not
/// retried, and the signedIn identity resolution awaits the membership RPC
/// (`current_organization_ids`), so leaving it open would also keep the
/// sign-out's identity clear queued behind it. Only GET and HEAD stay open
/// like [_HangingHttpClient]: PostgREST retries a failed GET with real
/// back-off timers, which would outlive the test under widget-test fake time.
class _FailingHttpClient extends _CountingHttpClient {
  @override
  Future<http.StreamedResponse> respond(http.BaseRequest request) {
    final retriedByPostgrest =
        request.method == 'GET' || request.method == 'HEAD';
    if (request.url.path.startsWith('/auth/v1/') || !retriedByPostgrest) {
      return Future.error(http.ClientException('network is unreachable'));
    }
    return Completer<http.StreamedResponse>().future;
  }
}

String _jwt({required int expiresAtSeconds}) {
  String encode(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': _userA, 'exp': expiresAtSeconds})}.signature';
}

/// A's persisted session with an access token valid for another hour, so
/// the cold start needs no token refresh and lands on signedIn(A).
String _validSessionJsonForA() {
  final expiresAt = DateTime.now().add(const Duration(hours: 1));
  return jsonEncode({
    'access_token': _jwt(
      expiresAtSeconds: expiresAt.millisecondsSinceEpoch ~/ 1000,
    ),
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
    'refresh_token': 'refresh-a',
    'user': {
      'id': _userA,
      'aud': 'authenticated',
      'email': 'a@lyron.local',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': DateTime.utc(2026, 10, 1).toIso8601String(),
    },
  });
}

class _Fixture {
  _Fixture({http.Client? httpClient})
    : songDatabase = SongCatalogDatabase.inMemory(),
      planningDatabase = PlanningLocalDatabase.inMemory(),
      identityDatabase = LastKnownIdentityDatabase.inMemory(),
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: httpClient ?? _HangingHttpClient(),
      );

  final SongCatalogDatabase songDatabase;
  final PlanningLocalDatabase planningDatabase;
  final LastKnownIdentityDatabase identityDatabase;
  final SupabaseClient client;

  /// A's pending planning mutation is always seeded: it is the unsynced
  /// work at stake. [cachedSongs] and [cachedProjection] decide whether a
  /// catalog and a planning read context can be established for A;
  /// [pendingSongForA] adds a pending song create of A's;
  /// [persistedSessionForA] starts the app signedIn(A).
  Future<void> seed(
    WidgetTester tester, {
    required bool cachedSongs,
    required bool cachedProjection,
    bool pendingSongForA = false,
    bool persistedSessionForA = false,
  }) async {
    await tester.runAsync(() async {
      if (pendingSongForA) {
        await songDatabase
            .into(songDatabase.cachedCatalogSongMutations)
            .insert(
              CachedCatalogSongMutationsCompanion.insert(
                userId: _userA,
                organizationId: _orgA,
                songId: 'song-a-draft',
                slug: 'a-draft',
                title: 'A draft',
                source: '{title:A draft}\n',
                version: 0,
                syncStatus: SongSyncStatus.pendingCreate.value,
              ),
            );
      }
      if (persistedSessionForA) {
        await client.auth.setInitialSession(_validSessionJsonForA());
      }
      if (cachedSongs) {
        await DriftSongCatalogStore(songDatabase).replaceActiveSnapshot(
          userId: _userA,
          organizationId: _orgA,
          summaries: const [
            SongSummary(id: 'song-a', slug: 'a-song', title: 'A song'),
          ],
          sources: const [SongSource(id: 'song-a', source: '{title:A song}\n')],
          refreshedAt: DateTime.utc(2026, 10, 1),
        );
      }
      if (cachedProjection) {
        await DriftPlanningLocalStore(planningDatabase).replaceActiveProjection(
          userId: _userA,
          organizationId: _orgA,
          plans: [
            CachedPlanRecord(
              id: 'plan-a',
              name: 'A plan',
              description: null,
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          ],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 10, 1),
        );
      }
      await planningDatabase
          .into(planningDatabase.cachedPlanningMutations)
          .insert(
            CachedPlanningMutationsCompanion.insert(
              userId: _userA,
              organizationId: _orgA,
              aggregateType: 'plan',
              aggregateId: 'plan-a-edit',
              mutationKind: PlanningMutationKind.planEdit.value,
              syncStatus: PlanningMutationSyncStatus.pending.value,
              orderKey: 1,
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          );
      await DriftLastKnownIdentityStore(identityDatabase).write(
        const LastKnownIdentity(
          userId: _userA,
          email: 'a@lyron.local',
          organizationId: _orgA,
        ),
      );
    });
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      isolatedSongCatalogProviderScope(
        songCatalogDatabase: songDatabase,
        planningLocalDatabase: planningDatabase,
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          lastKnownIdentityDatabaseProvider.overrideWithValue(identityDatabase),
        ],
        child: LyronApp(),
      ),
    );
    await pumpFrames(tester);
  }

  /// One second of fake time: far below gotrue's 10 s refresh budget, so
  /// nothing asserted here may depend on the network.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LyronApp)));

  GoRouter router(WidgetTester tester) =>
      container(tester).read(appRouterProvider);

  AppAuthStatus authStatus(WidgetTester tester) =>
      container(tester).read(appAuthControllerProvider).state.status;

  Future<int> pendingPlanningMutationCount(WidgetTester tester) async {
    final count = await tester.runAsync(() async {
      final rows = await (planningDatabase.select(
        planningDatabase.cachedPlanningMutations,
      )..where((table) => table.userId.equals(_userA))).get();
      return rows.length;
    });
    return count!;
  }

  Future<int> pendingSongMutationCount(WidgetTester tester) async {
    final count = await tester.runAsync(() async {
      final rows = await (songDatabase.select(
        songDatabase.cachedCatalogSongMutations,
      )..where((table) => table.userId.equals(_userA))).get();
      return rows.length;
    });
    return count!;
  }

  Future<String?> identityUserId(WidgetTester tester) async {
    final identity = await tester.runAsync(
      () => DriftLastKnownIdentityStore(identityDatabase).read(),
    );
    return identity?.userId;
  }

  /// The 2026-08-19 product decision stands: a confirmed explicit sign-out
  /// still deletes the signing-out user's local data and identity row.
  Future<void> confirmDiscardAndExpectDeleted(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
    await pumpFrames(tester);
    expect(authStatus(tester), AppAuthStatus.signedOut);
    expect(await pendingPlanningMutationCount(tester), 0);
    expect(await pendingSongMutationCount(tester), 0);
    expect(await identityUserId(tester), isNull);
  }

  Future<void> tearDown(WidgetTester tester) async {
    // Never dispose the client here: dispose completes the hung requests
    // with an error, and the app code waiting on them would resume after its
    // providers are gone.
    client.auth.stopAutoRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await songDatabase.close();
      await planningDatabase.close();
      await identityDatabase.close();
    });
  }
}

void main() {
  suppressDriftMultipleDatabaseWarnings();

  // Red until Task 6 (SO1); spec 2026-10-07 sign-out pending-work guard.
  testWidgets(
    'Account > Sign out with pending work warns before deleting '
    'it (a)',
    skip: true,
    (tester) async {
      final fixture = _Fixture();
      await fixture.seed(
        tester,
        cachedSongs: true,
        cachedProjection: true,
        pendingSongForA: true,
      );
      await fixture.pumpApp(tester);
      // Precondition: sessionExpired(A), A's own catalog on screen.
      expect(fixture.authStatus(tester), AppAuthStatus.sessionExpired);
      expect(find.text('A song'), findsOneWidget);

      fixture.router(tester).go(AppRoutes.account.path);
      await fixture.pumpFrames(tester);
      await tester.tap(find.text(AppStrings.signOutAction));
      await fixture.pumpFrames(tester);

      final observed = (
        warningShown: find
            .text(AppStrings.unsyncedSignOutTitle)
            .evaluate()
            .isNotEmpty,
        status: fixture.authStatus(tester),
        pendingWorkOfA: await fixture.pendingPlanningMutationCount(tester),
        pendingSongWorkOfA: await fixture.pendingSongMutationCount(tester),
      );
      expect(
        observed,
        (
          warningShown: true,
          status: AppAuthStatus.sessionExpired,
          pendingWorkOfA: 1,
          pendingSongWorkOfA: 1,
        ),
        reason:
            'the Account sign-out must warn about A\'s unsynced work and '
            'delete nothing before the user confirms',
      );

      await fixture.confirmDiscardAndExpectDeleted(tester);

      await fixture.tearDown(tester);
    },
  );

  // Red until Task 5 (SO2); spec 2026-10-07 sign-out pending-work guard.
  testWidgets(
    'song list > Sign out in sessionExpired with no read context '
    'and pending work warns before deleting it (b)',
    skip: true,
    (tester) async {
      // A has pending work but neither cached songs nor a cached projection,
      // so no catalog and no planning context is ever established.
      final fixture = _Fixture();
      await fixture.seed(tester, cachedSongs: false, cachedProjection: false);
      await fixture.pumpApp(tester);
      expect(fixture.authStatus(tester), AppAuthStatus.sessionExpired);
      expect(
        fixture.container(tester).read(activeCatalogContextProvider),
        isNull,
      );
      expect(
        fixture.container(tester).read(planningSyncStateProvider).userId,
        isNull,
      );

      await tester.tap(find.byKey(const Key('song-list-overflow-menu')));
      await fixture.pumpFrames(tester);
      await tester.tap(find.text(AppStrings.signOutAction));
      await fixture.pumpFrames(tester);

      final observed = (
        warningShown: find
            .text(AppStrings.unsyncedSignOutTitle)
            .evaluate()
            .isNotEmpty,
        status: fixture.authStatus(tester),
        pendingWorkOfA: await fixture.pendingPlanningMutationCount(tester),
      );
      expect(
        observed,
        (
          warningShown: true,
          status: AppAuthStatus.sessionExpired,
          pendingWorkOfA: 1,
        ),
        reason:
            'the song-list sign-out must warn about A\'s unsynced work even '
            'without a read context, and delete nothing before the user '
            'confirms',
      );

      await fixture.confirmDiscardAndExpectDeleted(tester);

      await fixture.tearDown(tester);
    },
  );

  // Guard: the harness sees the existing warning. With a planning context
  // established, the song list's context-scoped check already warns today.
  testWidgets('song list > Sign out with a read context and pending work '
      'warns, and Cancel deletes nothing (guard)', (tester) async {
    final fixture = _Fixture();
    await fixture.seed(tester, cachedSongs: true, cachedProjection: true);
    await fixture.pumpApp(tester);
    expect(fixture.authStatus(tester), AppAuthStatus.sessionExpired);

    await tester.tap(find.byKey(const Key('song-list-overflow-menu')));
    await fixture.pumpFrames(tester);
    await tester.tap(find.text(AppStrings.signOutAction));
    await fixture.pumpFrames(tester);
    expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.songCancelAction));
    await fixture.pumpFrames(tester);
    expect(fixture.authStatus(tester), AppAuthStatus.sessionExpired);
    expect(await fixture.pendingPlanningMutationCount(tester), 1);

    await fixture.tearDown(tester);
  });

  // W3: gotrue drops the local session and emits signedOut before it calls
  // the backend, then rethrows that call's network failure (SO3).
  testWidgets(
    'offline: a confirmed sign-out on a failing network signs out locally, '
    'purges, and raises no unhandled error (SO3)',
    (tester) async {
      final httpClient = _FailingHttpClient();
      final fixture = _Fixture(httpClient: httpClient);
      await fixture.seed(
        tester,
        cachedSongs: true,
        cachedProjection: true,
        persistedSessionForA: true,
      );
      await fixture.pumpApp(tester);
      expect(fixture.authStatus(tester), AppAuthStatus.signedIn);

      await tester.tap(find.byKey(const Key('song-list-overflow-menu')));
      await fixture.pumpFrames(tester);
      await tester.tap(find.text(AppStrings.signOutAction));
      await fixture.pumpFrames(tester);
      expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);

      await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
      await fixture.pumpFrames(tester);

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the backend revocation\'s network failure after the local '
            'sign-out is not an error',
      );
      expect(fixture.authStatus(tester), AppAuthStatus.signedOut);
      expect(await fixture.pendingPlanningMutationCount(tester), 0);
      expect(await fixture.identityUserId(tester), isNull);
      expect(
        httpClient.logoutRequests,
        1,
        reason: 'the sign-out must still have sent its backend revocation',
      );

      await fixture.tearDown(tester);
    },
  );

  // W3, AC9: the outcome is signedOut and the command's lock is released at
  // the local sign-out, while the backend revocation fails or never answers.
  for (final failingNetwork in [true, false]) {
    testWidgets(
      failingNetwork
          ? 'offline (failing network): the command signs out and a second '
                'run is not held (SO3)'
          : 'offline (network that never answers): the command signs out '
                'and a second run is not held (SO3)',
      (tester) async {
        final _CountingHttpClient httpClient = failingNetwork
            ? _FailingHttpClient()
            : _HangingHttpClient();
        final fixture = _Fixture(httpClient: httpClient);
        await fixture.seed(
          tester,
          cachedSongs: true,
          cachedProjection: true,
          persistedSessionForA: true,
        );
        await fixture.pumpApp(tester);
        expect(fixture.authStatus(tester), AppAuthStatus.signedIn);

        final command = fixture.container(tester).read(signOutCommandProvider);
        final outcomes = <SignOutOutcome>[];
        unawaited(
          command.run(confirmDiscard: (_) async => true).then(outcomes.add),
        );
        await fixture.pumpFrames(tester);
        expect(outcomes, [SignOutOutcome.signedOut]);
        expect(fixture.authStatus(tester), AppAuthStatus.signedOut);
        expect(tester.takeException(), isNull);
        expect(
          httpClient.logoutRequests,
          1,
          reason: 'the sign-out must still have sent its backend revocation',
        );

        unawaited(
          command.run(confirmDiscard: (_) async => true).then(outcomes.add),
        );
        await fixture.pumpFrames(tester);
        expect(
          outcomes,
          [SignOutOutcome.signedOut, SignOutOutcome.signedOut],
          reason:
              'a second run must not wait for the first run\'s backend '
              'request',
        );
        expect(tester.takeException(), isNull);

        await fixture.tearDown(tester);
      },
    );
  }
}
