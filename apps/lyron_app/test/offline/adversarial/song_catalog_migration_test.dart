import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_relaunch.dart';
import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test(
    'a pending song mutation survives a catalog database reopen (LF-T7)',
    () async {
      final file = await createRelaunchDbFile('catalog-migration');
      // Track the currently-open database so a mid-test failure still closes
      // the live connection (and frees the sqlite file) before the temp dir is
      // removed, instead of relying on the explicit close() calls below.
      SongCatalogDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      var db = SongCatalogDatabase.connect(openRelaunchExecutor(file));
      openDb = db;

      await db
          .into(db.cachedCatalogSongMutations)
          .insert(
            CachedCatalogSongMutationsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-local-1',
              slug: 'local-song',
              title: 'Local Song',
              source: '{title: Local Song}',
              version: 1,
              syncStatus: 'pending_create',
            ),
          );

      await db.close();
      openDb = null;

      db = SongCatalogDatabase.connect(openRelaunchExecutor(file));
      openDb = db;

      final rows = await db.select(db.cachedCatalogSongMutations).get();

      expect(rows, hasLength(1));
      expect(rows.single.songId, 'song-local-1');
      expect(rows.single.slug, 'local-song');
      expect(rows.single.title, 'Local Song');
      expect(rows.single.source, '{title: Local Song}');
      expect(rows.single.syncStatus, 'pending_create');

      await db.close();
      openDb = null;
    },
  );
}
