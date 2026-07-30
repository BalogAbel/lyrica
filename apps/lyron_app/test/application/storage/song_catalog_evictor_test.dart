import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('SongCatalogEvictor', () {
    late SongCatalogDatabase database;
    late CatalogStorageAccountant accountant;
    late SongCatalogEvictor evictor;

    setUp(() async {
      database = SongCatalogDatabase.inMemory();
      accountant = CatalogStorageAccountant(database);
      evictor = SongCatalogEvictor(database: database, accountant: accountant);

      await database
          .into(database.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      for (final songId in ['song-clean', 'song-dirty']) {
        await database
            .into(database.cachedCatalogSummaries)
            .insert(
              CachedCatalogSummariesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: songId,
                slug: songId,
                title: songId,
                version: 1,
              ),
            );
        await database
            .into(database.cachedCatalogSources)
            .insert(
              CachedCatalogSourcesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: songId,
                source: 'body ' * 200,
              ),
            );
      }
      await database
          .into(database.cachedCatalogSongMutations)
          .insert(
            CachedCatalogSongMutationsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-dirty',
              slug: 'song-dirty',
              title: 'song-dirty',
              source: 'edited body',
              version: 2,
              syncStatus: 'pending',
            ),
          );
    });

    tearDown(() async {
      await database.close();
    });

    test('drops sources for songs without pending mutations and reports the '
        'bytes freed', () async {
      final before = await accountant.measureCatalogBytes();

      final freed = await evictor.evictDroppable();

      expect(freed, greaterThan(0));
      final after = await accountant.measureCatalogBytes();
      expect(after, before - freed);
    });

    test('never drops the source of a song with a pending mutation', () async {
      await evictor.evictDroppable();

      final sources = await database
          .select(database.cachedCatalogSources)
          .get();
      expect(sources.map((row) => row.songId), ['song-dirty']);
    });

    test('never drops pending song mutations or summaries', () async {
      await evictor.evictDroppable();

      final mutations = await database
          .select(database.cachedCatalogSongMutations)
          .get();
      expect(mutations, hasLength(1));

      final summaries = await database
          .select(database.cachedCatalogSummaries)
          .get();
      expect(summaries, hasLength(2));
    });

    test('is idempotent: a second eviction frees nothing', () async {
      await evictor.evictDroppable();
      expect(await evictor.evictDroppable(), 0);
    });

    test('protects per (user, organization): a different owner with no pending '
        'mutation for the same song id is still evicted', () async {
      // Second owner pair, reusing the song id 'song-dirty' — under
      // user-1/org-1 that id has a pending mutation, but user-2/org-2 has
      // none. If the NOT EXISTS correlation were keyed on song_id alone
      // (ignoring user_id/organization_id), this row would be wrongly
      // protected too.
      await database
          .into(database.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-2',
              organizationId: 'org-2',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      await database
          .into(database.cachedCatalogSummaries)
          .insert(
            CachedCatalogSummariesCompanion.insert(
              userId: 'user-2',
              organizationId: 'org-2',
              snapshotVersion: 1,
              songId: 'song-dirty',
              slug: 'song-dirty',
              title: 'song-dirty',
              version: 1,
            ),
          );
      await database
          .into(database.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-2',
              organizationId: 'org-2',
              snapshotVersion: 1,
              songId: 'song-dirty',
              source: 'body ' * 200,
            ),
          );

      await evictor.evictDroppable();

      final sources = await database
          .select(database.cachedCatalogSources)
          .get();
      final owners = sources
          .map((row) => (row.userId, row.organizationId, row.songId))
          .toSet();

      // user-1/org-1's song-dirty source survives (pending mutation there).
      expect(owners, contains(('user-1', 'org-1', 'song-dirty')));
      // user-2/org-2's song-dirty source is evicted (no pending mutation
      // for that owner, even though the same song id has one elsewhere).
      expect(owners, isNot(contains(('user-2', 'org-2', 'song-dirty'))));
    });
  });
}
