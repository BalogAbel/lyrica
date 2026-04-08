import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
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

    test(
      'overlays local mutation states while hiding pending delete rows from normal reads',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 27, 9),
        );

        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
            slug: 'alpha',
            title: 'Alpha Edited',
            source: '{title: Alpha Edited}',
            syncStatus: SongSyncStatus.pendingUpdate,
            baseVersion: 7,
            syncErrorContext: 'offline while editing',
          ),
        );
        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-2',
            slug: 'beta',
            title: 'Beta',
            source: '{title: Beta}',
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        );
        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-3',
            slug: 'gamma',
            title: 'Gamma',
            source: '{title: Gamma}',
            syncStatus: SongSyncStatus.pendingDelete,
            baseVersion: 2,
            syncErrorContext: 'dependency check deferred',
          ),
        );
        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-4',
            slug: 'delta',
            title: 'Delta',
            source: '{title: Delta}',
            syncStatus: SongSyncStatus.synced,
            baseVersion: 5,
          ),
        );
        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-5',
            slug: 'epsilon',
            title: 'Epsilon',
            source: '{title: Epsilon}',
            syncStatus: SongSyncStatus.conflict,
            baseVersion: 11,
            syncErrorContext: 'server version is newer',
          ),
        );

        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [
            SongSummary(id: 'song-1', title: 'Alpha Edited', slug: 'alpha'),
            SongSummary(id: 'song-2', title: 'Beta', slug: 'beta'),
            SongSummary(id: 'song-5', title: 'Epsilon', slug: 'epsilon'),
          ],
        );

        final updatedSource = await store.readActiveSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );

        expect(updatedSource?.source, '{title: Alpha Edited}');
        expect(
          await store.readActiveSummaryBySlug(
            userId: 'user-1',
            organizationId: 'org-1',
            songSlug: 'gamma',
          ),
          isNull,
        );
        final pendingDeletes = await store.readSongMutations(
          userId: 'user-1',
          organizationId: 'org-1',
          syncStatuses: const [SongSyncStatus.pendingDelete],
        );

        expect(pendingDeletes, hasLength(1));
        expect(pendingDeletes.single.songId, 'song-3');

        final conflictRow = await store.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-5',
        );

        expect(conflictRow?.syncStatus, SongSyncStatus.conflict.value);
        expect(conflictRow?.baseVersion, 11);
        expect(conflictRow?.syncErrorContext, 'server version is newer');
      },
    );

    test(
      'pending mutations shadow snapshot rows that still collide on the same slug',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [
            SongSummary(id: 'song-1', title: 'Alpha', slug: 'alpha'),
          ],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 27, 9),
        );

        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-2',
            slug: 'alpha',
            title: 'Alpha Local',
            source: '{title: Alpha Local}',
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        );

        expect(
          await store.readActiveSummaryBySlug(
            userId: 'user-1',
            organizationId: 'org-1',
            songSlug: 'alpha',
          ),
          const SongSummary(id: 'song-2', title: 'Alpha Local', slug: 'alpha'),
        );
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [
            SongSummary(id: 'song-2', title: 'Alpha Local', slug: 'alpha'),
          ],
        );
      },
    );

    test(
      'allocates unique slugs without reusing pending delete mutation slugs',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [
            SongSummary(id: 'song-1', title: 'Alpha', slug: 'alpha'),
          ],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 27, 10),
        );

        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-2',
            slug: 'alpha-2',
            title: 'Alpha',
            source: '{title: Alpha local delete}',
            syncStatus: SongSyncStatus.pendingDelete,
          ),
        );

        expect(
          await store.readActiveSummaryBySlug(
            userId: 'user-1',
            organizationId: 'org-1',
            songSlug: 'alpha-2',
          ),
          isNull,
        );

        expect(
          await store.allocateAvailableSongSlug(
            userId: 'user-1',
            organizationId: 'org-1',
            title: 'Alpha',
          ),
          'alpha-3',
        );
      },
    );

    test(
      'rejects saving a mutation when another song already reserves its slug',
      () async {
        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
            slug: 'alpha',
            title: 'Alpha',
            source: '{title: Alpha}',
            syncStatus: SongSyncStatus.pendingDelete,
          ),
        );

        await expectLater(
          () => store.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-2',
              slug: 'alpha',
              title: 'Alpha Recreated',
              source: '{title: Alpha Recreated}',
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Local song slug is already reserved'),
            ),
          ),
        );
      },
    );

    test('reconciles the canonical slug after a successful sync', () async {
      await store.saveSongMutation(
        const SongCatalogMutationDraft(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
          slug: 'alpha',
          title: 'Alpha',
          source: '{title: Alpha}',
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );

      await store.reconcileSyncedSong(
        userId: 'user-1',
        organizationId: 'org-1',
        summary: const SongSummary(
          id: 'song-1',
          title: 'Alpha',
          slug: 'alpha-2',
          version: 12,
        ),
        source: const SongSource(
          id: 'song-1',
          source: '{title: Alpha canonical}',
        ),
      );

      final syncedRow = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );

      expect(syncedRow, isNull);
      expect(
        await store.readActiveSummaryBySlug(
          userId: 'user-1',
          organizationId: 'org-1',
          songSlug: 'alpha',
        ),
        isNull,
      );
      expect(
        await store.readActiveSummaryBySlug(
          userId: 'user-1',
          organizationId: 'org-1',
          songSlug: 'alpha-2',
        ),
        const SongSummary(
          id: 'song-1',
          title: 'Alpha',
          slug: 'alpha-2',
          version: 12,
        ),
      );
      final canonicalSource = await store.readActiveSource(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(canonicalSource?.source, '{title: Alpha canonical}');
    });

    test('purges a single song from snapshot and mutation storage', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 27, 11),
      );
      await store.saveSongMutation(
        const SongCatalogMutationDraft(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
          slug: 'alpha',
          title: 'Alpha',
          source: '{title: Alpha pending delete}',
          syncStatus: SongSyncStatus.pendingDelete,
          baseVersion: 3,
        ),
      );

      await store.deleteSong(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );

      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
      expect(
        await store.readSongMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    });
  });
}
