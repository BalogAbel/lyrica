import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyrica_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AppAuthSessionReader = AppAuthSession? Function();
typedef ActiveOrganizationReader = Future<String?> Function();
typedef CatalogSessionVerifier = Future<CatalogSessionStatus> Function();

const _defaultRefreshInterval = Duration(minutes: 5);

class SongCatalogController extends ChangeNotifier {
  SongCatalogController({
    required SongCatalogStore store,
    required SongRepository remoteRepository,
    required AppAuthSessionReader authSessionReader,
    required ActiveOrganizationReader organizationReader,
    required CatalogSessionVerifier sessionVerifier,
    AppForegroundState? foregroundState,
    Duration refreshInterval = _defaultRefreshInterval,
  }) : _store = store,
       _remoteRepository = remoteRepository,
       _authSessionReader = authSessionReader,
       _organizationReader = organizationReader,
       _sessionVerifier = sessionVerifier,
       _foregroundState = foregroundState ?? _AlwaysForegroundState(),
       _refreshInterval = refreshInterval,
       _state = const CatalogSnapshotState.initial() {
    _foregroundSubscription = _foregroundState.watchForeground().listen(
      _handleForegroundChange,
    );
    _updateRefreshScheduler();
  }

  final SongCatalogStore _store;
  final SongRepository _remoteRepository;
  final AppAuthSessionReader _authSessionReader;
  final ActiveOrganizationReader _organizationReader;
  final CatalogSessionVerifier _sessionVerifier;
  final AppForegroundState _foregroundState;
  final Duration _refreshInterval;

  CatalogSnapshotState _state;
  int _refreshGeneration = 0;
  bool _disposed = false;
  Timer? _refreshTimer;
  StreamSubscription<bool>? _foregroundSubscription;
  Future<void>? _refreshFuture;

  CatalogSnapshotState get state => _state;

  Future<void> refreshCatalog() async {
    final inFlightRefresh = _refreshFuture;
    if (inFlightRefresh != null) {
      return inFlightRefresh;
    }

    final refreshFuture = _refreshCatalog();
    _refreshFuture = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
      }
    }
  }

  Future<void> _refreshCatalog() async {
    final generation = _refreshGeneration;
    final session = _authSessionReader();
    if (session == null) {
      _setStateIfCurrent(
        generation,
        const CatalogSnapshotState.initial().copyWith(
          sessionStatus: CatalogSessionStatus.expired,
        ),
      );
      return;
    }

    String? organizationId;
    try {
      organizationId = await _resolveOrganizationId(session.userId);
    } catch (error) {
      if (_isAuthorizationFailure(error)) {
        _setStateIfCurrent(
          generation,
          const CatalogSnapshotState.initial().copyWith(
            sessionStatus: CatalogSessionStatus.expired,
          ),
        );
        return;
      }
      rethrow;
    }
    if (_isStale(generation)) {
      return;
    }
    if (organizationId == null) {
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
    _invalidateRefreshWork();
    _stopRefreshScheduler();
    final context = await _readCachedContextForSignOut();
    _setState(const CatalogSnapshotState.initial());
    if (context != null) {
      await _store.deleteCatalog(
        userId: context.userId,
        organizationId: context.organizationId,
      );
    }
  }

  void handleSessionExpired() {
    _invalidateRefreshWork();
    _stopRefreshScheduler();
    _setState(
      const CatalogSnapshotState.initial().copyWith(
        sessionStatus: CatalogSessionStatus.expired,
      ),
    );
  }

  void handleSessionAvailable() {
    _updateRefreshScheduler();
  }

  Future<ActiveCatalogContext?> _readCachedContextForSignOut() async {
    final context = _state.context;
    if (context != null) {
      return context;
    }

    final session = _authSessionReader();
    if (session == null) {
      return null;
    }

    final organizationId = await _store.readLatestCachedOrganizationId(
      userId: session.userId,
    );
    if (organizationId == null) {
      return null;
    }

    return ActiveCatalogContext(
      userId: session.userId,
      organizationId: organizationId,
    );
  }

  Future<bool> _hasCachedCatalog(ActiveCatalogContext context) async {
    final summaries = await _store.readActiveSummaries(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    return summaries.isNotEmpty;
  }

  Future<String?> _resolveOrganizationId(String userId) async {
    try {
      return await _organizationReader();
    } catch (error) {
      if (_isConnectivityFailure(error)) {
        return _store.readLatestCachedOrganizationId(userId: userId);
      }
      rethrow;
    }
  }

  bool _isConnectivityFailure(Object error) {
    return error is SocketException || error is TimeoutException;
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
    _refreshFuture = null;
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
