import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

void main() {
  final originalDontWarnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        originalDontWarnAboutMultipleDatabases;
  });

  group('PlanningSyncController', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore store;
    late _FakePlanningRemoteRefreshRepository remoteRepository;
    late AppAuthSession? session;

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      store = DriftPlanningLocalStore(database);
      remoteRepository = _FakePlanningRemoteRefreshRepository();
      session = const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyron.local',
      );
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'eager refresh starts when signed-in active context becomes available',
      () async {
        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        expect(controller.state.accessStatus, PlanningAccessStatus.signedIn);
        expect(controller.state.userId, 'user-1');
        expect(controller.state.organizationId, 'org-1');
        expect(controller.state.refreshStatus, PlanningRefreshStatus.idle);
        expect(controller.state.hasLocalPlanningData, isTrue);
        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'keeps the previous local planning state when refresh fails',
      () async {
        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
        remoteRepository.error = Exception('offline');

        await controller.refreshPlanning();

        expect(controller.state.refreshStatus, PlanningRefreshStatus.failed);
        expect(controller.state.hasLocalPlanningData, isTrue);
        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          hasLength(1),
        );
      },
    );

    test('overlapping refreshes do not run concurrently', () async {
      final firstRefresh = Completer<PlanningSyncPayload>();
      remoteRepository.nextPayload = firstRefresh.future;
      final controller = PlanningSyncController(
        localStore: () => store,
        remoteRepository: () => remoteRepository,
        authSessionReader: () => session,
      );
      await controller.handleActiveContextChanged(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        refresh: false,
      );

      final refreshA = controller.refreshPlanning();
      final refreshB = controller.refreshPlanning();
      await Future<void>.delayed(Duration.zero);

      expect(remoteRepository.fetchCallCount, 1);
      expect(controller.state.refreshStatus, PlanningRefreshStatus.refreshing);

      firstRefresh.complete(_payloadFor('org-1'));
      await Future.wait([refreshA, refreshB]);

      expect(remoteRepository.fetchCallCount, 1);
      expect(controller.state.refreshStatus, PlanningRefreshStatus.idle);
    });

    test(
      'sign-out during an in-flight refresh prevents stale repopulation',
      () async {
        final inFlightRefresh = Completer<PlanningSyncPayload>();
        remoteRepository.nextPayload = inFlightRefresh.future;
        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );
        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          refresh: false,
        );

        final refreshFuture = controller.refreshPlanning();
        session = null;
        await controller.handleExplicitSignOut();

        inFlightRefresh.complete(_payloadFor('org-1'));
        await refreshFuture;

        expect(controller.state.accessStatus, PlanningAccessStatus.signedOut);
        expect(controller.state.organizationId, isNull);
        expect(controller.state.hasLocalPlanningData, isFalse);
        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'sign-out during a blocked local commit prevents stale repopulation',
      () async {
        final inFlightRefresh = Completer<PlanningSyncPayload>();
        remoteRepository.nextPayload = inFlightRefresh.future;
        final replaceStarted = Completer<void>();
        final commitGate = Completer<void>();
        final localStore = _BlockingPlanningLocalStore(
          replaceStarted: replaceStarted,
          commitGate: commitGate,
        );
        final controller = PlanningSyncController(
          localStore: () => localStore,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );
        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          refresh: false,
        );

        final refreshFuture = controller.refreshPlanning();
        inFlightRefresh.complete(_payloadFor('org-1'));
        await replaceStarted.future;

        session = null;
        await controller.handleExplicitSignOut();
        commitGate.complete();
        await refreshFuture;

        expect(controller.state.accessStatus, PlanningAccessStatus.signedOut);
        expect(
          await localStore.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'explicit sign-out still deletes planning data after active context has already been cleared',
      () async {
        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        session = null;
        await controller.handleActiveContextChanged(null, refresh: false);
        await controller.handleExplicitSignOut();

        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'session expiry clears persisted planning data for the previous user',
      () async {
        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        session = null;
        await controller.handleSessionExpired();

        expect(controller.state.accessStatus, PlanningAccessStatus.signedOut);
        expect(controller.state.userId, isNull);
        expect(controller.state.organizationId, isNull);
        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'stale refresh completions are discarded after the active organization changes',
      () async {
        final org1Refresh = Completer<PlanningSyncPayload>();
        final org2Refresh = Completer<PlanningSyncPayload>();
        remoteRepository.payloadsByOrganizationId['org-1'] = org1Refresh.future;
        remoteRepository.payloadsByOrganizationId['org-2'] = org2Refresh.future;

        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );
        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          refresh: false,
        );
        final firstRefresh = controller.refreshPlanning();

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
          refresh: false,
        );
        final secondRefresh = controller.refreshPlanning();

        org2Refresh.complete(_payloadFor('org-2', planId: 'plan-2'));
        await secondRefresh;
        org1Refresh.complete(_payloadFor('org-1', planId: 'plan-1'));
        await firstRefresh;

        expect(controller.state.organizationId, 'org-2');
        expect(
          await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
          ),
          isNull,
        );
        expect(
          await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-2',
            planId: 'plan-2',
          ),
          isNotNull,
        );
      },
    );

    test(
      'stale previous-boundary delete is aborted when ownership returns to that organization',
      () async {
        final localStore = _BlockingBoundaryDeletePlanningLocalStore(store);
        final controller = PlanningSyncController(
          localStore: () => localStore,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );

        final switchToOrg2 = controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
          refresh: false,
        );
        await localStore.deleteStarted.future;

        final switchBackToOrg1 = controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          refresh: false,
        );
        localStore.releaseDelete();

        await switchToOrg2;
        await switchBackToOrg1;

        expect(controller.state.organizationId, 'org-1');
        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'organization change while a refresh is in flight still triggers a refresh for the new generation',
      () async {
        final org1Refresh = Completer<PlanningSyncPayload>();
        remoteRepository.payloadsByOrganizationId['org-1'] = org1Refresh.future;

        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );
        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          refresh: false,
        );

        final firstRefresh = controller.refreshPlanning();
        await Future<void>.delayed(Duration.zero);

        remoteRepository.payloadsByOrganizationId['org-2'] = Future.value(
          _payloadFor('org-2', planId: 'plan-2'),
        );
        final secondRefreshFuture = controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
        );

        org1Refresh.complete(_payloadFor('org-1', planId: 'plan-1'));
        await firstRefresh;
        await secondRefreshFuture;

        expect(remoteRepository.fetchCallCount, 2);
        expect(controller.state.organizationId, 'org-2');
        expect(
          await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-2',
            planId: 'plan-2',
          ),
          isNotNull,
        );
      },
    );

    test(
      'switching to a new active organization that fails to refresh does not expose the previous organization projection',
      () async {
        final controller = PlanningSyncController(
          localStore: () => store,
          remoteRepository: () => remoteRepository,
          authSessionReader: () => session,
        );

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        );
        remoteRepository.payloadsByOrganizationId['org-2'] =
            Future<PlanningSyncPayload>(() => throw Exception('offline'));

        await controller.handleActiveContextChanged(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
        );

        expect(controller.state.organizationId, 'org-2');
        expect(controller.state.refreshStatus, PlanningRefreshStatus.failed);
        expect(controller.state.hasLocalPlanningData, isFalse);
        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );
  });
}

