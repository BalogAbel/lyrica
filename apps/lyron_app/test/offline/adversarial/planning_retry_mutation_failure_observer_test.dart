import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// N3 (PR #64 review, second remediation round): `PlanningMutationSyncController
/// .retryMutation` used to decide whether to throw `connectivityFailure` by
/// re-reading the record's `errorCode` from the store AFTER `syncPendingMutations`
/// returned. If a local edit landed on the SAME aggregate during the retry's
/// own remote round trip, the failure-status write gates on the pre-send
/// revision (D2/D3, ADR-030) and no-ops -- correctly leaving the row `pending`
/// with the newer content and no stale error -- but that also means the
/// stale post-sync read finds `errorCode == null` and reports the retry as
/// having succeeded, even though this exact remote call genuinely got a
/// `connectivityFailure`. This suite drives the real
/// `DriftPlanningMutationStore` (not a hand-rolled fake) for the same reason
/// `planning_sync_snapshot_identity_test.dart` does: the D2/D3 gating this
/// race depends on lives inside the storage boundary.
void main() {
  group('retryMutation failure observer (N3)', () {
    test('an edit landing during the retry\'s own remote round trip must not '
        'make the retry look like it succeeded -- the caller still learns '
        'this exact attempt failed, even though the row self-heals', () async {
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

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );
      // Simulate a prior failed sync attempt, the starting state a retry
      // button acts on.
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
        errorMessage: 'base_version_conflict',
      );

      final remote = _GatedFailingPlanningRemote(
        const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final retryFuture = controller.retryMutation(
        readContext,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );

      // Wait until the retry's own remote call has actually been reached
      // (the controller already durably marked the row `sending` at the
      // pre-send revision before this).
      await remote.entered.future;

      // The user keeps typing while THIS retry's remote call is in
      // flight -- the edit lands on the same aggregate, bumping its
      // revision past the `sending` write's captured value.
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Weekend Service',
          description: 'Edited while retrying',
        ),
      );

      // Now the retry's own remote call returns connectivityFailure.
      remote.gate.complete();

      await expectLater(
        retryFuture,
        throwsA(
          isA<PlanningMutationSyncException>().having(
            (e) => e.code,
            'code',
            PlanningMutationSyncErrorCode.connectivityFailure,
          ),
        ),
        reason:
            'the retry the user explicitly triggered genuinely failed to '
            'leave the device -- the caller must learn that, regardless '
            'of what a concurrent edit did to the row afterward',
      );

      final afterRetry = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(
        afterRetry,
        isNotNull,
        reason: 'the concurrent edit must not be silently discarded',
      );
      expect(
        afterRetry!.syncStatus,
        PlanningMutationSyncStatus.pending,
        reason:
            'D3 self-heal: the gated failure-status write no-ops against '
            'the newer revision, leaving the row exactly as the edit left '
            'it -- pending, ready for the next ordinary sync to resend',
      );
      expect(afterRetry.description, 'Edited while retrying');
      expect(
        afterRetry.errorCode,
        isNull,
        reason:
            'the newer, never-sent content must not carry a stale error '
            'from a failure that concluded the OLD content\'s send',
      );
    });

    test('the unchanged case still throws exactly as before when nothing '
        'edits the aggregate during the retry\'s remote call', () async {
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

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
        errorMessage: 'base_version_conflict',
      );

      final remote = _GatedFailingPlanningRemote(
        const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
      );
      // No concurrent edit this time -- release the gate immediately.
      remote.gate.complete();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await expectLater(
        controller.retryMutation(
          readContext,
          aggregateType: 'plan',
          aggregateId: 'plan-1',
        ),
        throwsA(
          isA<PlanningMutationSyncException>().having(
            (e) => e.code,
            'code',
            PlanningMutationSyncErrorCode.connectivityFailure,
          ),
        ),
      );

      final afterRetry = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(afterRetry!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(
        afterRetry.errorCode,
        PlanningMutationSyncErrorCode.connectivityFailure,
      );
    });
  });

  /// N3, remaining gaps found in the third review round's follow-up. The
  /// observer closes the stale-read window, but two paths still let an
  /// explicit retry return as if it had worked while nothing was sent.
  group('retryMutation silent-success gaps (N3 follow-up)', () {
    test('a connectivity failure on an EARLIER candidate ends the pass before '
        'the retried aggregate is ever attempted -- the retry must still '
        'report that nothing left the device', () async {
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

      // Two pending plans. The user hits retry on the SECOND one while
      // offline; `_run` breaks out of its loop on the first one's
      // connectivity failure, so the retried aggregate is never sent.
      for (final (id, slug, name) in const [
        ('plan-1', 'first-service', 'First Service'),
        ('plan-2', 'second-service', 'Second Service'),
      ]) {
        await store.recordPlanCreate(
          context: context,
          draft: PlanningPlanCreateMutationDraft(
            planId: id,
            slug: slug,
            name: name,
            description: 'Original description',
          ),
        );
      }
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-2',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
        errorMessage: 'base_version_conflict',
      );

      final remote = _AlwaysFailingPlanningRemote(
        const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await expectLater(
        controller.retryMutation(
          readContext,
          aggregateType: 'plan',
          aggregateId: 'plan-2',
        ),
        throwsA(
          isA<PlanningMutationSyncException>().having(
            (e) => e.code,
            'code',
            PlanningMutationSyncErrorCode.connectivityFailure,
          ),
        ),
        reason:
            'the user asked for THIS record to be resent and it never '
            'reached the network -- returning normally reports a success '
            'that did not happen, the exact silent success S13 removed',
      );

      expect(
        remote.attempted,
        isNot(contains('plan-2')),
        reason:
            'precondition: the retried aggregate must genuinely never have '
            'been attempted, or this test proves nothing about the gap',
      );
    });

    test('a competing sync starting in the window between retryMutation\'s '
        'in-flight wait and its own call must not swallow the retry\'s '
        'failure signal', () async {
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

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Original description',
        ),
      );

      final remote = _AlwaysFailingPlanningRemote(
        const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
        gateFirstCall: true,
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      // A background sync is already running when the user hits retry.
      final backgroundRun = controller.syncPendingMutations(readContext);

      // Another trigger (a concurrent write's `_scheduleSync`, say) starts a
      // NEW observer-less run the moment the background one finishes.
      // Registered here, before `retryMutation` awaits the same future, so
      // it lands in exactly the window `retryMutation`'s in-flight wait
      // leaves open: the wait only guarantees the run it saw is over, not
      // that no other run has started since.
      unawaited(
        backgroundRun.then((_) {
          unawaited(controller.syncPendingMutations(readContext));
        }),
      );

      final retryFuture = controller.retryMutation(
        readContext,
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );

      await remote.entered.future;
      remote.gate.complete();

      await expectLater(
        retryFuture,
        throwsA(
          isA<PlanningMutationSyncException>().having(
            (e) => e.code,
            'code',
            PlanningMutationSyncErrorCode.connectivityFailure,
          ),
        ),
        reason:
            'coalescing onto a run started without the observer drops the '
            'retry\'s only failure signal -- and that run snapshotted its '
            'candidates before this retry\'s reset anyway, so riding along '
            'on it is exactly what the in-flight wait exists to prevent',
      );
    });
  });
}

