import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

void main() {
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
        name: 'Plan $organizationId',
        description: 'Description $organizationId',
        scheduledFor: DateTime.utc(2026, 4, 5, 9),
        updatedAt: DateTime.utc(2026, 4, 3, 12),
      ),
    ],
    sessions: [
      PlanningSyncSession(
        id: 'session-$organizationId',
        planId: planId,
        position: 10,
        name: 'Session $organizationId',
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
