import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lyrica_app/src/application/song_library/active_catalog_context.dart';
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

class SongCatalogController extends ChangeNotifier {
  SongCatalogController({
    required SongCatalogStore store,
    required SongRepository remoteRepository,
    required AppAuthSessionReader authSessionReader,
    required ActiveOrganizationReader organizationReader,
    required CatalogSessionVerifier sessionVerifier,
  }) : _store = store,
       _remoteRepository = remoteRepository,
       _authSessionReader = authSessionReader,
       _organizationReader = organizationReader,
       _sessionVerifier = sessionVerifier,
       _state = const CatalogSnapshotState.initial();

  final SongCatalogStore _store;
  final SongRepository _remoteRepository;
  final AppAuthSessionReader _authSessionReader;
  final ActiveOrganizationReader _organizationReader;
  final CatalogSessionVerifier _sessionVerifier;

  CatalogSnapshotState _state;
  int _refreshGeneration = 0;
  bool _disposed = false;

  CatalogSnapshotState get state => _state;

  Future<void> refreshCatalog() async {
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
    _refreshGeneration += 1;
    final context = _state.context ?? await _readCurrentContext();
    if (context != null) {
      await _store.deleteCatalog(
        userId: context.userId,
        organizationId: context.organizationId,
      );
    }

    _setState(const CatalogSnapshotState.initial());
  }

  Future<ActiveCatalogContext?> _readCurrentContext() async {
    final session = _authSessionReader();
    if (session == null) {
      return null;
    }

    final organizationId = await _resolveOrganizationId(session.userId);
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

  @override
  void dispose() {
    _disposed = true;
    _refreshGeneration += 1;
    super.dispose();
  }
}