PlanningSyncPayload _payloadFor(
  String organizationId, {
  String planId = 'plan-1',
}) {
  return PlanningSyncPayload(
    plans: [
      PlanningSyncPlan(
        id: planId,
        slug: 'plan-$organizationId',
        name: 'Plan $organizationId',
        description: 'Description $organizationId',
        scheduledFor: DateTime.utc(2026, 4, 5, 9),
        updatedAt: DateTime.utc(2026, 4, 3, 12),
        version: 1,
      ),
    ],
    sessions: [
      PlanningSyncSession(
        id: 'session-$organizationId',
        planId: planId,
        slug: 'session-$organizationId',
        position: 10,
        name: 'Session $organizationId',
        version: 1,
      ),
    ],
    items: [
      PlanningSyncSessionItem(
        id: 'item-$organizationId',
        planId: planId,
        sessionId: 'session-$organizationId',
        position: 10,
        songId: 'song-$organizationId',
        songTitle: 'Song $organizationId',
      ),
    ],
  );
}

class _FakePlanningRemoteRefreshRepository
    implements PlanningRemoteRefreshRepository {
  int fetchCallCount = 0;
  Object? error;
  Future<PlanningSyncPayload>? nextPayload;
  final Map<String, Future<PlanningSyncPayload>> payloadsByOrganizationId = {};

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    fetchCallCount += 1;

    if (error != null) {
      throw error!;
    }

    final deferredPayload = nextPayload;
    if (deferredPayload != null) {
      nextPayload = null;
      return deferredPayload;
    }

    final payload = payloadsByOrganizationId[organizationId];
    if (payload != null) {
      return payload;
    }

    return _payloadFor(organizationId);
  }
}

class _BlockingPlanningLocalStore implements PlanningLocalStore {
  _BlockingPlanningLocalStore({
    required this.replaceStarted,
    required this.commitGate,
  });

