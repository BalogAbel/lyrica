import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyrica_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SongCatalogStore', () {
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'replaces the active snapshot atomically for one user and organization',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 12),
        );

        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [SongSummary(id: 'song-1', title: 'Alpha')],
        );

        final source = await store.readActiveSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );

        expect(source?.id, 'song-1');
        expect(source?.source, '{title: Alpha}');
      },
    );

    test(
      'hard replaces the previous active snapshot for the same context',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 12),
        );

        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
          sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 13),
        );

        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [SongSummary(id: 'song-2', title: 'Beta')],
        );
        expect(
          await store.readActiveSource(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          ),
          isNull,
        );
      },
    );

    test('keeps only the current cached snapshot for one user', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-2',
        summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
        sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 13),
      );

      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
        const [SongSummary(id: 'song-2', title: 'Beta')],
      );
    });

    test('deletes the cached snapshot for one user and organization', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      await store.deleteCatalog(userId: 'user-1', organizationId: 'org-1');

      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
      expect(
        await store.readActiveSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        ),
        isNull,
      );
    });

    test('reads the latest cached organization context for a user', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-2',
        summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
        sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 13),
      );

      expect(
        await store.readLatestCachedOrganizationId(userId: 'user-1'),
        'org-2',
      );
    });

    test(
      'rejects snapshot replacement when sources do not match summaries',
      () async {
        await expectLater(
          () => store.replaceActiveSnapshot(
            userId: 'user-1',
            organizationId: 'org-1',
            summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
            sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
            refreshedAt: DateTime.utc(2026, 3, 25, 12),
          ),
          throwsArgumentError,
        );

        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          isEmpty,
        );
      },
    );

    test(
      'can reopen a persisted catalog from a new database instance',
      () async {
        final previousDontWarn =
            driftRuntimeOptions.dontWarnAboutMultipleDatabases;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(() {
          driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousDontWarn;
        });

        final tempDir = await Directory.systemTemp.createTemp(
          'song-catalog-store-test',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final dbFile = File(p.join(tempDir.path, 'catalog.sqlite'));
        final firstDatabase = SongCatalogDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        var firstDatabaseClosed = false;
        addTearDown(() async {
          if (firstDatabaseClosed) {
            return;
          }
          firstDatabaseClosed = true;
          await firstDatabase.close();
        });

        final firstStore = DriftSongCatalogStore(firstDatabase);
        await firstStore.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 26, 10),
        );
        await firstDatabase.close();
        firstDatabaseClosed = true;

        final secondDatabase = SongCatalogDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        addTearDown(secondDatabase.close);
        final secondStore = DriftSongCatalogStore(secondDatabase);

        expect(
          await secondStore.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [SongSummary(id: 'song-1', title: 'Alpha')],
        );
        final reopenedSource = await secondStore.readActiveSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(reopenedSource?.id, 'song-1');
        expect(reopenedSource?.source, '{title: Alpha}');
      },
    );
  });
}
