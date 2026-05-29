import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';

void main() {
  test(
    'unifiedSyncOverviewProvider aggregates overridden catalog and song state',
    () async {
      final container = ProviderContainer(
        overrides: [
          catalogSnapshotStateProvider.overrideWithValue(
            const CatalogSnapshotState(
              context: ActiveCatalogContext(userId: 'u', organizationId: 'o'),
              connectionStatus: CatalogConnectionStatus.online,
              refreshStatus: CatalogRefreshStatus.idle,
              sessionStatus: CatalogSessionStatus.verified,
              hasCachedCatalog: true,
            ),
          ),
          planningSyncStateProvider.overrideWithValue(
            const PlanningSyncState.initial(),
          ),
          songMutationEntriesProvider.overrideWith(
            (ref) async => <SongMutationRecord>[
              SongMutationRecord(
                id: 's',
                organizationId: 'o',
                slug: 's',
                title: 'Song',
                chordproSource: '',
                version: 1,
                baseVersion: null,
                syncStatus: SongSyncStatus.pendingCreate,
              ),
            ],
          ),
          planningMutationEntriesProvider.overrideWith((ref) async => const []),
          planningPlanListProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      // Resolve FutureProviders before reading the synchronous overview.
      await container.read(songMutationEntriesProvider.future);
      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);

      final overview = container.read(unifiedSyncOverviewProvider);
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.unsynced);
      expect(overview.songRows.single.title, 'Song');
    },
  );

  test('unifiedDiscardControllerProvider resolves a controller', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(unifiedDiscardControllerProvider),
      isA<UnifiedDiscardController>(),
    );
  });
}
