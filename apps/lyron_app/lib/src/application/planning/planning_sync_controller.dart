import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

typedef PlanningAuthSessionReader = AppAuthSession? Function();
typedef PlanningLocalStoreReader = PlanningLocalStore Function();
typedef PlanningRemoteRefreshRepositoryReader =
    PlanningRemoteRefreshRepository Function();

class PlanningSyncController extends ChangeNotifier {
  PlanningSyncController({
    required PlanningLocalStoreReader localStore,
    required PlanningRemoteRefreshRepositoryReader remoteRepository,
    required PlanningAuthSessionReader authSessionReader,
    DateTime Function()? clock,
  }) : _localStore = localStore,
       _remoteRepository = remoteRepository,
       _authSessionReader = authSessionReader,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _state = const PlanningSyncState.initial();

  final PlanningLocalStoreReader _localStore;
  final PlanningRemoteRefreshRepositoryReader _remoteRepository;
  final PlanningAuthSessionReader _authSessionReader;
  final DateTime Function() _clock;

  PlanningSyncState _state;
  String? _lastAuthenticatedUserId;
  int _refreshGeneration = 0;
  Future<void>? _refreshFuture;
  int? _refreshFutureGeneration;
  bool _refreshQueued = false;
  bool _disposed = false;

  PlanningSyncState get state => _state;

  Future<void> handleActiveContextChanged(
    ActivePlanningReadContext? context, {
    bool refresh = true,
  }) async {
    final session = _authSessionReader();
    if (session == null || context == null) {
      _invalidateRefreshGeneration();
      _setState(
        const PlanningSyncState.initial().copyWith(
          accessStatus: session == null
              ? PlanningAccessStatus.signedOut
              : PlanningAccessStatus.signedIn,
        ),
      );
      return;
    }

    final previousUserId = _state.userId;
    final previousOrganizationId = _state.organizationId;
    final sameBoundary =
        previousUserId == context.userId &&
        previousOrganizationId == context.organizationId;

    if (!sameBoundary) {
      _invalidateRefreshGeneration();
      if (previousUserId != null && previousOrganizationId != null) {
        await _localStore().deletePlanningData(
          userId: previousUserId,
          organizationId: previousOrganizationId,
        );
      }
    }

    final hasProjection = await _localStore().hasProjection(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    _lastAuthenticatedUserId = context.userId;

    _setState(
      _state.copyWith(
        userId: context.userId,
        organizationId: context.organizationId,
        accessStatus: PlanningAccessStatus.signedIn,
        refreshStatus: PlanningRefreshStatus.idle,
        hasLocalPlanningData: hasProjection,
      ),
    );

    if (refresh) {
      await refreshPlanning();
    }
  }

  Future<void> refreshPlanning() async {
    final inFlightRefresh = _refreshFuture;
    if (inFlightRefresh != null) {
      if (_refreshFutureGeneration != _refreshGeneration) {
        _refreshQueued = true;
      }
      return inFlightRefresh;
    }

    final refreshFuture = _drainRefreshQueue();
    _refreshFuture = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
        _refreshFutureGeneration = null;
        _refreshQueued = false;
      }
    }
  }

  Future<void> _drainRefreshQueue() async {
    do {
      _refreshQueued = false;
      _refreshFutureGeneration = _refreshGeneration;
      await _refreshPlanning();
    } while (_shouldContinueQueuedRefresh());
  }

  Future<void> _refreshPlanning() async {
    final generation = _refreshGeneration;
    final userId = _state.userId;
    final organizationId = _state.organizationId;
    final session = _authSessionReader();
    if (_disposed ||
        session == null ||
        userId == null ||
        organizationId == null ||
        _state.accessStatus == PlanningAccessStatus.signedOut) {
      return;
    }

    final hadLocalPlanningData = await _localStore().hasProjection(
      userId: userId,
      organizationId: organizationId,
    );
    if (_isStale(generation)) {
      return;
    }

    _setState(
      _state.copyWith(
        refreshStatus: PlanningRefreshStatus.refreshing,
        hasLocalPlanningData: hadLocalPlanningData,
      ),
    );

    try {
      final payload = await _remoteRepository().fetchPlanningSyncPayload(
        organizationId: organizationId,
      );
      if (_isStale(generation)) {
        return;
      }

      await _replaceProjection(
        userId: userId,
        organizationId: organizationId,
        payload: payload,
        shouldContinue: () => !_isStale(generation),
      );
      if (_isStale(generation)) {
        return;
      }

      _setState(
        _state.copyWith(
          refreshStatus: PlanningRefreshStatus.idle,
          hasLocalPlanningData: true,
          lastRefreshedAt: _clock(),
        ),
      );
    } catch (_) {
      if (_isStale(generation)) {
        return;
      }

      _setState(
        _state.copyWith(
          refreshStatus: PlanningRefreshStatus.failed,
          hasLocalPlanningData: hadLocalPlanningData,
        ),
      );
    }
  }

  Future<void> handleExplicitSignOut() async {
    final userId =
        _state.userId ??
        _authSessionReader()?.userId ??
        _lastAuthenticatedUserId;
    _invalidateRefreshGeneration();
    _setState(
      const PlanningSyncState.initial().copyWith(
        accessStatus: PlanningAccessStatus.signedOut,
      ),
    );

    if (userId != null) {
      await _localStore().deletePlanningDataForUser(userId: userId);
    }
    _lastAuthenticatedUserId = null;
  }

  void handleSessionExpired() {
    _invalidateRefreshGeneration();
    _setState(
      const PlanningSyncState.initial().copyWith(
        accessStatus: PlanningAccessStatus.signedOut,
      ),
    );
  }

  Future<void> _replaceProjection({
    required String userId,
    required String organizationId,
    required PlanningSyncPayload payload,
    required bool Function() shouldContinue,
  }) {
    return _localStore().replaceActiveProjection(
      userId: userId,
      organizationId: organizationId,
      plans: payload.plans
          .map(
            (plan) => CachedPlanRecord(
              id: plan.id,
              name: plan.name,
              description: plan.description,
              scheduledFor: plan.scheduledFor,
              updatedAt: plan.updatedAt,
            ),
          )
          .toList(growable: false),
      sessions: payload.sessions
          .map(
            (session) => CachedSessionRecord(
              id: session.id,
              planId: session.planId,
              position: session.position,
              name: session.name,
            ),
          )
          .toList(growable: false),
      items: payload.items
          .map(
            (item) => CachedSessionItemRecord(
              id: item.id,
              planId: item.planId,
              sessionId: item.sessionId,
              position: item.position,
              songId: item.songId,
              songTitle: item.songTitle,
            ),
          )
          .toList(growable: false),
      refreshedAt: _clock(),
      shouldContinue: shouldContinue,
    );
  }

  bool _isStale(int generation) {
    return _disposed || generation != _refreshGeneration;
  }

  bool _shouldContinueQueuedRefresh() {
    return !_disposed &&
        _refreshQueued &&
        _state.accessStatus != PlanningAccessStatus.signedOut &&
        _state.userId != null &&
        _state.organizationId != null;
  }

  void _invalidateRefreshGeneration() {
    _refreshGeneration += 1;
  }

  void _setState(PlanningSyncState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateRefreshGeneration();
    super.dispose();
  }
}
