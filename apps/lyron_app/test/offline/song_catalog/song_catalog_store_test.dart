import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
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

    test(
      'keeps each organization cached snapshot independent for one user',
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
          organizationId: 'org-2',
          summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
          sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
          refreshedAt: DateTime.utc(2026, 3, 25, 13),
        );

        // F3 (docs/specs/2026-08-19-local-data-durability-contract.md):
        // caching a second organization for the same user must not evict the
        // first organization's own snapshot -- each (userId, organizationId)
        // pair is independently cached.
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          const [SongSummary(id: 'song-1', title: 'Alpha')],
        );
        expect(
          await store.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-2',
          ),
          const [SongSummary(id: 'song-2', title: 'Beta')],
        );
      },
    );

    test('refreshing organization A leaves organization B cached snapshot rows '
        'byte-identical (F3, local-data-durability-contract)', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-a',
        summaries: const [SongSummary(id: 'song-a1', title: 'Org A One')],
        sources: const [
          SongSource(id: 'song-a1', source: '{title: Org A One}'),
        ],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-b',
        summaries: const [SongSummary(id: 'song-b1', title: 'Org B One')],
        sources: const [
          SongSource(id: 'song-b1', source: '{title: Org B One}'),
        ],
        refreshedAt: DateTime.utc(2026, 3, 25, 13),
      );

      final orgBSummariesBefore =
          await (database.select(database.cachedCatalogSummaries)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-b'),
              ))
              .get();
      final orgBSourcesBefore =
          await (database.select(database.cachedCatalogSources)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-b'),
              ))
              .get();
      final orgBSnapshotBefore =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-b'),
              ))
              .getSingle();

      // A third replace, refreshing organization A only -- this is the
      // write that used to wipe organization B's entire cached snapshot
      // as a side effect, because the old deletion only filtered by
      // userId.
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-a',
        summaries: const [SongSummary(id: 'song-a2', title: 'Org A Two')],
        sources: const [
          SongSource(id: 'song-a2', source: '{title: Org A Two}'),
        ],
        refreshedAt: DateTime.utc(2026, 3, 25, 14),
      );

      final orgBSummariesAfter =
          await (database.select(database.cachedCatalogSummaries)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-b'),
              ))
              .get();
      final orgBSourcesAfter =
          await (database.select(database.cachedCatalogSources)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-b'),
              ))
              .get();
      final orgBSnapshotAfter =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-b'),
              ))
              .getSingle();

      expect(orgBSummariesAfter, orgBSummariesBefore);
      expect(orgBSourcesAfter, orgBSourcesBefore);
      expect(orgBSnapshotAfter, orgBSnapshotBefore);

      // And organization A itself did get refreshed, so this was a real
      // replace, not a no-op.
      expect(
        await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-a',
        ),
        const [SongSummary(id: 'song-a2', title: 'Org A Two')],
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
    //
    // The seeded droppable source deliberately belongs to a DIFFERENT
    // (userId, organizationId) pair ('user-other'/'org-other') than the one
    // every guarded write below targets ('user-1'/'org-1'): since ADR-028's
    // 2026-08-22 amendment, the active (userId, organizationId) a guarded
    // catalog write is FOR is excluded entirely from the reactive eviction
    // that runs on its own failure, so seeding the droppable content under
    // that same active pair would mean nothing is ever evicted here. A
    // matching cached_catalog_snapshots row is also required for the seeded
    // pair -- without one it is an "orphan" excluded from eviction entirely,
    // for the unrelated reason that there is nowhere to record
    // sourcesEvictedAt against it.
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
          .into(evictionDatabase.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-other',
              organizationId: 'org-other',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-other',
              organizationId: 'org-other',
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

    test('the active context is excluded from reactive eviction: when it is '
        'the ONLY droppable content on the device, nothing is evicted, the '
        'active pair\'s sources survive fully intact, and the write surfaces '
        'a typed LocalStorageWriteFailure after one retry (ADR-028 2026-08-22 '
        'amendment -- the core regression this closes)', () async {
      final failingExecutor = InsertFailingExecutor(
        NativeDatabase.memory(),
        null, // no budget: every INSERT fails, so the retry fails too.
      );
      final failingDatabase = SongCatalogDatabase.connect(failingExecutor);
      addTearDown(failingDatabase.close);
      final evictionDatabase = SongCatalogDatabase.inMemory();
      addTearDown(evictionDatabase.close);

      // The ONLY droppable content on the device belongs to the exact
      // (userId, organizationId) the guarded write below is for.
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'active-song',
              source: 'body ' * 200,
            ),
          );

      var insertAttempts = 0;
      final countingExecutor = _CountingInsertExecutor(
        failingExecutor,
        onInsertAttempted: () => insertAttempts += 1,
      );
      final countingDatabase = SongCatalogDatabase.connect(countingExecutor);
      addTearDown(countingDatabase.close);
      final recovery = LocalStorageWriteRecovery(
        evictor: SongCatalogEvictor(
          database: evictionDatabase,
          accountant: CatalogStorageAccountant(evictionDatabase),
        ),
      );
      final store = DriftSongCatalogStore(
        countingDatabase,
        writeRecovery: recovery,
      );

      await expectLater(
        () => store.saveSongMutation(
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

      // The initial attempt plus exactly one retry, per guard's
      // documented "evict once, retry once" contract -- eviction excluded
      // everything, so the retry fails identically to the first attempt.
      expect(insertAttempts, 2);

      // The active pair's cached source is STILL FULLY PRESENT.
      final remainingSources = await evictionDatabase
          .select(evictionDatabase.cachedCatalogSources)
          .get();
      expect(remainingSources, hasLength(1));
      expect(remainingSources.single.songId, 'active-song');
      expect(remainingSources.single.userId, 'user-1');
      expect(remainingSources.single.organizationId, 'org-1');

      final snapshotRow =
          await (evictionDatabase.select(
                evictionDatabase.cachedCatalogSnapshots,
              )..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-1'),
              ))
              .getSingle();
      expect(
        snapshotRow.sourcesEvictedAt,
        isNull,
        reason: 'nothing was evicted for the active pair',
      );
    });

    test('the active context is excluded from reactive eviction while every '
        'OTHER (userId, organizationId) pair\'s droppable content is still '
        'evicted in full, letting the retry succeed', () async {
      final failingExecutor = InsertFailingExecutor(
        NativeDatabase.memory(),
        InsertFailureBudget(failuresRemaining: 1),
      );
      final failingDatabase = SongCatalogDatabase.connect(failingExecutor);
      addTearDown(failingDatabase.close);
      final evictionDatabase = SongCatalogDatabase.inMemory();
      addTearDown(evictionDatabase.close);

      // The active pair's own droppable content.
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'active-song',
              source: 'body ' * 200,
            ),
          );
      // A different, older, non-active pair's droppable content.
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-other',
              organizationId: 'org-other',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 1, 1),
            ),
          );
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-other',
              organizationId: 'org-other',
              snapshotVersion: 1,
              songId: 'other-song',
              source: 'body ' * 200,
            ),
          );

      final recorder = _RecordingLocalDataEventsRecorderForEviction();
      final recovery = LocalStorageWriteRecovery(
        evictor: SongCatalogEvictor(
          database: evictionDatabase,
          accountant: CatalogStorageAccountant(evictionDatabase),
          eventsRecorder: recorder,
        ),
      );
      final store = DriftSongCatalogStore(
        failingDatabase,
        writeRecovery: recovery,
      );

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

      // The retry succeeded this time -- the mutation landed.
      final mutation = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(mutation, isNotNull);

      // The non-active pair was evicted and marked.
      final otherSources = await (evictionDatabase.select(
        evictionDatabase.cachedCatalogSources,
      )..where((table) => table.userId.equals('user-other'))).get();
      expect(otherSources, isEmpty);
      final otherSnapshot = await (evictionDatabase.select(
        evictionDatabase.cachedCatalogSnapshots,
      )..where((table) => table.userId.equals('user-other'))).getSingle();
      expect(otherSnapshot.sourcesEvictedAt, isNotNull);

      // The active pair's own droppable content is untouched.
      final activeSources = await (evictionDatabase.select(
        evictionDatabase.cachedCatalogSources,
      )..where((table) => table.userId.equals('user-1'))).get();
      expect(activeSources, hasLength(1));
      final activeSnapshot = await (evictionDatabase.select(
        evictionDatabase.cachedCatalogSnapshots,
      )..where((table) => table.userId.equals('user-1'))).getSingle();
      expect(activeSnapshot.sourcesEvictedAt, isNull);

      await pumpEventQueue();
      expect(recorder.evictionCalls.map((call) => call.userId), ['user-other']);
    });
  });

  group(
    'DriftSongCatalogStore proactive budget eviction (D6, ADR-035 Task 3.4)',
    () {
      late SongCatalogDatabase database;

      setUp(() {
        database = SongCatalogDatabase.inMemory();
      });

      tearDown(() async {
        await database.close();
      });

      Future<void> replaceEmptySnapshot(
        DriftSongCatalogStore store, {
        String userId = 'user-1',
        String organizationId = 'org-1',
      }) {
        return store.replaceActiveSnapshot(
          userId: userId,
          organizationId: organizationId,
          summaries: const [],
          sources: const [],
          refreshedAt: DateTime.utc(2026, 8, 22),
        );
      }

      test('calls evictToBudget with (totalBytes - budget) and the active '
          '(userId, organizationId) when the measured footprint exceeds the '
          'budget, after the write has succeeded', () async {
        final accountant = _FakeBudgetAccountant(totalBytes: 3000000000);
        final evictor = _FakeBudgetEvictor();
        final store = DriftSongCatalogStore(
          database,
          evictor: evictor,
          accountant: accountant,
        );

        await replaceEmptySnapshot(store);

        expect(evictor.calls, hasLength(1));
        final call = evictor.calls.single;
        expect(call.activeUserId, 'user-1');
        expect(call.activeOrganizationId, 'org-1');
        expect(call.targetBytes, 3000000000 - kCatalogStorageBudgetBytes);
      });

      test('never calls evictToBudget when the measured footprint is at or '
          'under the budget', () async {
        final accountant = _FakeBudgetAccountant(
          totalBytes: kCatalogStorageBudgetBytes,
        );
        final evictor = _FakeBudgetEvictor();
        final store = DriftSongCatalogStore(
          database,
          evictor: evictor,
          accountant: accountant,
        );

        await replaceEmptySnapshot(store);

        expect(evictor.calls, isEmpty);
      });

      test(
        'never calls the evictor when no evictor/accountant is supplied '
        '(existing test fixtures keep compiling and behaving unchanged)',
        () async {
          final store = DriftSongCatalogStore(database);

          await replaceEmptySnapshot(store);
          // No assertion beyond "did not throw" -- proves the optional
          // fields default to inert when absent.
        },
      );

      test('a measurement failure is best-effort: the write still proceeds '
          'and the failure never surfaces', () async {
        final accountant = _FakeBudgetAccountant(throwsOnMeasure: true);
        final evictor = _FakeBudgetEvictor();
        final store = DriftSongCatalogStore(
          database,
          evictor: evictor,
          accountant: accountant,
        );

        await replaceEmptySnapshot(store);

        expect(evictor.calls, isEmpty);
      });

      test('an evictToBudget failure is best-effort: the write still proceeds '
          'and the failure never surfaces', () async {
        final accountant = _FakeBudgetAccountant(totalBytes: 3000000000);
        final evictor = _FakeBudgetEvictor(throwsOnEvict: true);
        final store = DriftSongCatalogStore(
          database,
          evictor: evictor,
          accountant: accountant,
        );

        // Must not throw despite the evictor blowing up.
        await replaceEmptySnapshot(store);

        final summaries = await store.readActiveSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(summaries, isEmpty);
      });

      test('a replaceActiveSnapshot write that ultimately fails never runs the '
          'proactive budget eviction, even when over budget (finding 2: '
          "don't evict another organization's data for a write that was "
          'going to fail regardless)', () async {
        final failingExecutor = InsertFailingExecutor(
          NativeDatabase.memory(),
          null, // no budget: every INSERT fails, unconditionally.
        );
        final failingDatabase = SongCatalogDatabase.connect(failingExecutor);
        addTearDown(failingDatabase.close);

        final accountant = _FakeBudgetAccountant(totalBytes: 3000000000);
        final evictor = _FakeBudgetEvictor();
        final store = DriftSongCatalogStore(
          failingDatabase,
          evictor: evictor,
          accountant: accountant,
        );

        await expectLater(
          () => store.replaceActiveSnapshot(
            userId: 'user-1',
            organizationId: 'org-1',
            summaries: const [SongSummary(id: 'song-1', title: 'Song One')],
            sources: const [SongSource(id: 'song-1', source: 'chordpro body')],
            refreshedAt: DateTime.utc(2026, 8, 22),
          ),
          throwsA(anything),
        );

        expect(
          evictor.calls,
          isEmpty,
          reason:
              'the write failed, so the proactive eviction must never '
              'have run -- it would have destroyed another '
              "organization's droppable sources for zero benefit, since "
              'the write it was supposedly making room for never landed',
        );
      });
    },
  );

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

    test('a conditional saveSyncAttemptResult that matches applies and returns '
        'the new revision; a stale one does not apply and leaves the row '
        'untouched -- Finding B, 2026-08-06 remediation round', () async {
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
      final mutationStore = DriftSongMutationStore(
        songCatalogStore: store,
        planningLocalStore: const _NoopPlanningLocalStore(),
      );

      // Matching expectedRevision: applies.
      final applied = await mutationStore.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.conflict,
        errorMessage: 'version mismatch',
        expectedRevision: 1,
      );
      expect(applied, isTrue);
      final afterApplied = await store.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(afterApplied!.syncStatus, SongSyncStatus.conflict.value);
      expect(afterApplied.localRevision, 2);

      // A second song, edited once more after the revision a sync attempt
      // would have captured: a status write keyed to the STALE revision
      // must not apply.
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

      final stale = await mutationStore.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-2',
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.conflict,
        errorMessage: 'version mismatch',
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
        record.syncStatus,
        SongSyncStatus.pendingCreate.value,
        reason: 'the stale attempt must not have overwritten the status',
      );
      expect(
        record.source,
        '{title: Beta edited}',
        reason: 'the stale attempt must not have overwritten the content',
      );
      expect(
        record.syncErrorContext,
        isNull,
        reason: 'the stale attempt must not have written an error either',
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

  group('SongCatalogStore.resolveEmptySnapshot (D4, '
      'local-data-durability-contract)', () {
    late SongCatalogDatabase database;
    late DriftSongCatalogStore store;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      store = DriftSongCatalogStore(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('accepts when there is no stored snapshot row at all', () async {
      final resolution = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(resolution, EmptySnapshotResolution.accept);
    });

    test(
      'accepts when the stored snapshot exists but is already empty',
      () async {
        await store.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: const [],
          sources: const [],
          refreshedAt: DateTime.utc(2026, 3, 25, 12),
        );

        final resolution = await store.resolveEmptySnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        expect(resolution, EmptySnapshotResolution.accept);
      },
    );

    test('rejects the first empty resolution against a non-empty stored '
        'snapshot and sets the pending-confirmation marker', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      final resolution = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      expect(resolution, EmptySnapshotResolution.reject);

      final snapshotRow =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-1'),
              ))
              .getSingle();
      expect(snapshotRow.pendingEmptyConfirmationAt, isNotNull);
    });

    test('a rejection leaves the cached summaries, sources, and snapshot '
        'version/refreshedAt fully unchanged', () async {
      final refreshedAt = DateTime.utc(2026, 3, 25, 12);
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: refreshedAt,
      );

      final summariesBefore = await database
          .select(database.cachedCatalogSummaries)
          .get();
      final sourcesBefore = await database
          .select(database.cachedCatalogSources)
          .get();
      final snapshotBefore =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-1'),
              ))
              .getSingle();

      final resolution = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(resolution, EmptySnapshotResolution.reject);

      final summariesAfter = await database
          .select(database.cachedCatalogSummaries)
          .get();
      final sourcesAfter = await database
          .select(database.cachedCatalogSources)
          .get();
      final snapshotAfter =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-1'),
              ))
              .getSingle();

      expect(summariesAfter, summariesBefore);
      expect(sourcesAfter, sourcesBefore);
      expect(snapshotAfter.snapshotVersion, snapshotBefore.snapshotVersion);
      expect(snapshotAfter.refreshedAt, snapshotBefore.refreshedAt);
      expect(
        snapshotBefore.pendingEmptyConfirmationAt,
        isNull,
        reason: 'sanity: the marker must not already be set before this',
      );
      expect(snapshotAfter.pendingEmptyConfirmationAt, isNotNull);
    });

    test('accepts the second, independent empty resolution once the marker is '
        'set', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      final first = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(first, EmptySnapshotResolution.reject);

      final second = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(second, EmptySnapshotResolution.accept);
    });

    test('an intervening normal non-empty replace clears the pending-empty '
        'marker, so a later single empty response is rejected again rather '
        'than wrongly treated as the second confirmation', () async {
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Alpha')],
        sources: const [SongSource(id: 'song-1', source: '{title: Alpha}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 12),
      );

      final firstResolution = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(firstResolution, EmptySnapshotResolution.reject);

      // A normal, real, non-empty refresh lands in between -- this must
      // clear the marker the rejection above set.
      await store.replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
        sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
        refreshedAt: DateTime.utc(2026, 3, 25, 13),
      );

      final snapshotRow =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals('user-1') &
                    table.organizationId.equals('org-1'),
              ))
              .getSingle();
      expect(
        snapshotRow.pendingEmptyConfirmationAt,
        isNull,
        reason:
            'insertOnConflictUpdate only updates columns present in the '
            'companion -- omitting pendingEmptyConfirmationAt here would '
            'silently leave the earlier marker in place forever',
      );

      final thirdResolution = await store.resolveEmptySnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(
        thirdResolution,
        EmptySnapshotResolution.reject,
        reason:
            'this is a fresh, independent single empty response against '
            'the Beta snapshot -- the earlier rejection must not leak '
            'across the intervening real refresh',
      );
    });
  });

  group('DriftSongCatalogStore blue/green replace atomicity (D4, ADR-035 Task '
      '3.3)', () {
    // ADR-035 Task 3.3: _replaceActiveSnapshot's delete-then-insert
    // sequence is claimed to already be blue/green-equivalent on native
    // SQLite because it all runs inside one `_database.transaction()`
    // block -- this test proves that claim rather than assuming Drift
    // provides it. Three separate connections to the SAME on-disk
    // database file, opened and closed in sequence (mirroring "can reopen
    // a persisted catalog from a new database instance" above): the first
    // seeds a real, non-empty snapshot and is closed; the second wraps its
    // executor in InsertFailingExecutor (unlimited budget -- every INSERT
    // fails) and attempts a second, different non-empty replace, which
    // must fail partway through its transaction, after the old
    // summaries/sources/snapshot row have already been deleted but before
    // any row of the new snapshot is inserted; the third is a fresh,
    // unwrapped connection used only to read back the data, so the
    // failing executor never gets a chance to interfere with the
    // assertion queries.
    test(
      'a write that fails after the old snapshot is deleted but before '
      'the new snapshot commits leaves the previous snapshot fully intact',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'song-catalog-blue-green-atomicity-test',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final dbFile = File(p.join(tempDir.path, 'catalog.sqlite'));

        const seededSummaries = [SongSummary(id: 'song-1', title: 'Alpha')];
        const seededSources = [
          SongSource(id: 'song-1', source: '{title: Alpha}'),
        ];
        final seededRefreshedAt = DateTime.utc(2026, 3, 25, 12);

        final firstDatabase = SongCatalogDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        final firstStore = DriftSongCatalogStore(firstDatabase);
        await firstStore.replaceActiveSnapshot(
          userId: 'user-1',
          organizationId: 'org-1',
          summaries: seededSummaries,
          sources: seededSources,
          refreshedAt: seededRefreshedAt,
        );
        // Read the seeded snapshot row back through the same connection
        // that wrote it, rather than comparing against the literal
        // `DateTime.utc(...)` passed in above: Drift's native codec
        // round-trips `refreshedAt` as a local-time `DateTime` (same
        // instant, `isUtc: false`), and Dart's `DateTime.==` treats a UTC
        // and a local `DateTime` representing the identical instant as
        // unequal. Comparing two DB reads to each other sidesteps that
        // entirely and gives a true byte-identical check on every column.
        final seededSnapshotRow =
            await (firstDatabase.select(firstDatabase.cachedCatalogSnapshots)
                  ..where(
                    (table) =>
                        table.userId.equals('user-1') &
                        table.organizationId.equals('org-1'),
                  ))
                .getSingle();
        await firstDatabase.close();

        // Deliberately no LocalStorageWriteRecovery here: this test
        // targets the raw transaction's atomicity, not the eviction/retry
        // behaviour already covered by the "storage recovery" group above
        // -- a bare failing executor makes the single doomed attempt and
        // its outcome unambiguous. With no writeRecovery, `_guarded` calls
        // the write directly (see `_guarded` in song_catalog_store.dart),
        // so the raw executor exception propagates as-is.
        final secondDatabase = SongCatalogDatabase.connect(
          InsertFailingExecutor(NativeDatabase.createInBackground(dbFile)),
        );
        final secondStore = DriftSongCatalogStore(secondDatabase);

        await expectLater(
          () => secondStore.replaceActiveSnapshot(
            userId: 'user-1',
            organizationId: 'org-1',
            summaries: const [SongSummary(id: 'song-2', title: 'Beta')],
            sources: const [SongSource(id: 'song-2', source: '{title: Beta}')],
            refreshedAt: DateTime.utc(2026, 3, 25, 13),
          ),
          throwsA(isA<StorageQuotaSimulatedException>()),
        );
        await secondDatabase.close();

        final thirdDatabase = SongCatalogDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        addTearDown(thirdDatabase.close);
        final thirdStore = DriftSongCatalogStore(thirdDatabase);

        expect(
          await thirdStore.readActiveSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          seededSummaries,
          reason:
              'the interrupted second replace must not leave the '
              'summaries table empty or holding the Beta content',
        );
        final reopenedSource = await thirdStore.readActiveSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(reopenedSource?.id, seededSources.single.id);
        expect(reopenedSource?.source, seededSources.single.source);
        final failedSource = await thirdStore.readActiveSource(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-2',
        );
        expect(
          failedSource,
          isNull,
          reason: 'the Beta source must never have become visible',
        );

        final snapshotRow =
            await (thirdDatabase.select(thirdDatabase.cachedCatalogSnapshots)
                  ..where(
                    (table) =>
                        table.userId.equals('user-1') &
                        table.organizationId.equals('org-1'),
                  ))
                .getSingle();
        expect(
          snapshotRow,
          seededSnapshotRow,
          reason:
              'the failed replace must leave the snapshot row fully '
              'byte-identical to what was seeded -- not bumped, not '
              'partially overwritten, and with the marker untouched -- '
              'proving the interrupted transaction rolled back rather '
              'than partially committing',
        );
        expect(snapshotRow.snapshotVersion, 1);
        expect(snapshotRow.pendingEmptyConfirmationAt, isNull);
      },
    );
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

/// Counts every attempted `INSERT` (successful or not) while delegating to
/// [_delegate], so the "active context excluded from reactive eviction"
/// regression test can confirm guard's documented "evict once, retry once"
/// contract without depending on any timing assumption.
class _CountingInsertExecutor implements QueryExecutor {
  _CountingInsertExecutor(this._delegate, {required this.onInsertAttempted});

  final QueryExecutor _delegate;
  final void Function() onInsertAttempted;

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _delegate.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _delegate.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    onInsertAttempted();
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _delegate.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _CountingInsertTransactionExecutor(
    _delegate.beginTransaction(),
    onInsertAttempted: onInsertAttempted,
  );

  @override
  QueryExecutor beginExclusive() => _CountingInsertExecutor(
    _delegate.beginExclusive(),
    onInsertAttempted: onInsertAttempted,
  );

  @override
  Future<void> close() => _delegate.close();
}

/// Transaction-scoped counterpart of [_CountingInsertExecutor]: Drift issues
/// the actual `INSERT` for a `database.transaction(...)` block through a
/// [TransactionExecutor], not the top-level [QueryExecutor], so the count
/// must be mirrored here too (matching how [InsertFailingTransactionExecutor]
/// mirrors [InsertFailingExecutor] for the same reason).
class _CountingInsertTransactionExecutor implements TransactionExecutor {
  _CountingInsertTransactionExecutor(
    this._delegate, {
    required this.onInsertAttempted,
  });

  final TransactionExecutor _delegate;
  final void Function() onInsertAttempted;

  @override
  bool get supportsNestedTransactions => _delegate.supportsNestedTransactions;

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _delegate.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _delegate.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    onInsertAttempted();
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _delegate.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _CountingInsertTransactionExecutor(
    _delegate.beginTransaction(),
    onInsertAttempted: onInsertAttempted,
  );

  @override
  QueryExecutor beginExclusive() => _CountingInsertExecutor(
    _delegate.beginExclusive(),
    onInsertAttempted: onInsertAttempted,
  );

  @override
  Future<void> send() => _delegate.send();

  @override
  Future<void> rollback() => _delegate.rollback();

  @override
  Future<void> close() => _delegate.close();
}

/// Records every [recordEviction] call without touching a real database, so
/// the "active context excluded from reactive eviction" regression test can
/// assert exactly which pair's eviction was audited.
class _RecordingLocalDataEventsRecorderForEviction
    implements LocalDataEventsRecorder {
  final List<({String target, String? userId, int? rowsAffected})>
  evictionCalls = [];

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {
    evictionCalls.add((
      target: target,
      userId: userId,
      rowsAffected: rowsAffected,
    ));
  }

  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}

  @override
  Future<void> recordQuarantine({
    required PurgeTarget target,
    required String reason,
    String? userId,
  }) async {}
}

