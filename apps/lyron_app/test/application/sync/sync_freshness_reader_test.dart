import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test('reads the persisted refresh times for one user and organization '
      '(SG7)', () async {
    final songs = SongCatalogDatabase.inMemory();
    final plans = PlanningLocalDatabase.inMemory();
    addTearDown(songs.close);
    addTearDown(plans.close);
    await DriftSongCatalogStore(songs).replaceActiveSnapshot(
      userId: 'user-1',
      organizationId: 'org-1',
      summaries: const [SongSummary(id: 'song-1', title: 'Song')],
      sources: const [SongSource(id: 'song-1', source: '{title: Song}')],
      refreshedAt: DateTime.utc(2026, 10, 1, 8),
    );
    await plans
        .into(plans.planningProjectionOwners)
        .insert(
          PlanningProjectionOwnersCompanion.insert(
            userId: 'user-1',
            organizationId: 'org-1',
            snapshotVersion: 1,
            refreshedAt: DateTime.utc(2026, 10, 2, 9),
          ),
        );
    final reader = SyncFreshnessReader(
      songCatalogDatabase: songs,
      planningLocalDatabase: plans,
    );

    final freshness = await reader.read(
      userId: 'user-1',
      organizationId: 'org-1',
    );
    final other = await reader.read(userId: 'user-2', organizationId: 'org-1');

    expect(freshness.songsRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 1, 8));
    expect(freshness.plansRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 2, 9));
    expect(other, const SyncFreshness.unknown());
  });
}
