import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/planning_run_fixtures.dart';

/// F1 (docs/deferred/2026-10-22-content-version-ahead-of-content.md,
/// scheduled: S5b PR 2): a reconcile that lands after a newer pull for the
/// same context was stored writes the older accepted write over the newer
/// content, while the projection keeps the newer plan content version. The
/// projection then claims a content version it does not hold (I7). The race
/// predates S5b PR 1; the A -> B -> A path below is the extra way PR 1 reaches
/// it. These tests state the intended behavior and are skipped until the fix.
void main() {
  const skipReason =
      'F1, docs/deferred/2026-10-22-content-version-ahead-of-content.md '
      '(scheduled: S5b PR 2)';

  const context = PlanningMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  const readContext = ActivePlanningReadContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );

  late PlanningLocalDatabase db;
  late DriftPlanningLocalStore localStore;
  late DriftPlanningMutationStore store;
  late PlanningMutationReconciler reconciler;

  setUp(() async {
    db = PlanningLocalDatabase.inMemory();
    localStore = DriftPlanningLocalStore(db);
    store = DriftPlanningMutationStore(database: db, localStore: localStore);
    reconciler = PlanningMutationReconciler(localStore: () => localStore);
    await seedPlanningProjection(localStore, contentVersion: 3);
  });

  tearDown(() async {
    await db.close();
  });

  PlanningSyncController planningSyncFor(_ScriptedRefreshRemote remote) =>
      PlanningSyncController(
        localStore: () => localStore,
        localDataLifecycle: LocalDataLifecycle(
          songCatalogStore: _NoopSongCatalogStore(),
          planningLocalStore: localStore,
          identityStore: _NoopLastKnownIdentityStore(),
          noteLastKnownIdentity: (_) {},
          eventsRecorder: _NoopLocalDataEventsRecorder(),
        ),
        remoteRepository: () => remote,
        authSessionReader: () =>
            const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      );

  Future<void> recordRename() => store.recordSessionRename(
    context: context,
    draft: const PlanningSessionRenameMutationDraft(
      sessionId: 'session-1',
      planId: 'plan-1',
      name: 'Renamed',
      baseVersion: 2,
    ),
  );

  // W = own rename, accepted at session v3 / plan content version 4.
  // F = a foreign rename of the same session after W: session v4, content 5.
  Future<void> runWith({
    required bool Function() isActive,
    required PlanningSyncController planningSync,
  }) async {
    await recordRename();
    final remote = ScriptedPlanningRemote(
      (record) async =>
          record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4),
    );
    final controller = PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () => remote,
      // The after-write refresh fails (e.g. a transient error).
      refreshPlanning: (_) async => false,
      isRunContextActive: (_) => isActive(),
      reconcileAcceptedMutation: (ctx, record) async {
        // A pull for the same context, started after W (so it holds W and the
        // later foreign write F), stores right before this record's reconcile.
        await planningSync.refreshPlanning();
        await reconciler.reconcile(ctx, record);
      },
    );
    await controller.syncPendingMutations(readContext);
  }

  // Intended: the stored pull holds F (session v4, content version 5), so the
  // older accepted write W (session v3) must not overwrite it.
  Future<void> expectProjectionHoldsF() async {
    final detail = (await localStore.readPlanDetail(
      userId: 'user-1',
      organizationId: 'org-1',
      planId: 'plan-1',
    ))!;
    expect(detail.plan.contentVersion, 5);
    expect(detail.sessions.single.name, 'Foreign');
    expect(detail.sessions.single.version, 4);
  }

  test('a reconcile landing after a newer stored pull of the same context does '
      'not write the older accepted write over it (I7)', () async {
    final refreshRemote = _ScriptedRefreshRemote(
      _payload(sessionName: 'Foreign', sessionVersion: 4, contentVersion: 5),
    );
    final planningSync = planningSyncFor(refreshRemote);
    await planningSync.handleActiveContextChanged(readContext, refresh: false);

    await runWith(isActive: () => true, planningSync: planningSync);

    await expectProjectionHoldsF();
  }, skip: skipReason);

  test(
    'a context that moves to B at C3 and is back in A at C5 skips the refresh, '
    'reconciles, and still does not overwrite a newer stored pull (I7)',
    () async {
      final refreshRemote = _ScriptedRefreshRemote(
        _payload(sessionName: 'Foreign', sessionVersion: 4, contentVersion: 5),
      );
      final planningSync = planningSyncFor(refreshRemote);
      await planningSync.handleActiveContextChanged(
        readContext,
        refresh: false,
      );
      var guardCalls = 0;

      // Guard calls in order: C1, C2, C3 (moved: A -> B), C5 (back: B -> A).
      await runWith(
        isActive: () {
          guardCalls += 1;
          return guardCalls != 3;
        },
        planningSync: planningSync,
      );

      expect(guardCalls, 4);
      await expectProjectionHoldsF();
    },
    skip: skipReason,
  );
}

PlanningSyncPayload _payload({
  required String sessionName,
  required int sessionVersion,
  required int contentVersion,
}) => PlanningSyncPayload(
  plans: [
    PlanningSyncPlan(
      id: 'plan-1',
      slug: 'plan-1',
      name: 'Plan',
      description: null,
      scheduledFor: null,
      updatedAt: DateTime.utc(2026),
      version: 2,
      contentVersion: contentVersion,
    ),
  ],
  sessions: [
    PlanningSyncSession(
      id: 'session-1',
      planId: 'plan-1',
      slug: 'session-1',
      position: 1,
      name: sessionName,
      version: sessionVersion,
    ),
  ],
  items: const [
    PlanningSyncSessionItem(
      id: 'item-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      position: 1,
      songId: 'song-1',
      songTitle: 'Song',
      version: 1,
    ),
  ],
);

class _ScriptedRefreshRemote implements PlanningRemoteRefreshRepository {
  _ScriptedRefreshRemote(this._payload);

  final PlanningSyncPayload _payload;

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
    bool Function()? shouldContinue,
  }) async => _payload;
}

class _NoopSongCatalogStore implements SongCatalogStore {
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