/// Every call throws [failure]; the first optionally gates on [gate] so a
/// test can interleave against a run that is genuinely in flight. Records
/// the aggregate ids it was actually asked to send, so a test can assert
/// that a record was never attempted rather than assuming it.
class _AlwaysFailingPlanningRemote implements PlanningMutationRemoteRepository {
  _AlwaysFailingPlanningRemote(this.failure, {this.gateFirstCall = false});

  final PlanningMutationSyncException failure;
  final bool gateFirstCall;
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  final List<String> attempted = <String>[];

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    attempted.add(record.aggregateId);
    if (gateFirstCall && attempted.length == 1) {
      if (!entered.isCompleted) {
        entered.complete();
      }
      await gate.future;
    }
    throw failure;
  }
}

/// Copy of `planning_sync_snapshot_identity_test.dart`'s
/// `_GatedFailingPlanningRemote`: the FIRST call gates on [gate] and throws
/// [failure] once released; a second call (a following, un-raced sync)
/// closes the loop as an ordinary immediate accept.
class _GatedFailingPlanningRemote implements PlanningMutationRemoteRepository {
  _GatedFailingPlanningRemote(this.failure);

  final PlanningMutationSyncException failure;
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  var _calls = 0;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    _calls += 1;
    if (_calls == 1) {
      if (!entered.isCompleted) {
        entered.complete();
      }
      await gate.future;
      throw failure;
    }
    return record.copyWith(syncStatus: PlanningMutationSyncStatus.accepted);
  }
}
