import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';

void main() {
  test(
    'refresh failure preserves green header and reports stale freshness',
    () {
      final overview = computeUnifiedSyncOverview(
        UnifiedSyncOverviewInputs(
          catalog: const CatalogSnapshotState(
            context: ActiveCatalogContext(userId: 'u', organizationId: 'o'),
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.failed,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
          songEntries: const [],
          planning: const PlanningSyncState.initial(),
          planningEntries: const [],
        ),
      );
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
      expect(overview.freshness, UnifiedSyncFreshness.stale);
      expect(overview.hasUnsyncedWork, isFalse);
    },
  );

  test('offline cached with no pending stays green', () {
    final overview = computeUnifiedSyncOverview(
      UnifiedSyncOverviewInputs(
        catalog: const CatalogSnapshotState(
          context: ActiveCatalogContext(userId: 'u', organizationId: 'o'),
          connectionStatus: CatalogConnectionStatus.offlineCached,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
        songEntries: const [],
        planning: const PlanningSyncState.initial(),
        planningEntries: const [],
      ),
    );
    expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
    expect(overview.connectivity, UnifiedSyncConnectivity.offline);
    expect(overview.freshness, UnifiedSyncFreshness.offlineCached);
  });
}