  final Completer<void> replaceStarted;
  final Completer<void> commitGate;
  final Map<String, Map<String, PlanDetail>> _detailsByOrg = {};

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) async {
    replaceStarted.complete();
    await commitGate.future;
    if (shouldContinue != null && !shouldContinue()) {
      throw const PlanningProjectionAbortedException();
    }

    _detailsByOrg[organizationId] = {
      for (final plan in plans)
        plan.id: PlanDetail(
          plan: PlanSummary(
            id: plan.id,
            slug: plan.slug,
            name: plan.name,
            description: plan.description,
            scheduledFor: plan.scheduledFor,
            updatedAt: plan.updatedAt,
          ),
          sessions: const [],
        ),
    };
  }

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) async {
    return _detailsByOrg[organizationId]?.values
            .map((detail) => detail.plan)
            .toList(growable: false) ??
        const [];
  }

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) async {
    return _detailsByOrg[organizationId]?[planId];
  }

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async {
    final details = _detailsByOrg[organizationId]?.values;
    if (details == null) {
      return null;
    }

    for (final detail in details) {
      if (detail.plan.slug == planSlug) {
        return detail.plan;
      }
    }
    return null;
  }

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async {
    final details = _detailsByOrg[organizationId]?.values;
    if (details == null) {
      return null;
    }

    for (final detail in details) {
      if (detail.plan.slug == planSlug) {
        return detail;
      }
    }
    return null;
  }

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async {
    return _detailsByOrg.containsKey(organizationId);
  }

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    return 0;
  }

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async {
    return _detailsByOrg.keys.isEmpty ? null : _detailsByOrg.keys.first;
  }

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {
    _detailsByOrg.remove(organizationId);
  }

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {
    _detailsByOrg.clear();
  }

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
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

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
}

class _BlockingBoundaryDeletePlanningLocalStore implements PlanningLocalStore {
  _BlockingBoundaryDeletePlanningLocalStore(this._delegate);

  final PlanningLocalStore _delegate;
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> _deleteGate = Completer<void>();

  void releaseDelete() {
    if (!_deleteGate.isCompleted) {
      _deleteGate.complete();
    }
  }

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return _delegate.countSongReferences(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {
    if (!deleteStarted.isCompleted) {
      deleteStarted.complete();
    }
    await _deleteGate.future;
    await _delegate.deletePlanningData(
      userId: userId,
      organizationId: organizationId,
      shouldContinue: shouldContinue,
    );
  }

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) {
    return _delegate.deletePlanningDataForUser(
      userId: userId,
      shouldContinue: shouldContinue,
    );
  }

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) {
    return _delegate.deleteSyncedSession(
      userId: userId,
      organizationId: organizationId,
      sessionId: sessionId,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.deleteSyncedSessionItem(
      userId: userId,
      organizationId: organizationId,
      sessionId: sessionId,
      sessionItemId: sessionItemId,
      sessionVersion: sessionVersion,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) {
    return _delegate.hasProjection(
      userId: userId,
      organizationId: organizationId,
    );
  }

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) {
    return _delegate.readPlanDetail(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
    );
  }

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) {
    return _delegate.readPlanDetailBySlug(
      userId: userId,
      organizationId: organizationId,
      planSlug: planSlug,
    );
  }

  @override
  Future<String?> readLatestCachedOrganizationId({required String userId}) {
    return _delegate.readLatestCachedOrganizationId(userId: userId);
  }

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) {
    return _delegate.readPlanSummaries(
      userId: userId,
      organizationId: organizationId,
    );
  }

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) {
    return _delegate.readPlanSummaryBySlug(
      userId: userId,
      organizationId: organizationId,
      planSlug: planSlug,
    );
  }

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) {
    return _delegate.replaceActiveProjection(
      userId: userId,
      organizationId: organizationId,
      plans: plans,
      sessions: sessions,
      items: items,
      refreshedAt: refreshedAt,
      shouldContinue: shouldContinue,
    );
  }

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.replaceSyncedSessionItemOrder(
      userId: userId,
      organizationId: organizationId,
      sessionId: sessionId,
      orderedSessionItemIds: orderedSessionItemIds,
      orderedSessionItemPositions: orderedSessionItemPositions,
      sessionVersion: sessionVersion,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.replaceSyncedSessionOrder(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
      orderedSessionIds: orderedSessionIds,
      orderedSessionPositions: orderedSessionPositions,
      planVersion: planVersion,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) {
    return _delegate.upsertSyncedPlan(
      userId: userId,
      organizationId: organizationId,
      plan: plan,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) {
    return _delegate.upsertSyncedSession(
      userId: userId,
      organizationId: organizationId,
      session: session,
      refreshedAt: refreshedAt,
    );
  }

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) {
    return _delegate.upsertSyncedSessionItem(
      userId: userId,
      organizationId: organizationId,
      item: item,
      sessionVersion: sessionVersion,
      refreshedAt: refreshedAt,
    );
  }
}
