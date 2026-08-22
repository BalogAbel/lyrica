import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AppAuthSessionReader = AppAuthSession? Function();
typedef ActiveOrganizationReader = Future<String?> Function();
typedef CatalogSessionVerifier = Future<CatalogSessionStatus> Function();

// Reads the (userId, organizationId) pair last seen while authenticated, if
// any is on record. Deliberately a plain record rather than a dependency on
// the auth layer's LastKnownIdentity type, so this controller stays decoupled
// from that module. See docs/specs/2026-08-19-local-data-durability-contract.md
// (D3).
typedef LastKnownIdentityReader =
    ({String userId, String? organizationId})? Function();

const _defaultRefreshInterval = Duration(minutes: 5);

class SongCatalogController extends ChangeNotifier {
  SongCatalogController({
    required this._store,
    required this._localDataLifecycle,
    required this._remoteRepository,
    required this._authSessionReader,
    required this._organizationReader,
    required this._sessionVerifier,
    required this._onImplausibleEmptySnapshot,
    this._onVerifiedEmptyMembership,
    this._lastKnownIdentityReader,
    AppForegroundState? foregroundState,
    this._refreshInterval = _defaultRefreshInterval,
  }) : _foregroundState = foregroundState ?? _AlwaysForegroundState(),
       _state = const CatalogSnapshotState.initial() {
    _foregroundSubscription = _foregroundState.watchForeground().listen(
      _handleForegroundChange,
    );
    _updateRefreshScheduler();
  }

  final SongCatalogStore _store;
  final LocalDataLifecycle _localDataLifecycle;
  final SongRepository _remoteRepository;
  final AppAuthSessionReader _authSessionReader;
  final ActiveOrganizationReader _organizationReader;
  final CatalogSessionVerifier _sessionVerifier;
  // D4 (docs/specs/2026-08-19-local-data-durability-contract.md): best-effort
  // audit hook invoked when an incoming empty listSongs() response is
  // rejected against a non-empty cached snapshot (SongCatalogStore
  // .resolveEmptySnapshot returned reject). A failure here must never break
  // the refresh -- see the try/catch around its call site in
  // _refreshCatalog.
  final Future<void> Function({
    required String userId,
    required String organizationId,
  })
  _onImplausibleEmptySnapshot;
  final Future<void> Function({required String userId})?
  _onVerifiedEmptyMembership;
  final LastKnownIdentityReader? _lastKnownIdentityReader;
  final AppForegroundState _foregroundState;
  final Duration _refreshInterval;

  CatalogSnapshotState _state;
  int _refreshGeneration = 0;
  bool _disposed = false;
  String? _lastAuthenticatedUserId;
  bool _verifiedEmptyMembershipSeen = false;
  Timer? _refreshTimer;
  StreamSubscription<bool>? _foregroundSubscription;
  Future<void>? _refreshFuture;
  // The session identity (AppAuthSession.userId, nullable) the current
  // _refreshFuture was dispatched under. Only meaningful while _refreshFuture
  // is non-null. See docs/specs/2026-08-08-web-catalog-refresh-race.md (D1).
  String? _refreshFutureUserId;
  // At most one follow-up refresh queued behind the in-flight one, for
  // callers whose session identity differs from _refreshFutureUserId. Kept
  // to a single slot so a burst of differing-identity triggers cannot fan
  // out into a refresh storm; every such caller shares this one completer.
  Completer<void>? _pendingFollowUpRefresh;

  CatalogSnapshotState get state => _state;

