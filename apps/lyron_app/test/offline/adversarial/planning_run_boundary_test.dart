import 'dart:async';

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
import 'package:lyron_app/src/application/planning/session_item_key_edit.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/planning_run_fixtures.dart';

/// Adversarial coverage for S5b PR 1 (MG4, MG5): rule 1a of the content-version
/// advance runs only after a successful reconcile of the same record, for a
/// record whose run context is still active; the post-write refresh counts
/// only a pull that started after the write. Real storage boundary and sync
/// controllers against a scripted backend.
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
  var active = true;

  setUp(() async {
    active = true;
    db = PlanningLocalDatabase.inMemory();
    localStore = DriftPlanningLocalStore(db);
    store = DriftPlanningMutationStore(database: db, localStore: localStore);
    reconciler = PlanningMutationReconciler(localStore: () => localStore);
    await seedPlanningProjection(localStore, contentVersion: 3);
  });

  tearDown(() async {
    await db.close();
  });

  PlanningMutationSyncController controllerFor(
    PlanningMutationRemoteRepository remote, {
    PlanningRefreshTrigger? refreshPlanning,
    PlanningAcceptedMutationReconciler? reconcile,
  }) => PlanningMutationSyncController(
    mutationStore: () => store,
    remoteRepository: () => remote,
    refreshPlanning: refreshPlanning ?? (_) async => false,
    isRunContextActive: (_) => active,
    reconcileAcceptedMutation: reconcile ?? reconciler.reconcile,
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

  Future<PlanDetail?> planDetail(String planId) => localStore.readPlanDetail(
    userId: 'user-1',
    organizationId: 'org-1',
    planId: planId,
  );

  Future<List<PlanningMutationRecord>> allRows() =>
      store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

  test('a context switch before the batch end leaves the old projection '
      'behind its content, never ahead', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote((record) async {
      active = false;
      return record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4);
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    final detail = (await planDetail('plan-1'))!;
    expect(detail.plan.contentVersion, 3);
    expect(detail.sessions.single.name, 'S');
    expect(await allRows(), isEmpty);
  });

  test('a context switch before the batch end skips the refresh of the new '
      'context', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote((record) async {
      active = false;
      return record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4);
    });
    var refreshCalls = 0;

    await controllerFor(
      remote,
      refreshPlanning: (_) async {
        refreshCalls += 1;
        return true;
      },
    ).syncPendingMutations(readContext);

    expect(refreshCalls, 0);
    expect((await planDetail('plan-1'))!.plan.contentVersion, 3);
  });

  test('a reconcile failure leaves the projection content version '
      'untouched', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote(
      (record) async =>
          record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4),
    );

    await controllerFor(
      remote,
      reconcile: (ctx, record) async =>
          throw ReconcileFieldError('name', PlanningMutationKind.sessionRename),
    ).syncPendingMutations(readContext);

    expect((await planDetail('plan-1'))!.plan.contentVersion, 3);
    final rows = await allRows();
    expect(rows.single.syncStatus, PlanningMutationSyncStatus.failedDependency);
  });

  test('a plan created and given a child in one batch still reaches content '
      'version 2', () async {
    await store.recordPlanCreate(
      context: context,
      draft: const PlanningPlanCreateMutationDraft(
        planId: 'plan-new',
        slug: 'plan-new',
        name: 'New plan',
      ),
    );
    await store.recordSessionCreate(
      context: context,
      draft: const PlanningSessionCreateMutationDraft(
        sessionId: 'session-new',
        planId: 'plan-new',
        slug: 'session-new',
        name: 'New session',
        position: 1,
      ),
    );
    final remote = ScriptedPlanningRemote((record) async {
      switch (record.kind) {
        case PlanningMutationKind.planCreate:
          return record.copyWith(acceptedPlanContentVersion: 1);
        case PlanningMutationKind.sessionCreate:
          return record.copyWith(baseVersion: 1, acceptedPlanContentVersion: 2);
        default:
          throw StateError('unexpected ${record.kind}');
      }
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    expect((await planDetail('plan-new'))!.plan.contentVersion, 2);
    expect(await allRows(), isEmpty);
  });

  test('a sign-out purge inside a run writes nothing back', () async {
    await recordRename();
    final remote = ScriptedPlanningRemote((record) async {
      await localStore.deletePlanningDataForUser(userId: 'user-1');
      active = false;
      return record.copyWith(baseVersion: 3, acceptedPlanContentVersion: 4);
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    expect(await planDetail('plan-1'), isNull);
    expect(await allRows(), isEmpty);
  });

  test('a key edit accepted while an older refresh is in flight ends with the '
      'returned item version in the projection', () async {
    final stale = Completer<PlanningSyncPayload>();
    final remoteRefresh = _ScriptedRefreshRemote([
      stale.future,
      Future.value(_payload(itemVersion: 2)),
    ]);
    final planningSync = PlanningSyncController(
      localStore: () => localStore,
      localDataLifecycle: LocalDataLifecycle(
        songCatalogStore: _NoopSongCatalogStore(),
        planningLocalStore: localStore,
        identityStore: _NoopLastKnownIdentityStore(),
        noteLastKnownIdentity: (_) {},
        eventsRecorder: _NoopLocalDataEventsRecorder(),
      ),
      remoteRepository: () => remoteRefresh,
      authSessionReader: () =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
    );
    await planningSync.handleActiveContextChanged(readContext, refresh: false);
    await store.recordSessionItemKeyEdit(
      context: context,
      draft: PlanningSessionItemKeyEditMutationDraft(
        sessionItemId: 'item-1',
        sessionId: 'session-1',
        planId: 'plan-1',
        edit: SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: 2,
          capoMode: SessionItemKeyFieldMode.keep,
        ),
        baseVersion: 1,
        baseTranspose: null,
        baseCapo: null,
      ),
    );
    final remote = ScriptedPlanningRemote(
      (record) async => record.copyWith(baseVersion: 2),
    );
    final refreshRequested = Completer<void>();

    final olderRefresh = planningSync.refreshPlanning();
    final sync = controllerFor(
      remote,
      refreshPlanning: (ctx) {
        refreshRequested.complete();
        return planningSync.refreshPlanningAfterWrite(ctx);
      },
    ).syncPendingMutations(readContext);
    await refreshRequested.future;
    stale.complete(_payload(itemVersion: 1));
    await Future.wait([olderRefresh, sync]);

    expect(remoteRefresh.fetchCount, 2);
    final item = (await planDetail('plan-1'))!.sessions.single.items.single;
    expect(item.version, 2);
    expect(await allRows(), isEmpty);
  });
}

PlanningSyncPayload _payload({required int itemVersion}) => PlanningSyncPayload(
  plans: [
    PlanningSyncPlan(
      id: 'plan-1',
      slug: 'plan-1',
      name: 'Plan',
      description: null,
      scheduledFor: null,
      updatedAt: DateTime.utc(2026),
      version: 2,
      contentVersion: 3,
    ),
  ],
  sessions: const [
    PlanningSyncSession(
      id: 'session-1',
      planId: 'plan-1',
      slug: 'session-1',
      position: 1,
      name: 'S',
      version: 2,
    ),
  ],
  items: [
    PlanningSyncSessionItem(
      id: 'item-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      position: 1,
      songId: 'song-1',
      songTitle: 'Song',
      version: itemVersion,
    ),
  ],
);

/// Answers its pulls from a script, in order.
class _ScriptedRefreshRemote implements PlanningRemoteRefreshRepository {
  _ScriptedRefreshRemote(this._payloads);

  final List<Future<PlanningSyncPayload>> _payloads;
  int fetchCount = 0;

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
    bool Function()? shouldContinue,
  }) => _payloads[fetchCount++];
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
