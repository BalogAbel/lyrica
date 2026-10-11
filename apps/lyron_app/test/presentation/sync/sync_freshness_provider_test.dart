import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late SongCatalogDatabase songs;
  late PlanningLocalDatabase plans;

  setUp(() async {
    songs = SongCatalogDatabase.inMemory();
    plans = PlanningLocalDatabase.inMemory();
    final store = DriftSongCatalogStore(songs);
    for (final entry in {
      'user-1': (DateTime.utc(2026, 10, 1, 8), DateTime.utc(2026, 10, 2, 9)),
      'user-2': (DateTime.utc(2026, 9, 1, 8), DateTime.utc(2026, 9, 2, 9)),
    }.entries) {
      await store.replaceActiveSnapshot(
        userId: entry.key,
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Song')],
        sources: const [SongSource(id: 'song-1', source: '{title: Song}')],
        refreshedAt: entry.value.$1,
      );
      await plans
          .into(plans.planningProjectionOwners)
          .insert(
            PlanningProjectionOwnersCompanion.insert(
              userId: entry.key,
              organizationId: 'org-1',
              snapshotVersion: 1,
              refreshedAt: entry.value.$2,
            ),
          );
    }
  });

  tearDown(() async {
    await songs.close();
    await plans.close();
  });

  ProviderContainer containerFor(ActiveCatalogContext? context) {
    final container = ProviderContainer(
      overrides: [
        catalogSnapshotStateProvider.overrideWithValue(
          const CatalogSnapshotState.initial(),
        ),
        planningSyncStateProvider.overrideWithValue(
          const PlanningSyncState.initial(),
        ),
        activeCatalogContextProvider.overrideWithValue(context),
        syncFreshnessReaderProvider.overrideWithValue(
          SyncFreshnessReader(
            songCatalogDatabase: songs,
            planningLocalDatabase: plans,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncFreshnessProvider, (_, _) {});
    return container;
  }

  test('yields the active user\'s refresh times, never another user\'s '
      '(SG7)', () async {
    final container = containerFor(
      const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
    );

    final freshness = await container.read(syncFreshnessProvider.future);

    expect(freshness.songsRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 1, 8));
    expect(freshness.plansRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 2, 9));
  });

  test('yields unknown without an active context (SG7)', () async {
    final container = containerFor(null);

    final freshness = await container.read(syncFreshnessProvider.future);

    expect(freshness, const SyncFreshness.unknown());
  });
}
