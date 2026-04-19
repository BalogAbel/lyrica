import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:path/path.dart' as p;

import '../../support/drift_test_setup.dart';

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
