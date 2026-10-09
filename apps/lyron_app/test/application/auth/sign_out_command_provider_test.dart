import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late PlanningLocalDatabase planningDatabase;
  late SongCatalogDatabase songDatabase;
  late List<String> events;
  late AppAuthController authController;
  late StreamController<AppAuthSession?> sessions;

  setUp(() async {
    planningDatabase = PlanningLocalDatabase.inMemory();
    addTearDown(planningDatabase.close);
    songDatabase = SongCatalogDatabase.inMemory();
    addTearDown(songDatabase.close);
    events = [];
    sessions = StreamController<AppAuthSession?>.broadcast();
    addTearDown(sessions.close);
    authController = AppAuthController(
      _SignedInAuthRepository(events, sessions.stream),
    );
    await authController.restoreSession();
  });

  test('the command counts the current user\'s pending work in every '
      'organization and cancelling leaves the user signed in', () async {
    await planningDatabase
        .into(planningDatabase.cachedPlanningMutations)
        .insert(
          CachedPlanningMutationsCompanion.insert(
            userId: 'user-1',
            organizationId: 'org-without-context',
            aggregateType: 'plan',
            aggregateId: 'plan-edit',
            mutationKind: PlanningMutationKind.planEdit.value,
            syncStatus: PlanningMutationSyncStatus.pending.value,
            orderKey: 1,
            updatedAt: DateTime.utc(2026, 10, 7),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
      ],
    );
    addTearDown(container.dispose);

    final asked = <int?>[];
    final outcome = await container
        .read(signOutCommandProvider)
        .run(
          confirmDiscard: (count) async {
            asked.add(count);
            return false;
          },
        );

    expect(outcome, SignOutOutcome.cancelled);
    expect(asked, [1]);
    expect(authController.state.status, AppAuthStatus.signedIn);
  });

  test('the sign-out sequence holds the catalog controller until it ends '
      '(SO1)', () async {
    final catalogGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
        songCatalogControllerProvider.overrideWith((ref) {
          events.add('catalog-created');
          ref.onDispose(() => events.add('catalog-disposed'));
          return _GatedSongCatalogController(songDatabase, events, catalogGate);
        }),
        planningSyncControllerProvider.overrideWith(
          (ref) => _RecordingPlanningSyncController(events),
        ),
      ],
    );
    addTearDown(container.dispose);

    // No pending work: the run signs out without asking.
    final run = container
        .read(signOutCommandProvider)
        .run(confirmDiscard: (_) async => true);
    await pumpEventQueue();
    expect(
      events,
      ['catalog-created', 'catalog-sign-out'],
      reason:
          'nothing else listens to the catalog controller; the command '
          'must hold it while its sign-out runs',
    );

    catalogGate.complete();
    expect(await run, SignOutOutcome.signedOut);
    await pumpEventQueue();
    expect(events, [
      'catalog-created',
      'catalog-sign-out',
      'planning-sign-out',
      'auth-sign-out',
      'catalog-disposed',
    ]);
  });

  test('a user switch during the catalog purge stops the sequence: no '
      'planning purge, no sign-out, the new user stays signed in '
      '(SO6, AC12)', () async {
    final catalogGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
        songCatalogControllerProvider.overrideWith((ref) {
          events.add('catalog-created');
          ref.onDispose(() => events.add('catalog-disposed'));
          return _GatedSongCatalogController(songDatabase, events, catalogGate);
        }),
        planningSyncControllerProvider.overrideWith(
          (ref) => _RecordingPlanningSyncController(events),
        ),
      ],
    );
    addTearDown(container.dispose);

    // No pending work for user-1: the run signs out without asking.
    final run = container
        .read(signOutCommandProvider)
        .run(confirmDiscard: (_) async => true);
    await pumpEventQueue();
    expect(events, ['catalog-created', 'catalog-sign-out']);

    // user-2's session lands while the catalog purge of user-1 is held.
    sessions.add(
      const AppAuthSession(userId: 'user-2', email: 'user2@example.com'),
    );
    await pumpEventQueue();
    expect(authController.state.currentUserId, 'user-2');

    catalogGate.complete();
    expect(await run, SignOutOutcome.superseded);
    await pumpEventQueue();
    expect(events, ['catalog-created', 'catalog-sign-out', 'catalog-disposed']);
    expect(authController.state.status, AppAuthStatus.signedIn);
    expect(authController.state.currentUserId, 'user-2');
  });

  test('a user switch during the planning purge stops before the auth '
      'sign-out: the new user stays signed in (SO6, AC12)', () async {
    final planningGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
        songCatalogDatabaseProvider.overrideWithValue(songDatabase),
        songCatalogControllerProvider.overrideWith((ref) {
          events.add('catalog-created');
          ref.onDispose(() => events.add('catalog-disposed'));
          return _GatedSongCatalogController(
            songDatabase,
            events,
            Completer<void>()..complete(),
          );
        }),
        planningSyncControllerProvider.overrideWith(
          (ref) => _RecordingPlanningSyncController(events, gate: planningGate),
        ),
      ],
    );
    addTearDown(container.dispose);

    final run = container
        .read(signOutCommandProvider)
        .run(confirmDiscard: (_) async => true);
    await pumpEventQueue();
    expect(events, [
      'catalog-created',
      'catalog-sign-out',
      'planning-sign-out',
    ]);

    // user-2's session lands while the planning purge of user-1 is held.
    sessions.add(
      const AppAuthSession(userId: 'user-2', email: 'user2@example.com'),
    );
    await pumpEventQueue();
    expect(authController.state.currentUserId, 'user-2');

    planningGate.complete();
    expect(await run, SignOutOutcome.superseded);
    await pumpEventQueue();
    expect(events, [
      'catalog-created',
      'catalog-sign-out',
      'planning-sign-out',
      'catalog-disposed',
    ]);
    expect(events, isNot(contains('auth-sign-out')));
    expect(authController.state.status, AppAuthStatus.signedIn);
    expect(authController.state.currentUserId, 'user-2');
  });
}

