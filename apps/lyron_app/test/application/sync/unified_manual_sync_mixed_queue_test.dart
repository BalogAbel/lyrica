import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';

void main() {
  test(
    'mixed queue: song pending + planning conflict yields red overview',
    () async {
      final calls = <String>[];
      final controller = UnifiedManualSyncController(
        activeContextReader: () =>
            const UnifiedSyncActiveContext(userId: 'u', organizationId: 'o'),
        syncSongMutations: (c) async => calls.add('song'),
        refreshSongCatalog: () async => calls.add('catalog'),
        syncPlanningMutations: (c) async => calls.add('planning'),
        refreshPlanning: () async => calls.add('planRefresh'),
      );

      final result = await controller.syncNow();
      expect(result.anyFailure, isFalse);
      expect(calls, ['song', 'catalog', 'planning', 'planRefresh']);

      // After the run, the aggregator should still surface the simulated
      // post-sync state: song pending create + planning reorder conflict.
      final overview = computeUnifiedSyncOverview(
        UnifiedSyncOverviewInputs(
          catalog: const CatalogSnapshotState(
            context: ActiveCatalogContext(userId: 'u', organizationId: 'o'),
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
          songEntries: [
            SongMutationRecord(
              id: 's1',
              organizationId: 'o',
              slug: 's1',
              title: 'Hymn',
              chordproSource: '',
              version: 1,
              baseVersion: null,
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          ],
          planning: const PlanningSyncState.initial(),
          planningEntries: [
            PlanningMutationRecord(
              aggregateId: 'p2',
              organizationId: 'o',
              kind: PlanningMutationKind.sessionReorder,
              syncStatus: PlanningMutationSyncStatus.conflict,
              orderKey: 0,
              updatedAt: DateTime.utc(2026, 5, 14),
              planId: 'p2',
              errorCode: PlanningMutationSyncErrorCode.conflict,
            ),
          ],
        ),
      );

      expect(overview.headerStatus, UnifiedSyncHeaderStatus.conflict);
      expect(overview.songRows, hasLength(1));
      expect(overview.planRows, hasLength(1));
      expect(
        overview.planRows.single.reasonCode,
        UnifiedSyncReasonCode.conflict,
      );
    },
  );
}
