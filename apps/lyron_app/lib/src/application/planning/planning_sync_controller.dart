import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/current_user_ownership.dart';
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
  final _ownership = CurrentUserOwnership();

  PlanningSyncState get state => _state;

  /// XU2 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): called
  /// on every signedIn and sessionExpired notification with
  /// AppAuthState.currentUserId, before the status handlers. When the
  /// current user changes, refresh and local-first work started for the
  /// previous user is invalidated, and planning state held for another user
  /// is reset. This runs on the auth edge itself: the I3 guard in
  /// _refreshPlanning runs only if a refresh runs, and _readPlanningOrThrow
  /// skips the refresh while local data is present (F7). Releasing the
  /// previous boundary here also means handleActiveContextChanged finds no
  /// previous boundary to delete when the new user's arrives (F8). In memory
  /// only: no local data is deleted.
  void handleCurrentUser(String currentUserId) {
    final changed = _ownership.observe(currentUserId);
    final heldUserId = _state.userId;
    final holdsForeign = heldUserId != null && heldUserId != currentUserId;
    if (!changed && !holdsForeign) {
      return;
    }
    _advanceBoundaryGeneration();
    _invalidateRefreshGeneration();
    if (holdsForeign) {
      _setState(
        const PlanningSyncState.initial().copyWith(
          accessStatus: PlanningAccessStatus.signedIn,
        ),
      );
    }
  }

  Future<void> handleActiveContextChanged(
    ActivePlanningReadContext? context, {
    bool refresh = true,
  }) async {
    if (context != null && !_ownership.allows(context.userId)) {
      // XU2: a mirrored boundary owned by a user who is no longer current (a
      // notification queued before the user changed) is never adopted, and
      // must not disturb the current user's work.
      return;
    }
    final boundaryGeneration = _advanceBoundaryGeneration();
    final session = _authSessionReader();
    if (context == null) {
      // No catalog-side context to mirror (signed out, or the catalog
      // controller itself cleared its context for one of the 4 invariant
      // causes) -- a reset here is correct and out of scope for I2.
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

    if (session == null) {
      // I2 fix (Opus adversarial review of the whole branch diff,
      // docs/specs/2026-09-28-offline-catalog-local-first-visibility.md):
      // catalog's local-first sets its context under sessionExpired, and
      // that propagates here via activePlanningContextProvider with
      // session == null but a non-null incoming context. That is an
      // AUTH-OUTCOME, not one of the 4 invariant purge causes -- it must
      // be status-only, mirroring the catalog controller's null-session
      // _refreshCatalogBody branch (Task 2.1): if planning already owns
      // this exact (userId, organizationId) boundary, leave it alone.
      // Otherwise, try to re-establish it locally (no network) rather than
      // wiping to initial() and waiting for a later event to recover.
      if (_state.userId == context.userId &&
          _state.organizationId == context.organizationId) {
        _setState(_state.copyWith(accessStatus: PlanningAccessStatus.signedIn));
        return;
      }

      final hasProjection = await _localStore().hasProjection(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      if (_isStaleBoundary(boundaryGeneration)) {
        return;
      }
      if (!hasProjection) {
        _invalidateRefreshGeneration();
        _setState(
          const PlanningSyncState.initial().copyWith(
            accessStatus: PlanningAccessStatus.signedIn,
          ),
        );
        return;
      }
      _lastAuthenticatedUserId = context.userId;
      _setState(
        _state.copyWith(
          userId: context.userId,
          organizationId: context.organizationId,
          accessStatus: PlanningAccessStatus.signedIn,
          refreshStatus: PlanningRefreshStatus.idle,
          hasLocalPlanningData: true,
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
    final session = _authSessionReader();
    if (_disposed || _state.accessStatus == PlanningAccessStatus.signedOut) {
      return;
    }
    // I3 ownership guard (Opus adversarial review of the whole branch diff,
    // docs/specs/2026-09-28-offline-catalog-local-first-visibility.md,
    // Invariant cause 4): _state.userId may have been established for a
    // DIFFERENT user (e.g. while sessionExpired, via local-first) and a
    // different user has since signed in on this device (this call path is
    // new since Task 2.7). Without this check the code below reuses
    // _state.userId/organizationId unrevalidated, silently
    // refreshing/reporting the PRIOR user's stale planning context under
    // the new session. Reset to initial() so local-first / the fetch below
    // run fresh for the CURRENT session's user, mirroring
    // SongCatalogController's equivalent guard in _refreshCatalogBody.
    if (session != null &&
        _state.userId != null &&
        _state.userId != session.userId) {
      _setState(
        const PlanningSyncState.initial().copyWith(
          accessStatus: PlanningAccessStatus.signedIn,
        ),
      );
    }
    var userId = _state.userId;
    var organizationId = _state.organizationId;
    if (session == null || userId == null || organizationId == null) {
      // Task 2.7 (docs/specs/2026-09-28-offline-catalog-local-first
      // -visibility.md, Step 2 item 7): mirrors SongCatalogController's
      // Task 2.5 shape -- a null-session/unresolved-boundary refresh
      // attempt tries to (re-)establish local-first context on EVERY
      // attempt, not only once at the sessionExpired transition (which is
      // all handleOfflineAuthenticated used to cover). Purely a local
      // read; never touches the network.
      await _tryEstablishLocalFirstContext(
        boundaryGeneration: _boundaryGeneration,
      );
      if (_isStale(generation)) {
        return;
      }
      userId = _state.userId;
      organizationId = _state.organizationId;
      if (session == null || userId == null || organizationId == null) {
        return;
      }
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
    // XU5 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): the
    // purge user is the user who signed out -- the last current user this
    // holder observed -- not whatever it last held. Held state and the stale
    // _lastAuthenticatedUserId made one user's sign-out purge another user's
    // planning data, and once XU2 released foreign state the chain could
    // fall through to nobody and keep the signing-out user's own data (F9).
    // The old chain is only the fallback for a holder that never observed a
    // current user.
    final userId =
        _ownership.userId ??
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

  // D5.4/D5.5 (docs/specs/2026-08-19-local-data-durability-contract.md,
  // ADR-035 Phase 4): registered as a VerifiedEmptyMembershipCleanupHandler
  // on the coordinator (planning_providers.dart), which only invokes
  // registered handlers once a purge has genuinely run through
  // LocalDataLifecycle.maybePurgeForMembershipRevocation -- this method's
  // own job is purely to reset THIS controller's in-memory state to match
  // data that is now genuinely gone, not to purge anything itself (that
  // used to happen here directly, on a single unconfirmed resolution --
  // exactly the F4 bug D5 exists to close).
  Future<void> handleVerifiedEmptyMembership({required String userId}) async {
    _advanceBoundaryGeneration();
    _invalidateRefreshGeneration();
    _setState(
      const PlanningSyncState.initial().copyWith(
        accessStatus: PlanningAccessStatus.signedIn,
      ),
    );
  }

  Future<void> handleSessionExpired() async {
    _advanceAuthGeneration();
    _advanceBoundaryGeneration();
    _invalidateRefreshGeneration();
    // I2 (P6) fix (Opus adversarial review of the whole branch diff,
    // docs/specs/2026-09-28-offline-catalog-local-first-visibility.md):
    // this used to unconditionally reset to PlanningSyncState.initial() on
    // EVERY sessionExpired auth notification, wiping an already-established
    // context -- an auth-outcome-driven destructive reset, not one of the 4
    // invariant purge causes. Mirror the catalog controller's
    // handleSessionExpired: status-only when there is a context to
    // preserve, and only fall back to initial() when there genuinely is
    // nothing established yet (so the local-first gap-filler below still
    // has clean state to work from).
    if (_state.userId != null && _state.organizationId != null) {
      _setState(_state.copyWith(accessStatus: PlanningAccessStatus.signedIn));
      return;
    }
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
  // Task 2.7 (docs/specs/2026-09-28-offline-catalog-local-first-visibility.md,
  // Step 2 item 7): thin wrapper around _tryEstablishLocalFirstContext, the
  // same helper _refreshPlanning's null-session branch now also uses. Kept
  // as its own public method (rather than inlined into _refreshPlanning)
  // because it is still called directly, without going through a refresh
  // attempt, at the signedIn -> sessionExpired auth transition
  // (planning_providers.dart).
  Future<void> handleOfflineAuthenticated() async {
    await _tryEstablishLocalFirstContext(
      boundaryGeneration: _boundaryGeneration,
    );
  }

  // Generation guard: this call does not establish a new boundary itself --
  // it passively resolves the current unresolved one from local data -- so
  // the caller captures _boundaryGeneration without advancing it, then this
  // checks _isStaleBoundary against that captured value after the local read
  // completes. Advancing the generation here would be wrong: it would
  // invalidate a concurrent handleActiveContextChanged call that is
  // legitimately establishing a new boundary at the same time.
  Future<void> _tryEstablishLocalFirstContext({
    required int boundaryGeneration,
  }) async {
    if (_state.userId != null && _state.organizationId != null) {
      return;
    }

    final identity = _lastKnownIdentityReader?.call();
    // R2 (PR #79 review, docs/specs/2026-09-28-offline-catalog-local-first
    // -visibility.md): ownership rule, identical to
    // SongCatalogController._tryEstablishLocalFirstContext. With a live
    // session the context is for THAT session's user; the identity's
    // organizationId is only trusted when the identity belongs to the same
    // user. Without a live session (sessionExpired) the identity's user is
    // used; the provider passes only the current user's identity (XU1,
    // docs/specs/2026-10-06-cross-user-local-first-ownership.md), so that
    // is the last known session's user. Using identity.userId unconditionally
    // re-established the PRIOR user's context after _refreshPlanning's I3
    // guard had just cleared it, so a different user's refresh fetched the
    // prior user's org with the new user's token and overwrote the prior
    // user's projection.
    final sessionUserId = _authSessionReader()?.userId;
    final userId = sessionUserId ?? identity?.userId;
    if (userId == null) {
      return;
    }
    // Item 3 (I2 fix, docs/specs/2026-09-28-offline-catalog-local-first
    // -visibility.md): the last-known identity's own organizationId can be
    // null (e.g. membership resolution never completed before the device
    // went offline). Fall back to the store's last-cached organization id
    // for this user, the same fallback SongCatalogController's equivalent
    // helper already has via SongCatalogStore.readLatestCachedOrganizationId
    // -- without it, planning's local-first silently gives up in a case the
    // catalog side already recovers from.
    var organizationId = identity?.userId == userId
        ? identity?.organizationId
        : null;
    organizationId ??= await _localStore().readLatestCachedOrganizationId(
      userId: userId,
    );
    if (_isStaleBoundary(boundaryGeneration)) {
      return;
    }
    if (organizationId == null) {
      return;
    }

    final hasProjection = await _localStore().hasProjection(
      userId: userId,
      organizationId: organizationId,
    );
    if (_isStaleBoundary(boundaryGeneration)) {
      return;
    }
    if (!hasProjection) {
      return;
    }
    if (_state.userId != null && _state.organizationId != null) {
      // A concurrent call (e.g. handleActiveContextChanged) may have
      // already established a real context while this local read was in
      // flight. Never clobber it.
      return;
    }

    _setState(
      _state.copyWith(
        userId: userId,
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
              contentVersion: plan.contentVersion,
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