  // Coalescing here used to be presence-based: "some refresh is in flight"
  // was treated as "the refresh you asked for will happen". That is false
  // when the in-flight refresh was dispatched under a different session
  // identity — e.g. it started with no session, bailed at its first gate,
  // and a moment later the auth stream emits signedIn in the same turn. The
  // signed-in caller would get handed back the doomed null-session future
  // instead of a real refresh, and nothing would retrigger it. See
  // docs/specs/2026-08-08-web-catalog-refresh-race.md (D1) for the full
  // repro and the coalescing contract this implements: same identity still
  // coalesces (sign-out overlap tests depend on that), a different identity
  // gets exactly one queued follow-up that runs once the in-flight refresh
  // settles, and the caller's future completes only after that follow-up.
  Future<void> refreshCatalog() async {
    final requestedUserId = _authSessionReader()?.userId;
    final inFlightRefresh = _refreshFuture;
    if (inFlightRefresh != null) {
      if (requestedUserId == _refreshFutureUserId) {
        return inFlightRefresh;
      }

      final pendingFollowUp = _pendingFollowUpRefresh;
      if (pendingFollowUp != null) {
        return pendingFollowUp.future;
      }

      final followUpCompleter = Completer<void>();
      _pendingFollowUpRefresh = followUpCompleter;
      unawaited(
        inFlightRefresh.whenComplete(() async {
          _pendingFollowUpRefresh = null;
          if (_disposed) {
            followUpCompleter.complete();
            return;
          }
          try {
            await refreshCatalog();
            followUpCompleter.complete();
          } catch (error, stackTrace) {
            followUpCompleter.completeError(error, stackTrace);
          }
        }),
      );
      return followUpCompleter.future;
    }

    _refreshFutureUserId = requestedUserId;
    final refreshFuture = _refreshCatalog();
    _refreshFuture = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
        _refreshFutureUserId = null;
      }
    }
  }

  Future<void> _refreshCatalog() async {
    final generation = _refreshGeneration;
    final session = _authSessionReader();
    if (session == null) {
      _verifiedEmptyMembershipSeen = false;
      _setStateIfCurrent(
        generation,
        const CatalogSnapshotState.initial().copyWith(
          sessionStatus: CatalogSessionStatus.expired,
        ),
      );
      return;
    }
    _rememberAuthenticatedUser(session.userId);

    String? organizationId;
    var organizationLookupWasConnectivityFailure = false;
    try {
      organizationId = await _resolveOrganizationId();
    } catch (error) {
      if (_isAuthorizationFailure(error)) {
        _setStateIfCurrent(
          generation,
          const CatalogSnapshotState.initial().copyWith(
            sessionStatus: CatalogSessionStatus.expired,
          ),
        );
        _resetSessionLifecycle();
        return;
      }
      if (_isConnectivityFailure(error)) {
        organizationLookupWasConnectivityFailure = true;
        if (_state.context != null) {
          return;
        }
        if (!_verifiedEmptyMembershipSeen) {
          organizationId = await _store.readLatestCachedOrganizationId(
            userId: session.userId,
          );
        }
      } else {
        _setStateIfCurrent(
          generation,
          _state.context == null
              ? const CatalogSnapshotState.initial().copyWith(
                  sessionStatus: CatalogSessionStatus.verified,
                )
              : _state.copyWith(
                  refreshStatus: CatalogRefreshStatus.failed,
                  sessionStatus: CatalogSessionStatus.verified,
                ),
        );
        return;
      }
    }
    if (_isStale(generation)) {
      return;
    }
    if (organizationId == null) {
      if (organizationLookupWasConnectivityFailure &&
          !_verifiedEmptyMembershipSeen) {
        if (_state.context != null) {
          return;
        }
        _setStateIfCurrent(
          generation,
          _state.copyWith(
            clearContext: true,
            connectionStatus: CatalogConnectionStatus.unavailable,
            refreshStatus: CatalogRefreshStatus.failed,
            sessionStatus: CatalogSessionStatus.unverifiableDueToConnectivity,
            hasCachedCatalog: false,
          ),
        );
        return;
      }
      if (organizationLookupWasConnectivityFailure &&
          _verifiedEmptyMembershipSeen) {
        return;
      }
      _verifiedEmptyMembershipSeen = true;
      final handler = _onVerifiedEmptyMembership;
      if (handler != null) {
        await handler(userId: session.userId);
      } else {
        await _localDataLifecycle.purgeSongCatalog(
          userId: session.userId,
          reason: PurgeReason.membershipRevokedConfirmed,
        );
      }
      if (_isStale(generation)) {
        return;
      }
      _setStateIfCurrent(
        generation,
        const CatalogSnapshotState.initial().copyWith(
          sessionStatus: CatalogSessionStatus.verified,
        ),
      );
      return;
    }

    final context = ActiveCatalogContext(
      userId: session.userId,
      organizationId: organizationId,
    );
    _verifiedEmptyMembershipSeen = false;
    final hasCachedCatalog = await _hasCachedCatalog(context);
    if (_isStale(generation)) {
      return;
    }
    final sessionStatus = await _sessionVerifier();
    if (_isStale(generation)) {
      return;
    }

    if (sessionStatus == CatalogSessionStatus.expired) {
      _setStateIfCurrent(
        generation,
        _state.copyWith(
          clearContext: true,
          connectionStatus: CatalogConnectionStatus.unavailable,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.expired,
          hasCachedCatalog: false,
        ),
      );
      _resetSessionLifecycle();
      return;
    }

    if (sessionStatus == CatalogSessionStatus.unverifiableDueToConnectivity) {
      _setStateIfCurrent(
        generation,
        _state.copyWith(
          context: context,
          connectionStatus: hasCachedCatalog
              ? CatalogConnectionStatus.offlineCached
              : CatalogConnectionStatus.unavailable,
          refreshStatus: CatalogRefreshStatus.failed,
          sessionStatus: CatalogSessionStatus.unverifiableDueToConnectivity,
          hasCachedCatalog: hasCachedCatalog,
        ),
      );
      return;
    }

    _setStateIfCurrent(
      generation,
      _state.copyWith(
        context: context,
        connectionStatus: hasCachedCatalog
            ? CatalogConnectionStatus.online
            : CatalogConnectionStatus.unavailable,
        refreshStatus: CatalogRefreshStatus.refreshing,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: hasCachedCatalog,
      ),
    );

    try {
      final summaries = await _remoteRepository.listSongs();
      if (summaries.isEmpty) {
        final resolution = await _store.resolveEmptySnapshot(
          userId: context.userId,
          organizationId: context.organizationId,
        );
        if (_isStale(generation)) {
          return;
        }
        if (resolution == EmptySnapshotResolution.reject) {
          try {
            await _onImplausibleEmptySnapshot(
              userId: context.userId,
              organizationId: context.organizationId,
            );
          } catch (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'SongCatalogController',
                context: ErrorDescription(
                  'failed to record an implausible-empty snapshot rejection '
                  '-- the rejection itself already applied and is not '
                  'affected',
                ),
              ),
            );
          }
          if (_isStale(generation)) {
            return;
          }
          _setStateIfCurrent(
            generation,
            _state.copyWith(
              context: context,
              connectionStatus: CatalogConnectionStatus.online,
              refreshStatus: CatalogRefreshStatus.implausibleEmpty,
              sessionStatus: CatalogSessionStatus.verified,
              hasCachedCatalog: hasCachedCatalog,
            ),
          );
          return;
        }
      }

      final sources = await Future.wait(
        summaries.map((summary) => _remoteRepository.getSongSource(summary.id)),
      );
      if (_isStale(generation)) {
        return;
      }

      await _store.replaceActiveSnapshot(
        userId: context.userId,
        organizationId: context.organizationId,
        summaries: summaries,
        sources: sources,
        refreshedAt: DateTime.now().toUtc(),
      );
      if (_isStale(generation)) {
        return;
      }

      _setStateIfCurrent(
        generation,
        _state.copyWith(
          context: context,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      );
    } catch (error) {
      if (_isAuthorizationFailure(error)) {
        _setStateIfCurrent(
          generation,
          _state.copyWith(
            clearContext: true,
            connectionStatus: CatalogConnectionStatus.unavailable,
            refreshStatus: CatalogRefreshStatus.failed,
            sessionStatus: CatalogSessionStatus.expired,
            hasCachedCatalog: false,
          ),
        );
        _resetSessionLifecycle();
        return;
      }

      final connectivityFailure = _isConnectivityFailure(error);

      _setStateIfCurrent(
        generation,
        _state.copyWith(
          context: hasCachedCatalog ? context : null,
          clearContext: !hasCachedCatalog,
          connectionStatus: hasCachedCatalog
              ? (connectivityFailure
                    ? CatalogConnectionStatus.offlineCached
                    : CatalogConnectionStatus.online)
              : CatalogConnectionStatus.unavailable,
          refreshStatus: CatalogRefreshStatus.failed,
          sessionStatus: connectivityFailure
              ? CatalogSessionStatus.unverifiableDueToConnectivity
              : CatalogSessionStatus.verified,
          hasCachedCatalog: hasCachedCatalog,
        ),
      );
    }
  }

  Future<void> handleExplicitSignOut() async {
    _resetSessionLifecycle();
    final userId =
        _state.context?.userId ??
        _authSessionReader()?.userId ??
        _lastAuthenticatedUserId;
    _setState(const CatalogSnapshotState.initial());
    if (userId != null) {
      // Same accountDeleted-vs-userSignOut caveat as
      // lastKnownIdentityPersistenceProvider's signedOut case: this code
      // cannot currently distinguish an explicit sign-out from account
      // deletion, so userSignOut is used for both today.
      await _localDataLifecycle.purgeSongCatalog(
        userId: userId,
        reason: PurgeReason.userSignOut,
      );
    }
  }

  void handleSessionExpired() {
    _resetSessionLifecycle();
    _setState(_state.copyWith(sessionStatus: CatalogSessionStatus.expired));
  }

  // Offline-authenticated cold start (D3): establishes context from the last
  // known identity purely from local data, with no network call and no
  // session check. This is a gap-filler for the sessionExpired path, not a
  // general re-resolution mechanism -- it never overwrites an already-valid
  // context, and if no local snapshot exists for the identity it leaves the
  // state exactly as handleSessionExpired() already set it (expired, no
  // context, nothing to show).
  Future<void> handleOfflineAuthenticated() async {
    if (_state.context != null) {
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

    final generation = _refreshGeneration;
    final context = ActiveCatalogContext(
      userId: identity.userId,
      organizationId: organizationId,
    );
    final hasCachedCatalog = await _hasCachedCatalog(context);
    if (_isStale(generation)) {
      return;
    }
    if (_state.context != null) {
      // A concurrent refreshCatalog() -- e.g. connectivity returned moments
      // after a cold start -- may have already established a real, live
      // context while the read above was in flight. An ordinary successful
      // refresh does not bump _refreshGeneration, so the staleness check
      // above cannot catch that on its own; re-check the same guard this
      // method already applies up front, so this offline gap-filler can
      // never clobber a context a newer online refresh just set.
      return;
    }
    if (!hasCachedCatalog) {
      return;
    }

    _setStateIfCurrent(
      generation,
      _state.copyWith(
        context: context,
        connectionStatus: CatalogConnectionStatus.offlineCached,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.expired,
        hasCachedCatalog: true,
      ),
    );
  }

  void handleSessionAvailable() {
    final session = _authSessionReader();
    if (session != null) {
      _rememberAuthenticatedUser(session.userId);
    }
    _updateRefreshScheduler();
  }

  Future<bool> _hasCachedCatalog(ActiveCatalogContext context) async {
    final summaries = await _store.readActiveSummaries(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    return summaries.isNotEmpty;
  }

  Future<String?> _resolveOrganizationId() async {
    return _organizationReader();
  }

  bool _isConnectivityFailure(Object error) {
    return isConnectivityFailure(error);
  }

  bool _isAuthorizationFailure(Object error) {
    if (error is AuthException) {
      return true;
    }

    if (error is PostgrestException) {
      return error.code == '42501' ||
          error.code == '401' ||
          error.code == '403' ||
          error.message.toLowerCase().contains('permission denied');
    }

    return false;
  }

  bool _isStale(int generation) {
    return _disposed || generation != _refreshGeneration;
  }

  void _setStateIfCurrent(int generation, CatalogSnapshotState nextState) {
    if (_isStale(generation)) {
      return;
    }

    _setState(nextState);
  }

  void _setState(CatalogSnapshotState nextState) {
    _state = nextState;
    notifyListeners();
  }

  void _invalidateRefreshWork() {
    _refreshGeneration += 1;
  }

  void _rememberAuthenticatedUser(String userId) {
    _lastAuthenticatedUserId = userId;
  }

  void _handleForegroundChange(bool isForeground) {
    if (!isForeground) {
      _stopRefreshScheduler();
      return;
    }

    _updateRefreshScheduler();
  }

  void _updateRefreshScheduler() {
    if (_disposed) {
      return;
    }

    final session = _authSessionReader();
    final shouldRun = session != null && _foregroundState.isForeground;
    if (!shouldRun) {
      _stopRefreshScheduler();
      return;
    }

    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      if (_authSessionReader() == null || !_foregroundState.isForeground) {
        _stopRefreshScheduler();
        return;
      }

      unawaited(refreshCatalog());
    });
  }

  void _stopRefreshScheduler() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _resetSessionLifecycle() {
    _invalidateRefreshWork();
    _stopRefreshScheduler();
    _verifiedEmptyMembershipSeen = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshGeneration += 1;
    _stopRefreshScheduler();
    unawaited(_foregroundSubscription?.cancel());
    super.dispose();
  }
}

class _AlwaysForegroundState implements AppForegroundState {
  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => const Stream<bool>.empty();
}
