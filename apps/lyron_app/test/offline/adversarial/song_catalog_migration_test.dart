import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

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

  test(
    'an existing pre-migration (v2) catalog database gains localRevision on '
    'upgrade and keeps its pending row intact (D1, sync-snapshot-identity)',
    () async {
      final file = await createRelaunchDbFile('catalog-migration-v2-v3');
      SongCatalogDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      // Build a genuine pre-migration v2 database by hand, via raw sqlite3
      // (not through SongCatalogDatabase, which would create the CURRENT --
      // post-migration -- schema directly via onCreate and never exercise
      // onUpgrade at all). This is the exact CREATE TABLE text Drift
      // generated for schemaVersion 2, before localRevision existed --
      // captured from `sqlite_master` against that version of the code.
      final rawDb = sqlite3.sqlite3.open(file.path);
      rawDb.execute('''
        CREATE TABLE "cached_catalog_snapshots" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "refreshed_at" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id")
        );
        CREATE TABLE "cached_catalog_summaries" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "song_id" TEXT NOT NULL,
          "slug" TEXT NOT NULL,
          "title" TEXT NOT NULL,
          "version" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "song_id")
        );
        CREATE TABLE "cached_catalog_sources" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "song_id" TEXT NOT NULL,
          "source" TEXT NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "song_id")
        );
        CREATE TABLE "cached_catalog_song_mutations" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "song_id" TEXT NOT NULL,
          "slug" TEXT NOT NULL,
          "title" TEXT NOT NULL,
          "source" TEXT NOT NULL,
          "version" INTEGER NOT NULL,
          "sync_status" TEXT NOT NULL,
          "base_version" INTEGER NULL,
          "sync_error_context" TEXT NULL,
          PRIMARY KEY ("user_id", "organization_id", "song_id"),
          UNIQUE ("user_id", "organization_id", "slug")
        );
      ''');
      rawDb.execute('''
        INSERT INTO cached_catalog_song_mutations (
          user_id, organization_id, song_id, slug, title, source,
          version, sync_status
        ) VALUES (
          'user-1', 'org-1', 'song-pre-migration', 'pre-migration-song',
          'Pre-Migration Song', '{title: Pre-Migration Song}', 1,
          'pending_create'
        );
      ''');
      // Drift tracks the schema version via PRAGMA user_version -- this is
      // what makes onUpgrade(m, from: 2, to: 3) fire below, instead of
      // onCreate (which would build the CURRENT schema directly and never
      // touch the migration code at all).
      rawDb.execute('PRAGMA user_version = 2;');
      rawDb.close();

      final db = SongCatalogDatabase.connect(openRelaunchExecutor(file));
      openDb = db;

      final rows = await db.select(db.cachedCatalogSongMutations).get();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.songId, 'song-pre-migration');
      expect(row.slug, 'pre-migration-song');
      expect(row.title, 'Pre-Migration Song');
      expect(row.source, '{title: Pre-Migration Song}');
      expect(row.syncStatus, 'pending_create');
      expect(
        row.localRevision,
        1,
        reason:
            'a pre-migration row has no sync attempt in flight to '
            'distinguish from -- 1 is a sane starting revision, matching '
            'what a freshly-inserted row gets',
      );

      // The migrated column is real and usable, not just present: a
      // subsequent local write must be able to bump it, exactly as it
      // would for a row that was always on the current schema.
      await db
          .into(db.cachedCatalogSongMutations)
          .insertOnConflictUpdate(
            CachedCatalogSongMutationsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-pre-migration',
              slug: 'pre-migration-song',
              title: 'Edited After Migration',
              source: '{title: Edited After Migration}',
              version: 1,
              syncStatus: 'pending_update',
              localRevision: const Value(2),
            ),
          );
      final afterEdit =
          await (db.select(db.cachedCatalogSongMutations)
                ..where((table) => table.songId.equals('song-pre-migration')))
              .getSingle();
      expect(afterEdit.localRevision, 2);
      expect(afterEdit.title, 'Edited After Migration');

      await db.close();
      openDb = null;
    },
  );
}
