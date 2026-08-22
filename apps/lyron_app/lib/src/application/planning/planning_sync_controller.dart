import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

typedef PlanningAuthSessionReader = AppAuthSession? Function();
typedef PlanningLocalStoreReader = PlanningLocalStore Function();
typedef PlanningRemoteRefreshRepositoryReader =
    PlanningRemoteRefreshRepository Function();

// Reads the (userId, organizationId) pair last seen while authenticated, if
// any is on record. Deliberately a plain record rather than a dependency on
// the auth layer's LastKnownIdentity type, so this controller stays decoupled
// from that module. Mirrors SongCatalogController's identically-shaped
// typedef. See docs/specs/2026-08-19-local-data-durability-contract.md (D3).
typedef LastKnownIdentityReader =
    ({String userId, String? organizationId})? Function();

class PlanningSyncController extends ChangeNotifier {
  PlanningSyncController({
    required this._localStore,
    required this._localDataLifecycle,
    required this._remoteRepository,
    required this._authSessionReader,
    this._lastKnownIdentityReader,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _state = const PlanningSyncState.initial();

  final PlanningLocalStoreReader _localStore;
  final LocalDataLifecycle _localDataLifecycle;
  final PlanningRemoteRefreshRepositoryReader _remoteRepository;
  final PlanningAuthSessionReader _authSessionReader;
  final LastKnownIdentityReader? _lastKnownIdentityReader;
  final DateTime Function() _clock;

  PlanningSyncState _state;
  String? _lastAuthenticatedUserId;
  int _refreshGeneration = 0;
  int _authGeneration = 0;
  int _boundaryGeneration = 0;
  Future<void>? _refreshFuture;
  int? _refreshFutureGeneration;
  bool _refreshQueued = false;
  bool _disposed = false;

  PlanningSyncState get state => _state;

  Future<void> handleActiveContextChanged(
    ActivePlanningReadContext? context, {
    bool refresh = true,
  }) async {
    final boundaryGeneration = _advanceBoundaryGeneration();
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

    _advanceAuthGeneration();

    final previousUserId = _state.userId;
    final previousOrganizationId = _state.organizationId;
    final sameBoundary =
        previousUserId == context.userId &&
        previousOrganizationId == context.organizationId;

    if (!sameBoundary) {
      _invalidateRefreshGeneration();
      if (previousUserId != null && previousOrganizationId != null) {
        try {
          await _localStore().deletePlanningData(
            userId: previousUserId,
            organizationId: previousOrganizationId,
            shouldContinue: () => !_isStaleBoundary(boundaryGeneration),
          );
        } on PlanningProjectionAbortedException {
          return;
        }
      }
    }
    if (_isStaleBoundary(boundaryGeneration)) {
      return;
    }

    final hasProjection = await _localStore().hasProjection(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    if (_isStaleBoundary(boundaryGeneration)) {
      return;
    }
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

  Future<bool> refreshPlanning() async {
    final inFlightRefresh = _refreshFuture;
    if (inFlightRefresh != null) {
      if (_refreshFutureGeneration != _refreshGeneration) {
        _refreshQueued = true;
      }
      await inFlightRefresh;
      return _state.refreshStatus == PlanningRefreshStatus.idle;
    }

    final refreshFuture = _drainRefreshQueue();
    _refreshFuture = refreshFuture;
    try {
      await refreshFuture;
      return _state.refreshStatus == PlanningRefreshStatus.idle;
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
    final generation = _advanceAuthGeneration();
    _advanceBoundaryGeneration();
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
      try {
        // Same accountDeleted-vs-userSignOut caveat as
        // lastKnownIdentityPersistenceProvider's signedOut case: this code
        // cannot currently distinguish an explicit sign-out from account
        // deletion, so userSignOut is used for both today.
        await _localDataLifecycle.purgePlanningData(
          userId: userId,
          reason: PurgeReason.userSignOut,
          shouldContinue: () =>
              !_disposed &&
              generation == _authGeneration &&
              _state.accessStatus == PlanningAccessStatus.signedOut,
        );
      } on PlanningProjectionAbortedException {
        return;
      }
    }
    if (generation == _authGeneration) {
      _lastAuthenticatedUserId = null;
    }
  }

  Future<void> handleVerifiedEmptyMembership({required String userId}) async {
    _advanceBoundaryGeneration();
    _invalidateRefreshGeneration();
    _setState(
      const PlanningSyncState.initial().copyWith(
        accessStatus: PlanningAccessStatus.signedIn,
      ),
    );
    // D5/Phase 4 (ADR-035): planning data is no longer purged here. The
    // destructive/quarantine decision for a verified-empty-membership
    // resolution now happens exactly once, in
    // LocalDataLifecycle.resolveVerifiedEmptyMembership, called directly by
    // VerifiedEmptyMembershipCleanupCoordinator -- this method (invoked as
    // one of the coordinator's registered handlers) only resets this
    // controller's own active-context state.
  }

  Future<void> handleSessionExpired() async {
    _advanceAuthGeneration();
    _advanceBoundaryGeneration();
    _invalidateRefreshGeneration();
    _setState(
      const PlanningSyncState.initial().copyWith(
        accessStatus: PlanningAccessStatus.signedIn,
      ),
    );
  }

  // Offline-authenticated cold start (D3): establishes a read context from
  // the last known identity purely from local data, with no network call and
  // no session check. This is a gap-filler for the sessionExpired path, not a
  // general re-resolution mechanism -- it never overwrites an already-valid
  // context, and if no local projection exists for the identity it leaves the
  // state exactly as handleSessionExpired() already set it (no context,
  // nothing to show).
  //
  // Generation guard: this call does not establish a new boundary itself --
  // it passively resolves the current unresolved one from local data -- so it
  // captures _boundaryGeneration without advancing it, then checks
  // _isStaleBoundary against that captured value after the local read
  // completes. Advancing the generation here would be wrong: it would
  // invalidate a concurrent handleActiveContextChanged call that is
  // legitimately establishing a new boundary at the same time.
  Future<void> handleOfflineAuthenticated() async {
    if (_state.userId != null && _state.organizationId != null) {
      return;
    }

    final identity = _lastKnownIdentityReader?.call();
    if (identity == null) {
      return;
    }
    final organizationId = identity.organizationId;
    if (organizationId == null) {
      return;
    }

    final boundaryGeneration = _boundaryGeneration;
    final hasProjection = await _localStore().hasProjection(
      userId: identity.userId,
      organizationId: organizationId,
    );
    if (_isStaleBoundary(boundaryGeneration)) {
      return;
    }
    if (!hasProjection) {
      return;
    }

    _setState(
      _state.copyWith(
        userId: identity.userId,
        organizationId: organizationId,
        accessStatus: PlanningAccessStatus.signedIn,
        refreshStatus: PlanningRefreshStatus.idle,
        hasLocalPlanningData: true,
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
              slug: plan.slug,
              name: plan.name,
              description: plan.description,
              scheduledFor: plan.scheduledFor,
              updatedAt: plan.updatedAt,
              version: plan.version,
            ),
          )
          .toList(growable: false),
      sessions: payload.sessions
          .map(
            (session) => CachedSessionRecord(
              id: session.id,
              planId: session.planId,
              slug: session.slug,
              position: session.position,
              name: session.name,
              version: session.version,
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

  int _advanceAuthGeneration() {
    _authGeneration += 1;
    return _authGeneration;
  }

  int _advanceBoundaryGeneration() {
    _boundaryGeneration += 1;
    return _boundaryGeneration;
  }

  bool _isStaleBoundary(int generation) {
    return _disposed || generation != _boundaryGeneration;
  }

  void _setState(PlanningSyncState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateRefreshGeneration();
    _advanceBoundaryGeneration();
    super.dispose();
  }
}
