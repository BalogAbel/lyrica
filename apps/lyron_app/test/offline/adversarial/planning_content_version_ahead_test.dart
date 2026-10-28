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

/// F1 (spec decision F1, ADR-038 2026-10-21 amendment item 3): a
/// reconcile that lands after a newer pull for the same context was stored
/// must not write the older accepted write over the newer content while the
/// projection keeps the newer plan content version (I7). The race predates
/// S5b PR 1; the A -> B -> A path below is the extra way PR 1 reaches it.
/// These are the acceptance tests of decision F1 (spec
/// docs/specs/2026-10-21-planning-mutation-gaps.md).
void main() {
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
  });

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
  );

  test('a crash-resumed accepted rename does not overwrite a pull stored after '
      'the crash (F1)', () async {
    await recordRename();
    final marked = await store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
    );
    // The crash left the `accepted` marker: the backend took the rename,
    // the run died before its reconcile and clear.
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
      syncStatus: PlanningMutationSyncStatus.accepted,
      expectedRevision: marked!.localRevision,
    );
    final refreshRemote = _ScriptedRefreshRemote(
      _payload(sessionName: 'Foreign', sessionVersion: 4, contentVersion: 5),
    );
    final planningSync = planningSyncFor(refreshRemote);
    await planningSync.handleActiveContextChanged(readContext, refresh: false);
    // A pull stored after the crash holds the rename and a foreign write.
    await planningSync.refreshPlanning();

    final controller = PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () =>
          ScriptedPlanningRemote((_) => fail('a resumed marker is not resent')),
      refreshPlanning: (_) async => false,
      isRunContextActive: (_) => true,
      reconcileAcceptedMutation: reconciler.reconcile,
    );
    await controller.syncPendingMutations(readContext);

    await expectProjectionHoldsF();
    expect(
      await store.readAllMutations(userId: 'user-1', organizationId: 'org-1'),
      isEmpty,
    );
  });

  test('a retried session create resumed after a crash does not overwrite a '
      'foreign rename (F1)', () async {
    await store.recordSessionCreate(
      context: context,
      draft: const PlanningSessionCreateMutationDraft(
        sessionId: 'session-new',
        planId: 'plan-1',
        slug: 'mine',
        name: 'Mine',
        position: 2,
      ),
    );
    Future<PlanningMutationRecord> row() async => (await store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-new',
    ))!;
    // The first attempt failed, the user pressed Retry: MG8 rebases a create
    // from any status, so the row's base is now the PLAN version (2), which
    // is not a session version.
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-new',
      syncStatus: PlanningMutationSyncStatus.failedDependency,
      expectedRevision: (await row()).localRevision,
    );
    await store.retryMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-new',
    );
    expect((await row()).baseVersion, 2);
    // The retried create was accepted (session v1, content version 4); the
    // run died before its reconcile and clear.
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-new',
      syncStatus: PlanningMutationSyncStatus.accepted,
      expectedRevision: (await row()).localRevision,
    );
    // A pull stored after the crash holds a foreign rename of the new
    // session: v2 'Foreign', plan content version 5.
    await localStore.replaceActiveProjection(
      userId: 'user-1',
      organizationId: 'org-1',
      plans: [
        CachedPlanRecord(
          id: 'plan-1',
          slug: 'plan-1',
          name: 'Plan',
          description: null,
          scheduledFor: null,
          updatedAt: DateTime.utc(2026),
          version: 2,
          contentVersion: 5,
        ),
      ],
      sessions: const [
        CachedSessionRecord(
          id: 'session-1',
          planId: 'plan-1',
          position: 1,
          name: 'S',
          version: 2,
        ),
        CachedSessionRecord(
          id: 'session-new',
          planId: 'plan-1',
          slug: 'mine',
          position: 2,
          name: 'Foreign',
          version: 2,
        ),
      ],
      items: const [],
      refreshedAt: DateTime.utc(2026, 1, 2),
    );

    final controller = PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () =>
          ScriptedPlanningRemote((_) => fail('a resumed marker is not resent')),
      refreshPlanning: (_) async => false,
      isRunContextActive: (_) => true,
      reconcileAcceptedMutation: reconciler.reconcile,
    );
    await controller.syncPendingMutations(readContext);

    final detail = (await localStore.readPlanDetail(
      userId: 'user-1',
      organizationId: 'org-1',
      planId: 'plan-1',
    ))!;
    final session = detail.sessions.singleWhere((s) => s.id == 'session-new');
    expect(detail.plan.contentVersion, 5);
    expect(session.name, 'Foreign');
    expect(session.version, 2);
    expect(
      await store.readAllMutations(userId: 'user-1', organizationId: 'org-1'),
      isEmpty,
    );
  });
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
