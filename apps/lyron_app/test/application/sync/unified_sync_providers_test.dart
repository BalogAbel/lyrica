import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/storage/local_storage_monitor.dart';
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

  test(
    'unifiedSyncOverviewProvider carries storage pressure and pending mutation count',
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
            (ref) async => const <SongMutationRecord>[],
          ),
          planningMutationEntriesProvider.overrideWith((ref) async => const []),
          planningPlanListProvider.overrideWith((ref) async => const []),
          localStorageFootprintProvider.overrideWith(
            (ref) async => const LocalStorageFootprint(
              mutationBytes: 2 * 1024 * 1024,
              mutationCount: 3,
              projectionBytes: 0,
              catalogBytes: 0,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Resolve FutureProviders before reading the synchronous overview.
      await container.read(songMutationEntriesProvider.future);
      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);
      await container.read(localStorageFootprintProvider.future);

      final overview = container.read(unifiedSyncOverviewProvider);
      expect(overview.storagePressure, LocalStoragePressure.warning);
      expect(overview.pendingMutationCount, 3);
    },
  );

  test('mounted localStorageFootprintProvider remeasures and changes pressure '
      'when the storage revision advances', () async {
    final monitor = _FakeLocalStorageMonitor(
      const LocalStorageFootprint.empty(),
    );
    final container = ProviderContainer(
      overrides: [
        activePlanningContextProvider.overrideWithValue(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        ),
        localStorageMonitorProvider.overrideWithValue(monitor),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      localStorageFootprintProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    final first = await container.read(localStorageFootprintProvider.future);
    expect(
      container.read(localStorageBudgetProvider).classify(first),
      LocalStoragePressure.ok,
    );
    expect(monitor.measurementCount, 1);

    monitor.measurement = const LocalStorageFootprint(
      mutationBytes: 2 * 1024 * 1024,
      mutationCount: 1,
      projectionBytes: 0,
      catalogBytes: 0,
    );
    container.read(localStorageFootprintRevisionProvider.notifier).state += 1;

    final second = await container.read(localStorageFootprintProvider.future);
    expect(monitor.measurementCount, 2);
    expect(
      container.read(localStorageBudgetProvider).classify(second),
      LocalStoragePressure.warning,
    );
  });

  test('unifiedDiscardControllerProvider resolves a controller', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(unifiedDiscardControllerProvider),
      isA<UnifiedDiscardController>(),
    );
  });
}

class _FakeLocalStorageMonitor implements LocalStorageMonitor {
  _FakeLocalStorageMonitor(this.measurement);

  LocalStorageFootprint measurement;
  int measurementCount = 0;

  @override
  Future<LocalStorageFootprint> measure({
    required String userId,
    required String organizationId,
  }) async {
    measurementCount += 1;
    return measurement;
  }

  @override
  LocalStoragePressure pressureOf(LocalStorageFootprint footprint) {
    throw UnsupportedError('The provider classifies the measured footprint.');
  }
}
