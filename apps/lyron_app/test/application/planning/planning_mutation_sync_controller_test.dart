import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

void main() {
  group('PlanningMutationSyncController', () {
    test(
      'successful sync refreshes projection and clears the mutation',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              slug: 'weekend-service',
              name: 'Weekend Service',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        var reconcileCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {
            reconcileCalls += 1;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(refreshCalls, 1);
        expect(store.clearedAggregateIds, ['plan-1']);
        expect(reconcileCalls, 0);
      },
    );

    test(
      'authorization failures move mutations out of normal overlay states',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Weekend Service',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository(
          error: const PlanningMutationSyncException(
            PlanningMutationSyncErrorCode.authorizationDenied,
          ),
        );
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => true,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          store.lastSavedStatus,
          PlanningMutationSyncStatus.failedAuthorization,
        );
        expect(store.clearedAggregateIds, isEmpty);
        expect(repository.calls, 1);
      },
    );

    test('connectivity failure stops the remaining queue', () async {
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
          PlanningMutationRecord(
            aggregateId: 'plan-2',
            organizationId: 'org-1',
            name: 'Plan Two',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final repository = _FakePlanningMutationRemoteRepository(
        error: const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.syncPendingMutations(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

      expect(repository.calls, 1);
      expect(store.clearedAggregateIds, isEmpty);
    });

    test(
      'retrying a failed mutation marks it pending and resubmits it',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [],
          all: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.conflict,
              errorCode: PlanningMutationSyncErrorCode.conflict,
              errorMessage: 'base_version_conflict',
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.retryMutation(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.retriedAggregateIds, ['plan-1']);
        expect(repository.calls, 1);
        expect(store.clearedAggregateIds, ['plan-1']);
        expect(refreshCalls, 1);
      },
    );

    test('retrying a conflict works offline and requeues mutation', () async {
      final store = _FakePlanningMutationStore(
        pending: [],
        all: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            errorMessage: 'base_version_conflict',
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final repository = _FakePlanningMutationRemoteRepository();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => false,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.retryMutation(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: 'plan-1',
      );

      // Offline: retryMutation succeeds locally, then syncPendingMutations
      // attempts to send (repository.calls==1), but refresh fails so reconciles locally
      expect(store.retriedAggregateIds, contains('plan-1'));
      expect(repository.calls, 1);
      expect(store.clearedAggregateIds, contains('plan-1'));
    });

    test('retryMutation surfaces a connectivity failure to the caller and '
        'keeps the mutation retryable', () async {
      final store = _FakePlanningMutationStore(
        pending: [],
        all: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            errorMessage: 'base_version_conflict',
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final repository = _FakePlanningMutationRemoteRepository(
        error: const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final context = const ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await expectLater(
        controller.retryMutation(
          context,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
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

      // A retry that reports failure must not also discard the user's
      // work: the record is still in the store, pending, and still
      // renders as retryable.
      final record = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: 'plan-1',
      );
      expect(record, isNotNull);
      expect(record!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(
        record.errorCode,
        PlanningMutationSyncErrorCode.connectivityFailure,
      );
    });

    test('retryMutation must not report success when it coalesces onto a '
        'background sync that already snapshotted its candidates before the '
        'reset', () async {
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'plan-2',
            organizationId: 'org-1',
            name: 'Plan Two',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
          ),
        ],
        all: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            errorMessage: 'base_version_conflict',
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
          PlanningMutationRecord(
            aggregateId: 'plan-2',
            organizationId: 'org-1',
            name: 'Plan Two',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final syncCompleter = Completer<void>();
      // Every remote call fails offline -- both the background run's
      // attempt at plan-2 and (once fixed) the retry's own attempt at
      // plan-1 should end up with connectivityFailure.
      final repository = _FakePlanningMutationRemoteRepository(
        error: const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.connectivityFailure,
        ),
        slowCompleter: syncCompleter,
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final context = const ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      // A background trigger starts syncing first. Calling
      // syncPendingMutations synchronously reads and snapshots its
      // candidate list (plan-2 only -- plan-1 is a conflict, not
      // pending/accepted, so it is excluded) before suspending on the
      // (uncompleted) repository call below.
      final backgroundSync = controller.syncPendingMutations(context);

      // The user retries plan-1 while that background run is still in
      // flight. This resets plan-1 to pending with no error in the
      // store. Pre-fix, retryMutation's own call to syncPendingMutations
      // coalesces onto the SAME background run above -- which already
      // snapshotted its candidates without plan-1 in them and can never
      // pick it up.
      final retryFuture = controller.retryMutation(
        context,
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: 'plan-1',
      );

      // Drain every microtask that can run without the repository call
      // completing. The background run cannot progress past it until the
      // completer below is completed, so this deterministically captures
      // the moment retryMutation commits to coalescing (or, fixed, to
      // waiting) -- there is no race to lose either way.
      await Future<void>.delayed(Duration.zero);

      syncCompleter.complete();

      // Fixed behaviour: retryMutation must surface the connectivity
      // failure, exactly like the "surfaces a connectivity failure" test
      // above -- a retry that never left the device must not look like it
      // succeeded. Against the pre-fix controller this expectation fails:
      // retryFuture completes normally because it rode the background
      // run's future to completion, and that run never touched plan-1.
      await expectLater(
        retryFuture,
        throwsA(
          isA<PlanningMutationSyncException>().having(
            (e) => e.code,
            'code',
            PlanningMutationSyncErrorCode.connectivityFailure,
          ),
        ),
      );

      await backgroundSync;

      final record = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: 'plan-1',
      );
      expect(record, isNotNull);
      expect(
        record!.errorCode,
        PlanningMutationSyncErrorCode.connectivityFailure,
      );
    });

    test(
      'discarding a conflicted mutation syncs the remaining queue',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-2',
              organizationId: 'org-1',
              name: 'Plan Two',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 2,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.discardMutation(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.clearedAggregateIds, ['plan-1', 'plan-2']);
        expect(repository.calls, 1);
        expect(refreshCalls, 1);
      },
    );

    test('discarding a conflict works offline and clears mutation', () async {
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            errorMessage: 'base_version_conflict',
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final repository = _FakePlanningMutationRemoteRepository();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => false,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.discardMutation(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: 'plan-1',
      );

      expect(store.clearedAggregateIds, contains('plan-1'));
      expect(repository.calls, 0);
    });

    test(
      'successful sync reconciles the accepted mutation locally when refresh fails',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              slug: 'draft-slug',
              name: 'Draft name',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final syncedRecord = PlanningMutationRecord(
          aggregateId: 'plan-1',
          organizationId: 'org-1',
          slug: 'canonical-slug',
          name: 'Canonical name',
          kind: PlanningMutationKind.planCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          baseVersion: 3,
          updatedAt: DateTime.utc(2026),
        );
        final repository = _FakePlanningMutationRemoteRepository(
          result: syncedRecord,
        );
        PlanningMutationRecord? reconciledRecord;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, record) async {
            reconciledRecord = record;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(reconciledRecord, isNotNull);
        expect(reconciledRecord?.slug, 'canonical-slug');
        expect(reconciledRecord?.baseVersion, 3);
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );

    test(
      'successful session item sync reconciles locally when refresh fails',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'item-local-1',
              organizationId: 'org-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              songId: 'song-2',
              songTitle: 'Beta',
              kind: PlanningMutationKind.sessionItemCreateSong,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final syncedRecord = PlanningMutationRecord(
          aggregateId: 'item-9',
          organizationId: 'org-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          songId: 'song-2',
          songTitle: 'Beta',
          orderedSiblingIds: const ['item-1', 'item-9'],
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          baseVersion: 5,
          updatedAt: DateTime.utc(2026),
        );
        final repository = _FakePlanningMutationRemoteRepository(
          result: syncedRecord,
        );
        PlanningMutationRecord? reconciledRecord;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, record) async {
            reconciledRecord = record;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          reconciledRecord?.kind,
          PlanningMutationKind.sessionItemCreateSong,
        );
        expect(reconciledRecord?.aggregateId, 'item-9');
        expect(
          reconciledRecord?.orderedSiblingIds,
          orderedEquals(const ['item-1', 'item-9']),
        );
        expect(store.clearedAggregateIds, ['item-local-1']);
      },
    );

    test(
      'accepted-write fallback is skipped when the active boundary changed',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              slug: 'draft-slug',
              name: 'Draft name',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var reconcileCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => false,
          reconcileAcceptedMutation: (_, _) async {
            reconcileCalls += 1;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(reconcileCalls, 0);
        expect(store.clearedAggregateIds, ['plan-1']);
      },
    );

    test(
      'syncPendingMutations refreshes once for N accepted mutations',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
            PlanningMutationRecord(
              aggregateId: 'plan-2',
              organizationId: 'org-1',
              name: 'Plan Two',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 2,
              updatedAt: DateTime.utc(2026),
            ),
            PlanningMutationRecord(
              aggregateId: 'plan-3',
              organizationId: 'org-1',
              name: 'Plan Three',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 3,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(refreshCalls, 1);
        expect(store.clearedAggregateIds, ['plan-1', 'plan-2', 'plan-3']);
      },
    );

    test(
      'syncPendingMutations does not refresh when no mutations accepted',
      () async {
        final store = _FakePlanningMutationStore(pending: []);
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(refreshCalls, 0);
        expect(repository.calls, 0);
        expect(store.clearedAggregateIds, isEmpty);
      },
    );

    test(
      'a mutation already marked accepted is reconciled/cleared, not re-sent',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [],
          all: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planCreate,
              syncStatus: PlanningMutationSyncStatus.accepted,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository(
          error: const PlanningMutationSyncException(
            PlanningMutationSyncErrorCode.unknown,
          ),
        );
        var reconcileCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {
            reconcileCalls += 1;
          },
        );

        await controller.syncPendingMutations(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(
          repository.calls,
          0,
          reason: 'syncMutation should not be called for accepted',
        );
        expect(reconcileCalls, 1, reason: 'reconcile should be called');
        expect(store.clearedAggregateIds, [
          'plan-1',
        ], reason: 'mutation should be cleared');
      },
    );

    test('concurrent syncPendingMutations calls do not double-send', () async {
      final syncCompleter = Completer<void>();
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Plan One',
            kind: PlanningMutationKind.planCreate,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final repository = _FakePlanningMutationRemoteRepository(
        slowCompleter: syncCompleter,
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => repository,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final context = const ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      // Start two concurrent calls
      final a = controller.syncPendingMutations(context);
      final b = controller.syncPendingMutations(context);

      // Both should be awaiting the same in-flight future
      expect(
        identical(a, b),
        true,
        reason: 'concurrent calls should return same future',
      );

      // Release the remote sync
      syncCompleter.complete();
      await Future.wait([a, b]);

      // Each pending mutation sent exactly once
      expect(
        repository.calls,
        1,
        reason: 'remote.syncMutation called exactly once',
      );
      expect(store.clearedAggregateIds, [
        'plan-1',
      ], reason: 'mutation cleared once');
    });

    test(
      'retryMutation awaits syncPendingMutations without deadlock',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [],
          all: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.conflict,
              errorCode: PlanningMutationSyncErrorCode.conflict,
              errorMessage: 'conflict',
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        final context = const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        // retryMutation calls syncPendingMutations internally
        await controller.retryMutation(
          context,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.retriedAggregateIds, ['plan-1']);
        expect(repository.calls, 1);
        expect(store.clearedAggregateIds, ['plan-1']);
        expect(refreshCalls, 1);
      },
    );

    test(
      'discardMutation awaits syncPendingMutations without deadlock',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-2',
              organizationId: 'org-1',
              name: 'Plan Two',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: 2,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        var refreshCalls = 0;
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async {
            refreshCalls += 1;
            return true;
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        final context = const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        // discardMutation calls syncPendingMutations internally
        await controller.discardMutation(
          context,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.clearedAggregateIds, ['plan-1', 'plan-2']);
        expect(repository.calls, 1);
        expect(refreshCalls, 1);
      },
    );

    test(
      'discardMutation clears local intent when refresh is unavailable',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.conflict,
              errorCode: PlanningMutationSyncErrorCode.conflict,
              errorMessage: 'conflict',
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.discardMutation(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.clearedAggregateIds, contains('plan-1'));
      },
    );

    test(
      'retryMutation re-queues local intent when refresh is unavailable',
      () async {
        final store = _FakePlanningMutationStore(
          pending: [],
          all: [
            PlanningMutationRecord(
              aggregateId: 'plan-1',
              organizationId: 'org-1',
              name: 'Plan One',
              kind: PlanningMutationKind.planEdit,
              syncStatus: PlanningMutationSyncStatus.conflict,
              errorCode: PlanningMutationSyncErrorCode.conflict,
              errorMessage: 'conflict',
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        final repository = _FakePlanningMutationRemoteRepository();
        final controller = PlanningMutationSyncController(
          mutationStore: () => store,
          remoteRepository: () => repository,
          refreshPlanning: () async => false,
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: (_, _) async {},
        );

        await controller.retryMutation(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        );

        expect(store.retriedAggregateIds, contains('plan-1'));
        expect(store.clearedAggregateIds, contains('plan-1'));
      },
    );
  });
}

