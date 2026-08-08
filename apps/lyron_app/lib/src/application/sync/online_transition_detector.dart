import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';

typedef OnlineTransitionCallback = void Function();
typedef HasUnsyncedWorkReader = bool Function();

class OnlineTransitionDetector {
  OnlineTransitionDetector({
    required OnlineTransitionCallback onTransitionToOnline,
    HasUnsyncedWorkReader? hasUnsyncedWorkReader,
    this._triggerWhenClean = true,
  }) : _onTransition = onTransitionToOnline,
       _hasUnsyncedWork = hasUnsyncedWorkReader;

  final OnlineTransitionCallback _onTransition;
  final HasUnsyncedWorkReader? _hasUnsyncedWork;
  final bool _triggerWhenClean;

  bool? _previousCatalogOnline;
  bool? _previousPlanningOnline;

  void updateCatalog(CatalogSnapshotState state) {
    final isOnline = _catalogIsOnline(state);
    final previous = _previousCatalogOnline;
    _previousCatalogOnline = isOnline;
    if (previous == null) return;
    if (!previous && isOnline) {
      _maybeFire();
    }
  }

  void updatePlanning(PlanningSyncState state) {
    final isOnline = _planningIsOnline(state);
    final previous = _previousPlanningOnline;
    _previousPlanningOnline = isOnline;
    if (previous == null) return;
    if (!previous && isOnline) {
      _maybeFire();
    }
  }

  void _maybeFire() {
    if (!_triggerWhenClean && _hasUnsyncedWork?.call() == false) {
      return;
    }
    _onTransition();
  }

  static bool _catalogIsOnline(CatalogSnapshotState state) {
    return state.connectionStatus == CatalogConnectionStatus.online &&
        state.refreshStatus != CatalogRefreshStatus.failed;
  }

  static bool _planningIsOnline(PlanningSyncState state) {
    return state.refreshStatus != PlanningRefreshStatus.failed &&
        state.hasLocalPlanningData;
  }
}