/// Records every [evictToBudget] call without touching a real database, so
/// the proactive-eviction wiring tests can assert on exactly what
/// [DriftSongCatalogStore] passed through.
class _FakeBudgetEvictor implements SongCatalogEvictor {
  _FakeBudgetEvictor({this.throwsOnEvict = false});

  final bool throwsOnEvict;
  final List<
    ({int targetBytes, String activeUserId, String activeOrganizationId})
  >
  calls = [];

  @override
  Future<int> evictDroppable({
    String? protectedUserId,
    String? protectedOrganizationId,
  }) {
    throw UnimplementedError(
      'not exercised by the proactive-eviction wiring tests',
    );
  }

  @override
  Future<int> evictToBudget({
    required int targetBytes,
    required String activeUserId,
    required String activeOrganizationId,
  }) async {
    calls.add((
      targetBytes: targetBytes,
      activeUserId: activeUserId,
      activeOrganizationId: activeOrganizationId,
    ));
    if (throwsOnEvict) {
      throw Exception('simulated evictToBudget failure');
    }
    return 0;
  }
}

/// Reports a fixed (or throwing) total catalog footprint without touching a
/// real database, so the proactive-eviction wiring tests can control
/// whether the budget is exceeded.
class _FakeBudgetAccountant implements CatalogStorageAccountant {
  _FakeBudgetAccountant({this.totalBytes = 0, this.throwsOnMeasure = false});

  final int totalBytes;
  final bool throwsOnMeasure;

  @override
  Future<int> measureCatalogBytes() async {
    if (throwsOnMeasure) {
      throw Exception('simulated measurement failure');
    }
    return totalBytes;
  }

  @override
  Future<int> measureDroppableBytes() {
    throw UnimplementedError(
      'not exercised by the proactive-eviction wiring tests',
    );
  }

  @override
  Future<int> measureDroppableBytesFor({
    required String userId,
    required String organizationId,
  }) {
    throw UnimplementedError(
      'not exercised by the proactive-eviction wiring tests',
    );
  }
}
