import 'dart:async';

import 'package:flutter/foundation.dart';

class UnifiedManualSyncRunResult {
  const UnifiedManualSyncRunResult({
    required this.songSyncFailed,
    required this.songCatalogRefreshFailed,
    required this.planningSyncFailed,
    required this.planningRefreshFailed,
  });

  const UnifiedManualSyncRunResult.clean()
    : this(
        songSyncFailed: false,
        songCatalogRefreshFailed: false,
        planningSyncFailed: false,
        planningRefreshFailed: false,
      );

  final bool songSyncFailed;
  final bool songCatalogRefreshFailed;
  final bool planningSyncFailed;
  final bool planningRefreshFailed;

  bool get anyFailure =>
      songSyncFailed ||
      songCatalogRefreshFailed ||
      planningSyncFailed ||
      planningRefreshFailed;
}

class UnifiedSyncActiveContext {
  const UnifiedSyncActiveContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

typedef UnifiedSyncContextReader = UnifiedSyncActiveContext? Function();
typedef UnifiedSyncSongStep =
    Future<void> Function(UnifiedSyncActiveContext context);
typedef UnifiedSyncCatalogRefresh = Future<void> Function();
typedef UnifiedSyncPlanningStep =
    Future<void> Function(UnifiedSyncActiveContext context);
typedef UnifiedSyncPlanningRefresh = Future<void> Function();

class UnifiedManualSyncController extends ChangeNotifier {
  UnifiedManualSyncController({
    required this._activeContextReader,
    required this._syncSongMutations,
    required this._refreshSongCatalog,
    required this._syncPlanningMutations,
    required this._refreshPlanning,
  });

  final UnifiedSyncContextReader _activeContextReader;
  final UnifiedSyncSongStep _syncSongMutations;
  final UnifiedSyncCatalogRefresh _refreshSongCatalog;
  final UnifiedSyncPlanningStep _syncPlanningMutations;
  final UnifiedSyncPlanningRefresh _refreshPlanning;

  bool _running = false;
  bool _queued = false;
  Future<UnifiedManualSyncRunResult>? _inFlight;
  UnifiedManualSyncRunResult _lastResult =
      const UnifiedManualSyncRunResult.clean();

  bool get isRunning => _running;
  UnifiedManualSyncRunResult get lastResult => _lastResult;

  Future<UnifiedManualSyncRunResult> syncNow() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _queued = true;
      return inFlight;
    }
    final future = _runUntilQuiescent();
    _inFlight = future;
    _setRunning(true);
    return future.whenComplete(() {
      _inFlight = null;
      _setRunning(false);
    });
  }

  Future<UnifiedManualSyncRunResult> _runUntilQuiescent() async {
    var result = const UnifiedManualSyncRunResult.clean();
    do {
      _queued = false;
      result = await _runOnce();
    } while (_queued);
    _lastResult = result;
    notifyListeners();
    return result;
  }

  Future<UnifiedManualSyncRunResult> _runOnce() async {
    final context = _activeContextReader();
    if (context == null) {
      return const UnifiedManualSyncRunResult.clean();
    }
    var songSyncFailed = false;
    var songCatalogRefreshFailed = false;
    var planningSyncFailed = false;
    var planningRefreshFailed = false;

    try {
      await _syncSongMutations(context);
    } catch (_) {
      songSyncFailed = true;
    }
    try {
      await _refreshSongCatalog();
    } catch (_) {
      songCatalogRefreshFailed = true;
    }
    try {
      await _syncPlanningMutations(context);
    } catch (_) {
      planningSyncFailed = true;
    }
    try {
      await _refreshPlanning();
    } catch (_) {
      planningRefreshFailed = true;
    }
    return UnifiedManualSyncRunResult(
      songSyncFailed: songSyncFailed,
      songCatalogRefreshFailed: songCatalogRefreshFailed,
      planningSyncFailed: planningSyncFailed,
      planningRefreshFailed: planningRefreshFailed,
    );
  }

  void _setRunning(bool running) {
    if (_running == running) return;
    _running = running;
    notifyListeners();
  }
}
