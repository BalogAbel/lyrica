import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

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

    test(
      'reports eviction after deletion and not for the later true no-op',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'song-catalog-eviction-footprint-revision-test',
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
        await trackedDatabase
            .into(trackedDatabase.cachedCatalogSources)
            .insert(
              CachedCatalogSourcesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: 'song-clean',
                source: 'body ' * 200,
              ),
            );
        final observer = sqlite3.open(dbFile.path);
        addTearDown(observer.close);
        var revisionCount = 0;
        final committedRowCounts = <int>[];
        final trackedEvictor = SongCatalogEvictor(
          database: trackedDatabase,
          accountant: CatalogStorageAccountant(trackedDatabase),
          onStorageFootprintChanged: () {
            revisionCount += 1;
            final row = observer
                .select(
                  'SELECT count(*) AS row_count FROM cached_catalog_sources',
                )
                .single;
            committedRowCounts.add(row['row_count'] as int);
          },
        );

        await trackedEvictor.evictDroppable();

        expect(revisionCount, 1);
        expect(committedRowCounts, [0]);

        expect(await trackedEvictor.evictDroppable(), 0);
        expect(revisionCount, 1);
      },
    );

    test('does not report eviction when measurement throws', () async {
      var revisionCount = 0;
      final trackedEvictor = SongCatalogEvictor(
        database: database,
        accountant: _ThrowingCatalogStorageAccountant(database),
        onStorageFootprintChanged: () => revisionCount += 1,
      );

      await expectLater(trackedEvictor.evictDroppable, throwsA(anything));
      expect(revisionCount, 0);
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

  group('CatalogStorageAccountant.measureDroppableBytesFor', () {
    late SongCatalogDatabase database;
    late CatalogStorageAccountant accountant;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      accountant = CatalogStorageAccountant(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('measures only the given (userId, organizationId) pair\'s droppable '
        'bytes, excluding other pairs and protected sources', () async {
      await database
          .into(database.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'song-droppable',
              source: 'body ' * 200,
            ),
          );
      // Protected: has a pending mutation, must not count.
      await database
          .into(database.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'song-protected',
              source: 'body ' * 200,
            ),
          );
      await database
          .into(database.cachedCatalogSongMutations)
          .insert(
            CachedCatalogSongMutationsCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-protected',
              slug: 'song-protected',
              title: 'song-protected',
              source: 'edited body',
              version: 2,
              syncStatus: 'pending',
            ),
          );
      // A different pair -- must not count towards user-1/org-1's total.
      await database
          .into(database.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-2',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'song-elsewhere',
              source: 'body ' * 500,
            ),
          );

      final scoped = await accountant.measureDroppableBytesFor(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      final wholeDevice = await accountant.measureDroppableBytes();

      expect(scoped, greaterThan(0));
      expect(
        scoped,
        lessThan(wholeDevice),
        reason:
            'the device-wide total also includes the other pair\'s '
            'droppable bytes',
      );
    });

    test('returns 0 for a pair with no droppable sources', () async {
      final scoped = await accountant.measureDroppableBytesFor(
        userId: 'user-nonexistent',
        organizationId: 'org-nonexistent',
      );
      expect(scoped, 0);
    });
  });

  group('SongCatalogEvictor.evictToBudget (D6, ADR-035 Task 3.4)', () {
    late SongCatalogDatabase database;
    late CatalogStorageAccountant accountant;
    late SongCatalogEvictor evictor;

    setUp(() {
      database = SongCatalogDatabase.inMemory();
      accountant = CatalogStorageAccountant(database);
      evictor = SongCatalogEvictor(database: database, accountant: accountant);
    });

    tearDown(() async {
      await database.close();
    });

    Future<void> seedPair({
      required String userId,
      required String organizationId,
      required DateTime refreshedAt,
      required String songId,
      bool withPendingMutation = false,
    }) async {
      await database
          .into(database.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: 1,
              refreshedAt: refreshedAt,
            ),
          );
      await database
          .into(database.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: 1,
              songId: songId,
              source: 'body ' * 200,
            ),
          );
      if (withPendingMutation) {
        await database
            .into(database.cachedCatalogSongMutations)
            .insert(
              CachedCatalogSongMutationsCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                songId: songId,
                slug: songId,
                title: songId,
                source: 'edited body',
                version: 2,
                syncStatus: 'pending',
              ),
            );
      }
    }

    Future<DateTime?> sourcesEvictedAtFor({
      required String userId,
      required String organizationId,
    }) async {
      final row =
          await (database.select(database.cachedCatalogSnapshots)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .getSingle();
      return row.sourcesEvictedAt;
    }

    Future<bool> hasSourceRow({
      required String userId,
      required String organizationId,
      required String songId,
    }) async {
      final row =
          await (database.select(database.cachedCatalogSources)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.songId.equals(songId),
              ))
              .getSingleOrNull();
      return row != null;
    }

    test('stops once the size target is met: evicts oldest non-active pairs '
        'first, leaves a not-needed non-active pair and the active pair '
        'untouched', () async {
      // Three non-active pairs, oldest to newest, plus the active pair
      // (which must be touched last, if at all).
      await seedPair(
        userId: 'user-oldest',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 1, 1),
        songId: 'song-oldest',
      );
      await seedPair(
        userId: 'user-middle',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 3, 1),
        songId: 'song-middle',
      );
      await seedPair(
        userId: 'user-newest-nonactive',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 6, 1),
        songId: 'song-newest-nonactive',
      );
      await seedPair(
        userId: 'user-active',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2020, 1, 1), // deliberately the OLDEST
        // refreshedAt of all, to prove active-last overrides recency.
        songId: 'song-active',
      );

      final perPairBytes = await accountant.measureDroppableBytesFor(
        userId: 'user-oldest',
        organizationId: 'org-1',
      );
      // Just over one pair's worth: the oldest alone must not be enough,
      // forcing a second pair to be evicted too, but never a third.
      final target = perPairBytes + 1;

      final freed = await evictor.evictToBudget(
        targetBytes: target,
        activeUserId: 'user-active',
        activeOrganizationId: 'org-1',
      );

      expect(freed, greaterThanOrEqualTo(target));

      // The two oldest non-active pairs were evicted...
      expect(
        await hasSourceRow(
          userId: 'user-oldest',
          organizationId: 'org-1',
          songId: 'song-oldest',
        ),
        isFalse,
      );
      expect(
        await hasSourceRow(
          userId: 'user-middle',
          organizationId: 'org-1',
          songId: 'song-middle',
        ),
        isFalse,
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-oldest',
          organizationId: 'org-1',
        ),
        isNotNull,
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-middle',
          organizationId: 'org-1',
        ),
        isNotNull,
      );

      // ...but the third, not-needed non-active pair is left untouched...
      expect(
        await hasSourceRow(
          userId: 'user-newest-nonactive',
          organizationId: 'org-1',
          songId: 'song-newest-nonactive',
        ),
        isTrue,
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-newest-nonactive',
          organizationId: 'org-1',
        ),
        isNull,
      );

      // ...and the active pair is untouched even though it has droppable
      // content too and is (deliberately) the oldest by refreshedAt.
      expect(
        await hasSourceRow(
          userId: 'user-active',
          organizationId: 'org-1',
          songId: 'song-active',
        ),
        isTrue,
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-active',
          organizationId: 'org-1',
        ),
        isNull,
      );
    });

    test('evicts the active pair too when every other pair\'s droppable '
        'content together is not enough to meet the target', () async {
      await seedPair(
        userId: 'user-other',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 1, 1),
        songId: 'song-other',
      );
      await seedPair(
        userId: 'user-active',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 6, 1),
        songId: 'song-active',
      );

      final otherBytes = await accountant.measureDroppableBytesFor(
        userId: 'user-other',
        organizationId: 'org-1',
      );
      final activeBytes = await accountant.measureDroppableBytesFor(
        userId: 'user-active',
        organizationId: 'org-1',
      );
      // More than the single non-active pair can supply alone.
      final target = otherBytes + activeBytes;

      final freed = await evictor.evictToBudget(
        targetBytes: target,
        activeUserId: 'user-active',
        activeOrganizationId: 'org-1',
      );

      expect(freed, otherBytes + activeBytes);
      expect(
        await hasSourceRow(
          userId: 'user-other',
          organizationId: 'org-1',
          songId: 'song-other',
        ),
        isFalse,
      );
      expect(
        await hasSourceRow(
          userId: 'user-active',
          organizationId: 'org-1',
          songId: 'song-active',
        ),
        isFalse,
        reason:
            'D6: touch the active context last, not never -- freeing '
            'every other pair still was not enough',
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-active',
          organizationId: 'org-1',
        ),
        isNotNull,
      );
    });

    test('skips a pair with zero droppable bytes (fully protected by a '
        'pending mutation) without marking sourcesEvictedAt', () async {
      await seedPair(
        userId: 'user-protected',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 1, 1),
        songId: 'song-protected',
        withPendingMutation: true,
      );
      await seedPair(
        userId: 'user-active',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 6, 1),
        songId: 'song-active',
      );

      final freed = await evictor.evictToBudget(
        targetBytes: 1,
        activeUserId: 'user-active',
        activeOrganizationId: 'org-1',
      );

      // The only non-active pair is fully protected (0 droppable bytes),
      // so the target can only be met by falling through to the active
      // pair.
      expect(freed, greaterThan(0));
      expect(
        await hasSourceRow(
          userId: 'user-protected',
          organizationId: 'org-1',
          songId: 'song-protected',
        ),
        isTrue,
        reason: 'a pending mutation must never be evicted',
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-protected',
          organizationId: 'org-1',
        ),
        isNull,
        reason: 'nothing was actually evicted for this pair',
      );
      expect(
        await sourcesEvictedAtFor(
          userId: 'user-active',
          organizationId: 'org-1',
        ),
        isNotNull,
      );
    });

    test(
      'is a no-op returning 0 when every pair is already under target',
      () async {
        await seedPair(
          userId: 'user-active',
          organizationId: 'org-1',
          refreshedAt: DateTime.utc(2026, 6, 1),
          songId: 'song-active',
        );

        final freed = await evictor.evictToBudget(
          targetBytes: 0,
          activeUserId: 'user-active',
          activeOrganizationId: 'org-1',
        );

        expect(freed, 0);
        expect(
          await hasSourceRow(
            userId: 'user-active',
            organizationId: 'org-1',
            songId: 'song-active',
          ),
          isTrue,
        );
      },
    );
  });
}

class _ThrowingCatalogStorageAccountant extends CatalogStorageAccountant {
  const _ThrowingCatalogStorageAccountant(super.database);

  @override
  Future<int> measureDroppableBytes() {
    throw StateError('simulated measurement failure');
  }
}
