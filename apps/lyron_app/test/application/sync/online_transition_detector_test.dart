import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/sync/online_transition_detector.dart';

CatalogSnapshotState _catalog(CatalogConnectionStatus s) {
  return CatalogSnapshotState(
    context: const ActiveCatalogContext(userId: 'u', organizationId: 'o'),
    connectionStatus: s,
    refreshStatus: CatalogRefreshStatus.idle,
    sessionStatus: CatalogSessionStatus.verified,
    hasCachedCatalog: true,
  );
}

PlanningSyncState _planning({
  PlanningRefreshStatus refresh = PlanningRefreshStatus.idle,
  bool hasLocal = true,
}) {
  return PlanningSyncState(
    userId: 'u',
    organizationId: 'o',
    accessStatus: PlanningAccessStatus.signedIn,
    refreshStatus: refresh,
    hasLocalPlanningData: hasLocal,
    lastRefreshedAt: null,
  );
}

void main() {
  test('catalog offlineCached -> online fires once', () {
    var calls = 0;
    final detector = OnlineTransitionDetector(
      onTransitionToOnline: () => calls++,
    );
    detector.updateCatalog(_catalog(CatalogConnectionStatus.offlineCached));
    detector.updateCatalog(_catalog(CatalogConnectionStatus.online));
    expect(calls, 1);
  });

  test('staying online does not fire repeatedly', () {
    var calls = 0;
    final detector = OnlineTransitionDetector(
      onTransitionToOnline: () => calls++,
    );
    detector.updateCatalog(_catalog(CatalogConnectionStatus.online));
    detector.updateCatalog(_catalog(CatalogConnectionStatus.online));
    expect(calls, 0);
  });

  test('planning failed -> idle fires when hasLocal stays true', () {
    var calls = 0;
    final detector = OnlineTransitionDetector(
      onTransitionToOnline: () => calls++,
    );
    detector.updatePlanning(_planning(refresh: PlanningRefreshStatus.failed));
    detector.updatePlanning(_planning());
    expect(calls, 1);
  });

  test('triggerWhenClean=false suppresses fire when no unsynced work', () {
    var calls = 0;
    final detector = OnlineTransitionDetector(
      triggerWhenClean: false,
      hasUnsyncedWorkReader: () => false,
      onTransitionToOnline: () => calls++,
    );
    detector.updateCatalog(_catalog(CatalogConnectionStatus.unavailable));
    detector.updateCatalog(_catalog(CatalogConnectionStatus.online));
    expect(calls, 0);
  });

  test('triggerWhenClean=false still fires when unsynced work exists', () {
    var calls = 0;
    final detector = OnlineTransitionDetector(
      triggerWhenClean: false,
      hasUnsyncedWorkReader: () => true,
      onTransitionToOnline: () => calls++,
    );
    detector.updateCatalog(_catalog(CatalogConnectionStatus.unavailable));
    detector.updateCatalog(_catalog(CatalogConnectionStatus.online));
    expect(calls, 1);
  });
}