class _FakePlanningMutationStore implements PlanningMutationStore {
  _FakePlanningMutationStore({
    required this.pending,
    List<PlanningMutationRecord>? all,
  }) : all = all ?? pending;

  final List<PlanningMutationRecord> pending;
  final List<PlanningMutationRecord> all;
  final List<String> clearedAggregateIds = [];
  final List<String> retriedAggregateIds = [];
  PlanningMutationSyncStatus? lastSavedStatus;

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async {
    clearedAggregateIds.add(aggregateId);
    return true;
  }

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'unused';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'unused';

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async =>
      pending.isNotEmpty;

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async {
    // Combine pending and all, preferring pending versions (retried mutations)
    final seen = <String>{};
    final merged = <PlanningMutationRecord>[];
    for (final p in pending) {
      merged.add(p);
      seen.add(p.aggregateId);
    }
    for (final a in all) {
      if (!seen.contains(a.aggregateId)) {
        merged.add(a);
      }
    }
    // Sort by orderKey asc, then aggregateId asc (match drift query)
    merged.sort((x, y) {
      final cmp = x.orderKey.compareTo(y.orderKey);
      if (cmp != 0) return cmp;
      return x.aggregateId.compareTo(y.aggregateId);
    });
    return merged;
  }

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    for (final record in pending) {
      if (record.kind.aggregateType == aggregateType &&
          record.aggregateId == aggregateId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => pending;

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => pending;

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    retriedAggregateIds.add(aggregateId);
    final match = all.firstWhere(
      (record) =>
          record.kind.aggregateType == aggregateType &&
          record.aggregateId == aggregateId,
    );
    pending.add(
      match.copyWith(
        syncStatus: PlanningMutationSyncStatus.pending,
        clearErrorCode: true,
        clearErrorMessage: true,
      ),
    );
    return true;
  }

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}
  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}
  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) async {
    lastSavedStatus = syncStatus;
    // Mirror the real store: persist the attempt result onto the record so
    // a subsequent readMutation reflects it, the way the Drift-backed store
    // does. None of the tests in this file exercise the D2 snapshot-identity
    // race (that is covered end-to-end against the real
    // DriftPlanningMutationStore in
    // test/offline/adversarial/planning_sync_snapshot_identity_test.dart),
    // so this fake applies unconditionally regardless of expectedRevision.
    final index = pending.indexWhere(
      (record) =>
          record.kind.aggregateType == aggregateType &&
          record.aggregateId == aggregateId,
    );
    if (index != -1) {
      pending[index] = pending[index].copyWith(
        syncStatus: syncStatus,
        errorCode: errorCode,
        clearErrorCode: errorCode == null,
        errorMessage: errorMessage,
        clearErrorMessage: errorMessage == null,
      );
    }
    return 1;
  }
}

class _FakePlanningMutationRemoteRepository
    implements PlanningMutationRemoteRepository {
  _FakePlanningMutationRemoteRepository({
    this.error,
    this.result,
    this.slowCompleter,
  });

  final PlanningMutationSyncException? error;
  final PlanningMutationRecord? result;
  final Completer<void>? slowCompleter;
  int calls = 0;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    calls += 1;
    if (slowCompleter != null) {
      await slowCompleter!.future;
    }
    if (error != null) {
      throw error!;
    }
    return result ?? record;
  }
}
