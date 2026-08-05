import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../support/drift_test_setup.dart';
import '../../support/insert_failing_executor.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

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

    test('reports catalog storage only after the concrete commit', () async {
      final directory = await Directory.systemTemp.createTemp(
        'song-catalog-footprint-revision-test',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final dbFile = File(p.join(directory.path, 'catalog.sqlite'));
      final trackedDatabase = SongCatalogDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      addTearDown(trackedDatabase.close);
      final observer = sqlite3.open(dbFile.path);
      addTearDown(observer.close);
      final committedRowCounts = <int>[];
      final trackedStore = DriftSongCatalogStore(
        trackedDatabase,
        onStorageFootprintChanged: () {
          final row = observer
              .select(
                'SELECT count(*) AS row_count FROM cached_catalog_song_mutations',
              )
              .single;
          committedRowCounts.add(row['row_count'] as int);
        },
      );

      await trackedStore.saveSongMutation(
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

      expect(committedRowCounts, [1]);
    });

    test('does not report a catalog throw or true no-op', () async {
      var revisionCount = 0;
      final trackedStore = DriftSongCatalogStore(
        database,
        onStorageFootprintChanged: () => revisionCount += 1,
      );
      const mutation = SongCatalogMutationDraft(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
        slug: 'alpha',
        title: 'Alpha',
        source: '{title: Alpha}',
        syncStatus: SongSyncStatus.pendingCreate,
      );

      await trackedStore.clearSongMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'missing-song',
      );
      expect(revisionCount, 0);

      await trackedStore.saveSongMutation(mutation);
      expect(revisionCount, 1);

      await expectLater(
        () => trackedStore.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-2',
            slug: 'alpha',
            title: 'Duplicate slug',
            source: '{title: Duplicate slug}',
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        ),
        throwsA(isA<LocalSongSlugConflictException>()),
      );
      expect(revisionCount, 1);
    });

    test('does not report an identical song-mutation upsert', () async {
      var revisionCount = 0;
      final trackedStore = DriftSongCatalogStore(
        database,
        onStorageFootprintChanged: () => revisionCount += 1,
      );
      const mutation = SongCatalogMutationDraft(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
        slug: 'alpha',
        title: 'Alpha',
        source: '{title: Alpha}',
        syncStatus: SongSyncStatus.pendingCreate,
      );

      await trackedStore.saveSongMutation(mutation);
      expect(revisionCount, 1);

      await trackedStore.saveSongMutation(mutation);
      expect(revisionCount, 1);
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

    test(
      'deletes the cached snapshot and pending song mutations for one user and organization',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
          sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 12),
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

        await store.deleteCatalogsForUser(userId: 'user-1');

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
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
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
        });
      },
    );

    test(
      'reopens pending create mutations with durable overlay reads',
      () async {
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
          final tempDir = await Directory.systemTemp.createTemp(
            'song-catalog-store-test-pending-create',
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
          final firstStore = DriftSongCatalogStore(firstDatabase);

          await firstStore.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-local-1',
              slug: 'local-song',
              title: 'Local Song',
              source: '{title: Local Song}',
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          );
          await firstDatabase.close();

          final secondDatabase = SongCatalogDatabase.connect(
            NativeDatabase.createInBackground(dbFile),
          );
          addTearDown(secondDatabase.close);
          final secondStore = DriftSongCatalogStore(secondDatabase);

          expect(
            await secondStore.readSongMutations(
              userId: 'user-1',
              organizationId: 'org-1',
              syncStatuses: const [SongSyncStatus.pendingCreate],
            ),
            hasLength(1),
          );
          expect(
            await secondStore.readActiveSummaries(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            const [
              SongSummary(
                id: 'song-local-1',
                title: 'Local Song',
                slug: 'local-song',
              ),
            ],
          );
          final reopenedSource = await secondStore.readActiveSource(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-local-1',
          );
          expect(reopenedSource?.id, 'song-local-1');
          expect(reopenedSource?.source, '{title: Local Song}');
        });
      },
    );

    test(
      'reopens pending update mutations with durable overlay reads',
      () async {
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
          final tempDir = await Directory.systemTemp.createTemp(
            'song-catalog-store-test-pending-update',
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
          final firstStore = DriftSongCatalogStore(firstDatabase);

          await firstStore.replaceActiveSnapshot(
            userId: 'user-1',
            organizationId: 'org-1',
            summaries: const [
              SongSummary(id: 'song-1', title: 'Alpha', slug: 'alpha'),
            ],
            sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
            refreshedAt: DateTime.utc(2026, 3, 26, 10),
          );
          await firstStore.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
              slug: 'alpha-edited',
              title: 'Alpha Edited',
              source: '{title: Alpha Edited}',
              syncStatus: SongSyncStatus.pendingUpdate,
              baseVersion: 7,
              syncErrorContext: 'offline while editing',
            ),
          );
          await firstDatabase.close();

          final secondDatabase = SongCatalogDatabase.connect(
            NativeDatabase.createInBackground(dbFile),
          );
          addTearDown(secondDatabase.close);
          final secondStore = DriftSongCatalogStore(secondDatabase);

          expect(
            await secondStore.readSongMutations(
              userId: 'user-1',
              organizationId: 'org-1',
              syncStatuses: const [SongSyncStatus.pendingUpdate],
            ),
            hasLength(1),
          );
          expect(
            await secondStore.readActiveSummaryBySlug(
              userId: 'user-1',
              organizationId: 'org-1',
              songSlug: 'alpha',
            ),
            isNull,
          );
          expect(
            await secondStore.readActiveSummaryBySlug(
              userId: 'user-1',
              organizationId: 'org-1',
              songSlug: 'alpha-edited',
            ),
            const SongSummary(
              id: 'song-1',
              title: 'Alpha Edited',
              slug: 'alpha-edited',
            ),
          );
          final reopenedSource = await secondStore.readActiveSource(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          );
          expect(reopenedSource?.source, '{title: Alpha Edited}');
          final reopenedMutation = await secondStore.readSongMutationBySongId(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          );
          expect(reopenedMutation?.baseVersion, 7);
          expect(reopenedMutation?.syncErrorContext, 'offline while editing');
        });
      },
    );

    test(
      'reopens pending delete mutations with durable sync replay rows',
      () async {
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
          final tempDir = await Directory.systemTemp.createTemp(
            'song-catalog-store-test-pending-delete',
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
          final firstStore = DriftSongCatalogStore(firstDatabase);

          await firstStore.replaceActiveSnapshot(
            userId: 'user-1',
            organizationId: 'org-1',
            summaries: const [
              SongSummary(id: 'song-1', title: 'Alpha', slug: 'alpha'),
            ],
            sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
            refreshedAt: DateTime.utc(2026, 3, 26, 10),
          );
          await firstStore.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
              slug: 'alpha',
              title: 'Alpha',
              source: '{title: Alpha pending delete}',
              syncStatus: SongSyncStatus.pendingDelete,
              baseVersion: 2,
              syncErrorContext: 'dependency check deferred',
            ),
          );
          await firstDatabase.close();

          final secondDatabase = SongCatalogDatabase.connect(
            NativeDatabase.createInBackground(dbFile),
          );
          addTearDown(secondDatabase.close);
          final secondStore = DriftSongCatalogStore(secondDatabase);

          expect(
            await secondStore.readSongMutations(
              userId: 'user-1',
              organizationId: 'org-1',
              syncStatuses: const [SongSyncStatus.pendingDelete],
            ),
            hasLength(1),
          );
          expect(
            await secondStore.readActiveSummaries(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            isEmpty,
          );
          expect(
            await secondStore.readActiveSummaryBySlug(
              userId: 'user-1',
              organizationId: 'org-1',
              songSlug: 'alpha',
            ),
            isNull,
          );
          expect(
            await secondStore.readActiveSource(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
            ),
            isNull,
          );
          final reopenedMutation = await secondStore.readSongMutationBySongId(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          );
          expect(reopenedMutation?.baseVersion, 2);
          expect(
            reopenedMutation?.syncErrorContext,
            'dependency check deferred',
          );
        });
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
      'slug lookup hides the snapshot slug when a local mutation moves the same song to a new slug',
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
            songId: 'song-1',
            slug: 'alpha-edited',
            title: 'Alpha Edited',
            source: '{title: Alpha Edited}',
            syncStatus: SongSyncStatus.pendingUpdate,
            baseVersion: 1,
          ),
        );

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
            songSlug: 'alpha-edited',
          ),
          const SongSummary(
            id: 'song-1',
            title: 'Alpha Edited',
            slug: 'alpha-edited',
          ),
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
      'slugifies accented titles close to backend slugify behavior',
      () async {
        expect(
          await store.allocateAvailableSongSlug(
            userId: 'user-1',
            organizationId: 'org-1',
            title: 'Egy út',
          ),
          'egy-ut',
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
          throwsA(isA<LocalSongSlugConflictException>()),
        );
      },
    );

    test(
      'drift mutation store tolerates malformed sync error payloads',
      () async {
        await database
            .into(database.cachedCatalogSongMutations)
            .insert(
              CachedCatalogSongMutationsCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                songId: 'song-1',
                slug: 'alpha',
                title: 'Alpha',
                source: '{title: Alpha}',
                version: 1,
                syncStatus: 'pending_update',
                syncErrorContext: Value('not-json'),
              ),
            );

        final mutationStore = DriftSongMutationStore(
          songCatalogStore: store,
          planningLocalStore: const _NoopPlanningLocalStore(),
        );

        final record = await mutationStore.readById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );

        expect(record, isNotNull);
        expect(record?.errorCode, isNull);
        expect(record?.errorMessage, 'not-json');
      },
    );

    test(
      'drift mutation store tolerates unknown conflict source sync status values',
      () async {
        await database
            .into(database.cachedCatalogSongMutations)
            .insert(
              CachedCatalogSongMutationsCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                songId: 'song-1',
                slug: 'alpha',
                title: 'Alpha',
                source: '{title: Alpha}',
                version: 1,
                syncStatus: 'conflict',
                syncErrorContext: Value(
                  '{"code":"conflict","message":"server conflict","conflictSourceSyncStatus":"mystery_status"}',
                ),
              ),
            );

        final mutationStore = DriftSongMutationStore(
          songCatalogStore: store,
          planningLocalStore: const _NoopPlanningLocalStore(),
        );

        final record = await mutationStore.readById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );

        expect(record, isNotNull);
        expect(record?.errorCode, SongMutationSyncErrorCode.conflict);
        expect(record?.errorMessage, 'server conflict');
        expect(record?.conflictSourceSyncStatus, isNull);
      },
    );

    test(
      'drift mutation store preserves remote-delete metadata in sync error context',
      () async {
        final mutationStore = DriftSongMutationStore(
          songCatalogStore: store,
          planningLocalStore: const _NoopPlanningLocalStore(),
        );

        await mutationStore.upsertSong(
          userId: 'user-1',
          record: const SongMutationRecord(
            id: 'song-1',
            organizationId: 'org-1',
            slug: 'alpha',
            title: 'Alpha',
            chordproSource: '{title: Alpha}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.conflict,
            errorCode: SongMutationSyncErrorCode.remoteDeleted,
            errorMessage: 'song_not_found',
            conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
          ),
        );

        final stored = await store.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        final reread = await mutationStore.readById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );

        expect(stored?.syncErrorContext, contains('"code":"remoteDeleted"'));
        expect(
          stored?.syncErrorContext,
          contains('"conflictSourceSyncStatus":"pending_update"'),
        );
        expect(reread?.errorCode, SongMutationSyncErrorCode.remoteDeleted);
        expect(reread?.conflictSourceSyncStatus, SongSyncStatus.pendingUpdate);
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

  group('DriftSongCatalogStore storage recovery (D1)', () {
    // Every test below wires a real DriftSongCatalogStore whose underlying
    // executor fails every INSERT, and a real LocalStorageWriteRecovery
    // backed by a SECOND, unwrapped SongCatalogDatabase seeded with one
    // droppable source -- mirroring the two-database shape
    // storage_pressure_contract_test.dart already uses for the (unchanged)
    // planning-mutation path, so a storage failure on the guarded database
    // never fights with eviction reads/deletes on the catalog database.
    Future<
      ({
        SongCatalogDatabase failingDatabase,
        DriftSongCatalogStore store,
        SongCatalogDatabase evictionDatabase,
        int Function() revisionCount,
      })
    >
    buildGuardedStore({InsertFailureBudget? budget}) async {
      final failingExecutor = InsertFailingExecutor(
        NativeDatabase.memory(),
        budget,
      );
      final failingDatabase = SongCatalogDatabase.connect(failingExecutor);
      final evictionDatabase = SongCatalogDatabase.inMemory();

      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'droppable-song',
              source: 'body ' * 200,
            ),
          );

      var revisionCount = 0;
      final recovery = LocalStorageWriteRecovery(
        evictor: SongCatalogEvictor(
          database: evictionDatabase,
          accountant: CatalogStorageAccountant(evictionDatabase),
          onStorageFootprintChanged: () => revisionCount += 1,
        ),
      );
      final store = DriftSongCatalogStore(
        failingDatabase,
        writeRecovery: recovery,
      );

      return (
        failingDatabase: failingDatabase,
        store: store,
        evictionDatabase: evictionDatabase,
        revisionCount: () => revisionCount,
      );
    }

    test(
      'a failed saveSongMutation write evicts droppable catalog sources, '
      'retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
              slug: 'alpha',
              title: 'Alpha',
              source: '{title: Alpha}',
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          ),
          throwsA(
            isA<LocalStorageWriteFailure>().having(
              (failure) => failure.cause,
              'cause',
              isA<StorageQuotaSimulatedException>(),
            ),
          ),
        );

        expect(built.revisionCount(), 1);
        final remainingSources = await built.evictionDatabase
            .select(built.evictionDatabase.cachedCatalogSources)
            .get();
        expect(remainingSources, isEmpty);

        // Never landed: nothing to read back.
        final mutation = await built.store.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(mutation, isNull);
      },
    );

    test('a saveSongMutation write that fails once and succeeds on retry lands '
        'the mutation, after evicting droppable catalog sources', () async {
      final built = await buildGuardedStore(
        budget: InsertFailureBudget(failuresRemaining: 1),
      );
      addTearDown(built.failingDatabase.close);
      addTearDown(built.evictionDatabase.close);

      await built.store.saveSongMutation(
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

      final remainingSources = await built.evictionDatabase
          .select(built.evictionDatabase.cachedCatalogSources)
          .get();
      expect(remainingSources, isEmpty);

      final mutation = await built.store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(mutation, isNotNull);
      expect(mutation!.title, 'Alpha');
    });

    test(
      'a failed replaceActiveSnapshot write evicts droppable catalog '
      'sources, retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.replaceActiveSnapshot(
            userId: 'user-1',
            organizationId: 'org-1',
            summaries: const [SongSummary(id: 'song-1', title: 'Song One')],
            sources: const [SongSource(id: 'song-1', source: 'chordpro body')],
            refreshedAt: DateTime.utc(2026, 8, 4),
          ),
          throwsA(
            isA<LocalStorageWriteFailure>().having(
              (failure) => failure.cause,
              'cause',
              isA<StorageQuotaSimulatedException>(),
            ),
          ),
        );

        expect(built.revisionCount(), 1);
        final remainingSources = await built.evictionDatabase
            .select(built.evictionDatabase.cachedCatalogSources)
            .get();
        expect(remainingSources, isEmpty);

        final summaries = await built.store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(summaries, isEmpty);
      },
    );

    test(
      'a failed reconcileSyncedSong write evicts droppable catalog sources, '
      'retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.reconcileSyncedSong(
            userId: 'user-1',
            organizationId: 'org-1',
            summary: const SongSummary(
              id: 'song-1',
              title: 'Alpha',
              slug: 'alpha',
              version: 2,
            ),
            source: const SongSource(id: 'song-1', source: '{title: Alpha}'),
          ),
          throwsA(
            isA<LocalStorageWriteFailure>().having(
              (failure) => failure.cause,
              'cause',
              isA<StorageQuotaSimulatedException>(),
            ),
          ),
        );

        expect(built.revisionCount(), 1);
        final remainingSources = await built.evictionDatabase
            .select(built.evictionDatabase.cachedCatalogSources)
            .get();
        expect(remainingSources, isEmpty);

        // Never landed: nothing to read back.
        final summary = await built.store.readActiveSummaryById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(summary, isNull);
      },
    );

    test('domain rejections still pass through a guarded saveSongMutation '
        'without eviction or retry', () async {
      // No fault injection here: the underlying database is a plain,
      // non-failing database, so the ONLY way this can throw is the
      // domain check inside saveSongMutation itself (a slug already
      // reserved by a different song) -- proving the guard recognises it
      // as a LocalStorageDomainRejection rather than storage pressure.
      final database = SongCatalogDatabase.inMemory();
      addTearDown(database.close);
      var evictions = 0;
      final recovery = LocalStorageWriteRecovery(
        evictor: SongCatalogEvictor(
          database: database,
          accountant: CatalogStorageAccountant(database),
          onStorageFootprintChanged: () => evictions += 1,
        ),
      );
      final store = DriftSongCatalogStore(database, writeRecovery: recovery);

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
        throwsA(isA<LocalSongSlugConflictException>()),
      );

      expect(
        evictions,
        0,
        reason: 'a domain rejection must never trigger eviction',
      );
    });
  });

  group('SongCatalogStore.localRevision (D1, sync-snapshot-identity)', () {
    // docs/specs/2026-08-05-sync-snapshot-identity.md D1: localRevision is
    // local bookkeeping incremented by the store on every local write to a
    // mutation row -- unrelated to baseVersion/version (which track the
    // server's view) and never sent to the backend. Unlike planning's
    // several distinct record* writers, every song local write funnels
    // through the single saveSongMutation upsert (including the status
    // write DriftSongMutationStore.saveSyncAttemptResult makes), so this
    // group proves the "every" across that one path: a fold (a second local
    // edit landing on a still-pending row) and a status write.
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('increments by exactly one on every local write, including a fold '
        'and a status write', () async {
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
      final afterCreate = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(
        afterCreate!.localRevision,
        1,
        reason: 'a brand-new row starts at revision 1',
      );

      // Fold: a second local edit before the song ever synced lands in
      // the SAME row (still pendingCreate), not a new one -- the revision
      // must still advance.
      await store.saveSongMutation(
        const SongCatalogMutationDraft(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
          slug: 'alpha',
          title: 'Alpha',
          source: '{title: Edited content}',
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );
      final afterFold = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(afterFold!.localRevision, 2);
      expect(afterFold.source, '{title: Edited content}');

      // A status write (the shape
      // DriftSongMutationStore.saveSyncAttemptResult uses after a failed
      // remote attempt) also advances the revision.
      final mutationStore = DriftSongMutationStore(
        songCatalogStore: store,
        planningLocalStore: const _NoopPlanningLocalStore(),
      );
      await mutationStore.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
        syncStatus: SongSyncStatus.pendingCreate,
        errorCode: SongMutationSyncErrorCode.dependencyBlocked,
        errorMessage: 'blocked',
      );
      final afterStatusWrite = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(afterStatusWrite!.localRevision, 3);
    });

    test('a conditional reconcileSyncedSong that matches applies and returns '
        'true; a stale one does not apply, returns false, and leaves the row '
        'untouched', () async {
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

      // Matching expectedRevision: applies.
      final applied = await store.reconcileSyncedSong(
        userId: 'user-1',
        organizationId: 'org-1',
        summary: const SongSummary(
          id: 'song-1',
          title: 'Alpha',
          slug: 'alpha',
          version: 1,
        ),
        source: const SongSource(id: 'song-1', source: '{title: Alpha}'),
        expectedRevision: 1,
      );
      expect(applied, isTrue);
      expect(
        await store.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        ),
        isNull,
      );

      // A second song, edited once more after the snapshot a sync would
      // have captured: a reconcile keyed to the STALE revision must not
      // apply.
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
          songId: 'song-2',
          slug: 'beta',
          title: 'Beta',
          source: '{title: Beta edited}',
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );

      final stale = await store.reconcileSyncedSong(
        userId: 'user-1',
        organizationId: 'org-1',
        summary: const SongSummary(
          id: 'song-2',
          title: 'Beta',
          slug: 'beta',
          version: 1,
        ),
        source: const SongSource(id: 'song-2', source: '{title: Beta}'),
        expectedRevision: 1,
      );
      expect(stale, isFalse);

      final record = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-2',
      );
      expect(
        record,
        isNotNull,
        reason: 'the stale attempt must not have deleted the row',
      );
      expect(record!.localRevision, 2);
      expect(
        record.source,
        '{title: Beta edited}',
        reason: 'the stale attempt must not have overwritten anything',
      );
      // readActiveSummaryById overlays the still-pending mutation row
      // above the snapshot table, so it is not the right probe for "did
      // the snapshot write happen" -- query the raw snapshot table
      // directly instead.
      final rawSummaryRows = await (database.select(
        database.cachedCatalogSummaries,
      )..where((table) => table.songId.equals('song-2'))).get();
      expect(
        rawSummaryRows,
        isEmpty,
        reason:
            'a stale reconcile must skip the snapshot write too, not '
            'just the mutation-row delete',
      );
    });
  });

  group('DriftSongMutationStore missing-record handling (D4, in-flight '
      'create cancellation)', () {
    // docs/specs/2026-08-06-in-flight-create-cancellation.md D4: the song
    // side's equivalent of planning's saveSyncAttemptResult -- the write
    // SongMutationSyncController concludes a remote sync attempt with --
    // must report "did not apply" instead of throwing when the song's row
    // no longer exists (mutation row AND synced snapshot both gone): the
    // ordinary outcome of the user deleting a still-pending create while
    // its remote call was in flight (SongLibraryService.deleteSong's
    // pendingCreate branch).
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;
    late DriftSongMutationStore mutationStore;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
      mutationStore = DriftSongMutationStore(
        songCatalogStore: store,
        planningLocalStore: const _NoopPlanningLocalStore(),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('saveSyncAttemptResult against a nonexistent song returns false '
        'instead of throwing', () async {
      final result = await mutationStore.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'ghost-song',
        syncStatus: SongSyncStatus.pendingCreate,
        errorCode: SongMutationSyncErrorCode.authorizationDenied,
      );
      expect(result, isFalse);
    });

    test('saveSyncAttemptResult against an EXISTING song is unchanged -- it '
        'still applies and reports success', () async {
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

      final result = await mutationStore.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
        syncStatus: SongSyncStatus.pendingCreate,
        errorCode: SongMutationSyncErrorCode.dependencyBlocked,
        errorMessage: 'blocked',
      );
      expect(result, isTrue);

      final record = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(record!.syncErrorContext, contains('dependencyBlocked'));
    });
  });
}

class _NoopPlanningLocalStore implements PlanningLocalStore {
  const _NoopPlanningLocalStore();

  @override
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async => false;

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async => null;

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) async => null;

  @override
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async => null;

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async => null;

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) async {}

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) async {}

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {}
}
