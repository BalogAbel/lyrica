import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Adversarial coverage for
/// `docs/specs/2026-08-06-in-flight-create-cancellation.md` (D1/D2/D3,
/// planning half): ADR-030's `localRevision` gate assumes newer intent
/// arriving during a remote round trip leaves a pending row at a HIGHER
/// revision. That holds for edits. It does not hold for a delete of a
/// still-pending create, because the collapse ADR-028 D10 admits physically
/// REMOVES the row instead. If the create's own remote send is in flight at
/// that exact moment, the collapse destroys the only local record of the
/// user's delete intent -- the backend then accepts the create, and nothing
/// is ever left to tell it to delete the object.
///
/// This suite drives the real `DriftPlanningMutationStore` (not a hand-
/// rolled fake) because the fix lives inside the storage boundary, the same
/// reasoning `planning_sync_snapshot_identity_test.dart` documents.
void main() {
  group('In-flight create cancellation (D1/D2/D3, planning)', () {
    test('session: deleting a session while its create is in flight survives '
        'as a pending delete once the create succeeds', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 1,
        ),
      );

      final remote = _GatedPlanningRemote();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final syncFuture = controller.syncPendingMutations(readContext);

      // Wait until the remote call for the create has actually been
      // reached -- the create's send is genuinely in flight.
      await remote.entered.future;

      // The user deletes the session while that create is still in
      // flight.
      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      // Release the gate: the create succeeds on the backend.
      remote.gate.complete();
      await syncFuture;

      final afterSync = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      );

      expect(
        afterSync,
        isNotNull,
        reason:
            'the delete intent must survive -- the session now exists on '
            'the backend, and nothing will ever delete it if this row is '
            'lost',
      );
      expect(afterSync!.kind, PlanningMutationKind.sessionDelete);
      expect(afterSync.syncStatus, PlanningMutationSyncStatus.pending);

      // The next sync sends the delete.
      await controller.syncPendingMutations(readContext);
      final deleteCalls = remote.calls.where(
        (record) => record.kind == PlanningMutationKind.sessionDelete,
      );
      expect(
        deleteCalls,
        hasLength(1),
        reason: 'the survived delete intent must actually be sent',
      );
    });

    test('session item: deleting a session item while its create is in flight '
        'survives as a pending delete once the create succeeds', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song One',
          position: 1,
        ),
      );

      final remote = _GatedPlanningRemote();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final syncFuture = controller.syncPendingMutations(readContext);
      await remote.entered.future;

      await store.recordSessionItemDelete(
        context: context,
        draft: const PlanningSessionItemDeleteMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      remote.gate.complete();
      await syncFuture;

      final afterSync = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session_item',
        aggregateId: 'item-1',
      );

      expect(
        afterSync,
        isNotNull,
        reason: 'the delete intent must survive the in-flight create',
      );
      expect(afterSync!.kind, PlanningMutationKind.sessionItemDelete);
      expect(afterSync.syncStatus, PlanningMutationSyncStatus.pending);

      await controller.syncPendingMutations(readContext);
      final deleteCalls = remote.calls.where(
        (record) => record.kind == PlanningMutationKind.sessionItemDelete,
      );
      expect(deleteCalls, hasLength(1));
    });

    test('session: when the in-flight create fails instead, the tombstone '
        'resolves locally and no delete is ever sent', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 1,
        ),
      );

      final remote = _GatedPlanningRemote(
        failFirstWith: const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.authorizationDenied,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final syncFuture = controller.syncPendingMutations(readContext);
      await remote.entered.future;

      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      remote.gate.complete();
      await syncFuture;

      final afterSync = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      expect(
        afterSync,
        isNull,
        reason:
            'the create never reached the backend, so the tombstone must '
            'resolve locally with no trace left -- exactly like a plain '
            'collapse',
      );

      await controller.syncPendingMutations(readContext);
      final deleteCalls = remote.calls.where(
        (record) => record.kind == PlanningMutationKind.sessionDelete,
      );
      expect(
        deleteCalls,
        isEmpty,
        reason:
            'an object that never existed remotely must never be sent '
            'a delete',
      );
    });

    test('no regression: deleting a pending create with no sync in flight '
        'still collapses physically (ADR-028 D10 unchanged)', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 1,
        ),
      );

      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      final afterDelete = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      expect(
        afterDelete,
        isNull,
        reason:
            'no sync was ever in flight, so this must still be a '
            'plain physical collapse -- no tombstone',
      );
    });

    test('crash recovery: a record left `sending` is treated as pending on a '
        'fresh pass and resent', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 1,
        ),
      );

      // Simulate a crash that happened after a prior run durably wrote
      // the D1 `sending` marker but never got a response back: the
      // record is left `sending` with no in-flight call actually alive
      // anymore.
      final beforeCrash = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
        syncStatus: PlanningMutationSyncStatus.sending,
        expectedRevision: beforeCrash!.localRevision,
      );

      final remote = _GatedPlanningRemote();
      remote.gate.complete();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.syncPendingMutations(readContext);

      expect(
        remote.calls,
        hasLength(1),
        reason:
            'a record left `sending` by a crash must be resent, not '
            'stranded forever',
      );
      expect(remote.calls.single.kind, PlanningMutationKind.sessionCreate);

      final afterSync = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      );
      expect(
        afterSync,
        isNull,
        reason:
            'once resent and accepted, it clears normally, exactly '
            'like an ordinary pending record',
      );
    });
  });
}

/// Gates exactly the FIRST `syncMutation` call on [gate], signalling
/// [entered] once that call has been reached (so a test can race a local
/// write against it deterministically). Every later call resolves
/// immediately, so a test can drive a second sync run (e.g. sending the
/// delete a tombstone resolved into) without re-gating.
class _GatedPlanningRemote implements PlanningMutationRemoteRepository {
  _GatedPlanningRemote({this.failFirstWith});

  /// If set, the gated first call throws this once released instead of
  /// succeeding.
  final PlanningMutationSyncException? failFirstWith;

  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();
  final List<PlanningMutationRecord> calls = [];
  bool _firstCallSeen = false;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    calls.add(record);
    if (!_firstCallSeen) {
      _firstCallSeen = true;
      if (!entered.isCompleted) {
        entered.complete();
      }
      await gate.future;
      final failure = failFirstWith;
      if (failure != null) {
        throw failure;
      }
    }
    return record.copyWith(
      baseVersion: (record.baseVersion ?? 0) + 1,
      syncStatus: PlanningMutationSyncStatus.pending,
    );
  }
}