class _SignedInAuthRepository implements AuthRepository {
  _SignedInAuthRepository(this.events, this.sessions);

  final List<String> events;
  final Stream<AppAuthSession?> sessions;

  @override
  Future<AppAuthSession?> restoreSession() async {
    return const AppAuthSession(userId: 'user-1', email: 'user@example.com');
  }

  @override
  Stream<AppAuthSession?> watchSession() => sessions;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {
    events.add('auth-sign-out');
  }

  @override
  Future<void> deleteAccount() async {}
}

class _GatedSongCatalogController extends SongCatalogController {
  _GatedSongCatalogController(
    SongCatalogDatabase database,
    this.events,
    this.gate,
  ) : super(
        onImplausibleEmptySnapshot:
            ({required userId, required organizationId}) async {},
        store: DriftSongCatalogStore(database),
        localDataLifecycle: _noopLifecycle(database),
        remoteRepository: _NoopSongRepository(),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'user@example.com'),
        organizationReader: () async => 'org-1',
        sessionVerifier: () async => CatalogSessionStatus.verified,
        foregroundState: const _BackgroundState(),
      );

  final List<String> events;
  final Completer<void> gate;

  @override
  Future<void> handleExplicitSignOut() async {
    events.add('catalog-sign-out');
    await gate.future;
  }
}

class _RecordingPlanningSyncController extends PlanningSyncController {
  _RecordingPlanningSyncController(this.events, {this.gate})
    : super(
        localStore: () => _NoopPlanningLocalStore(),
        localDataLifecycle: _noopLifecycle(null),
        remoteRepository: () => _NoopPlanningRemoteRepository(),
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'user@example.com'),
      );

  final List<String> events;
  final Completer<void>? gate;

  @override
  Future<void> handleExplicitSignOut() async {
    events.add('planning-sign-out');
    await gate?.future;
  }
}

// Both controllers override handleExplicitSignOut, so none of these
// dependencies is ever invoked.
LocalDataLifecycle _noopLifecycle(SongCatalogDatabase? database) {
  return LocalDataLifecycle(
    songCatalogStore: database == null
        ? _NoopSongCatalogStore()
        : DriftSongCatalogStore(database),
    planningLocalStore: _NoopPlanningLocalStore(),
    identityStore: _NoopLastKnownIdentityStore(),
    noteLastKnownIdentity: (_) {},
    eventsRecorder: _NoopLocalDataEventsRecorder(),
  );
}

class _BackgroundState implements AppForegroundState {
  const _BackgroundState();

  @override
  bool get isForeground => false;

  @override
  Stream<bool> watchForeground() => const Stream<bool>.empty();
}

class _NoopSongRepository implements SongRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSongCatalogStore implements SongCatalogStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopPlanningLocalStore implements PlanningLocalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopPlanningRemoteRepository implements PlanningRemoteRefreshRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLastKnownIdentityStore implements LastKnownIdentityStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
