import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../support/drift_test_setup.dart';
import '../../support/insert_failing_executor.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('PlanningLocalStore', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore store;

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      store = DriftPlanningLocalStore(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('reports projection storage only after the concrete commit', () async {
      final directory = await Directory.systemTemp.createTemp(
        'planning-projection-footprint-revision-test',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final dbFile = File(p.join(directory.path, 'planning.sqlite'));
      final trackedDatabase = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      addTearDown(trackedDatabase.close);
      final observer = sqlite3.open(dbFile.path);
      addTearDown(observer.close);
      final committedRowCounts = <int>[];
      final trackedStore = DriftPlanningLocalStore(
        trackedDatabase,
        onStorageFootprintChanged: () {
          final row = observer
              .select('SELECT count(*) AS row_count FROM cached_planning_plans')
              .single;
          committedRowCounts.add(row['row_count'] as int);
        },
      );

      await trackedStore.upsertSyncedPlan(
        userId: 'user-1',
        organizationId: 'org-1',
        plan: _planRecord(id: 'plan-1', name: 'Plan'),
        refreshedAt: DateTime.utc(2026, 4, 3, 12),
      );

      expect(committedRowCounts, [1]);
    });

    test('does not report a projection throw or true no-op', () async {
      var revisionCount = 0;
      final trackedStore = DriftPlanningLocalStore(
        database,
        onStorageFootprintChanged: () => revisionCount += 1,
      );

      await trackedStore.deletePlanningData(
        userId: 'missing-user',
        organizationId: 'missing-organization',
      );
      expect(revisionCount, 0);

      await expectLater(
        () => trackedStore.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Plan')],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
          shouldContinue: () => false,
        ),
        throwsA(isA<PlanningProjectionAbortedException>()),
      );
      expect(revisionCount, 0);
    });

    test('does not report an identical synced-plan upsert', () async {
      var revisionCount = 0;
      final trackedStore = DriftPlanningLocalStore(
        database,
        onStorageFootprintChanged: () => revisionCount += 1,
      );
      final plan = _planRecord(id: 'plan-1', name: 'Plan');
      final refreshedAt = DateTime.utc(2026, 4, 3, 12);

      await trackedStore.upsertSyncedPlan(
        userId: 'user-1',
        organizationId: 'org-1',
        plan: plan,
        refreshedAt: refreshedAt,
      );
      expect(revisionCount, 1);

      await trackedStore.upsertSyncedPlan(
        userId: 'user-1',
        organizationId: 'org-1',
        plan: plan,
        refreshedAt: refreshedAt,
      );
      expect(revisionCount, 1);
    });

    test(
      'reports an earlier committed row when a later outer batch operation fails',
      () async {
        var revisionCount = 0;
        final trackedStore = DriftPlanningLocalStore(
          database,
          onStorageFootprintChanged: () => revisionCount += 1,
        );

        Future<void> applyOuterBatch() async {
          await trackedStore.upsertSyncedPlan(
            userId: 'user-1',
            organizationId: 'org-1',
            plan: _planRecord(id: 'plan-1', name: 'Committed plan'),
            refreshedAt: DateTime.utc(2026, 4, 3, 12),
          );
          await trackedStore.replaceActiveProjection(
            userId: 'user-1',
            organizationId: 'org-1',
            plans: [_planRecord(id: 'plan-2', name: 'Aborted projection')],
            sessions: const [],
            items: const [],
            refreshedAt: DateTime.utc(2026, 4, 3, 13),
            shouldContinue: () => false,
          );
        }

        await expectLater(
          applyOuterBatch,
          throwsA(isA<PlanningProjectionAbortedException>()),
        );
        expect(revisionCount, 1);
        expect(
          await trackedStore.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'replaces the active planning projection atomically for one user and organization',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [
            _planRecord(
              id: 'plan-1',
              name: 'Sunday AM',
              scheduledFor: DateTime.utc(2026, 4, 5, 8, 30),
            ),
          ],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Worship',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'A forrasnal',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        final summaries = await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        expect(summaries, hasLength(1));
        expect(summaries.single.id, 'plan-1');
        expect(summaries.single.name, 'Sunday AM');
        expect(summaries.single.description, 'Plan plan-1');
        expect(summaries.single.scheduledFor, DateTime.utc(2026, 4, 5, 8, 30));
        expect(summaries.single.updatedAt, DateTime.utc(2026, 4, 3, 9));

        final detail = await store.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
        );

        expect(detail, isNotNull);
        expect(detail!.sessions, hasLength(1));
        expect(detail.sessions.single.items.single.id, 'item-1');
        expect(detail.sessions.single.items.single.song.id, 'song-1');
      },
    );

    test(
      'hard replaces the previous active projection for the same context',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'First')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'First session',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'First song',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-2', name: 'Second')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-2',
              planId: 'plan-2',
              position: 10,
              name: 'Second session',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-2',
              planId: 'plan-2',
              sessionId: 'session-2',
              position: 10,
              songId: 'song-2',
              songTitle: 'Second song',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 13),
        );

        final summaries = await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(summaries, hasLength(1));
        expect(summaries.single.id, 'plan-2');
        expect(summaries.single.name, 'Second');
        expect(summaries.single.description, 'Plan plan-2');
        expect(summaries.single.scheduledFor, isNull);
        expect(summaries.single.updatedAt, DateTime.utc(2026, 4, 3, 9));
        expect(
          await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
          ),
          isNull,
        );
      },
    );

    test('isolates local planning data between organizations', () async {
      await store.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [_planRecord(id: 'plan-1', name: 'Org 1')],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            position: 10,
            name: 'Session 1',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 10,
            songId: 'song-1',
            songTitle: 'Song 1',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 4, 3, 12),
      );

      await store.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-2',
        plans: [_planRecord(id: 'plan-2', name: 'Org 2')],
        sessions: const [
          CachedSessionRecord(
            id: 'session-2',
            planId: 'plan-2',
            position: 10,
            name: 'Session 2',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-2',
            planId: 'plan-2',
            sessionId: 'session-2',
            position: 10,
            songId: 'song-2',
            songTitle: 'Song 2',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 4, 3, 13),
      );

      expect(
        await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        hasLength(1),
      );
      expect(
        await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
        hasLength(1),
      );
    });

    test(
      'counts local song references within the active organization projection',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Org 1')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Session 1',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'Song 1',
            ),
            CachedSessionItemRecord(
              id: 'item-2',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 20,
              songId: 'song-1',
              songTitle: 'Song 1 repeat',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        expect(
          await store.countSongReferences(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          ),
          2,
        );
        expect(
          await store.countSongReferences(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-9',
          ),
          0,
        );
      },
    );

    test('deletes all authenticated planning data for one user', () async {
      await store.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [_planRecord(id: 'plan-1', name: 'Org 1')],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            position: 10,
            name: 'Session 1',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 10,
            songId: 'song-1',
            songTitle: 'Song 1',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 4, 3, 12),
      );
      await store.replaceActiveProjection(
        userId: 'user-2',
        organizationId: 'org-9',
        plans: [_planRecord(id: 'plan-9', name: 'Other user')],
        sessions: const [
          CachedSessionRecord(
            id: 'session-9',
            planId: 'plan-9',
            position: 10,
            name: 'Session 9',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-9',
            planId: 'plan-9',
            sessionId: 'session-9',
            position: 10,
            songId: 'song-9',
            songTitle: 'Song 9',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 4, 3, 12),
      );

      await store.deletePlanningDataForUser(userId: 'user-1');

      expect(
        await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
      expect(
        await store.readPlanSummaries(
          userId: 'user-2',
          organizationId: 'org-9',
        ),
        hasLength(1),
      );
      expect(
        await database.select(database.planningProjectionOwners).get(),
        hasLength(1),
      );
    });

    test(
      'keeps the previous projection when replacement input is structurally invalid',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Valid')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Session 1',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'Song 1',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        await expectLater(
          () => store.replaceActiveProjection(
            userId: 'user-1',
            organizationId: 'org-1',
            plans: [_planRecord(id: 'plan-2', name: 'Broken')],
            sessions: const [
              CachedSessionRecord(
                id: 'session-2',
                planId: 'missing-plan',
                position: 10,
                name: 'Broken session',
              ),
            ],
            items: const [
              CachedSessionItemRecord(
                id: 'item-2',
                planId: 'plan-2',
                sessionId: 'session-2',
                position: 10,
                songId: 'song-2',
                songTitle: 'Song 2',
              ),
            ],
            refreshedAt: DateTime.utc(2026, 4, 3, 13),
          ),
          throwsArgumentError,
        );

        expect(
          await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          hasLength(1),
        );
        expect(
          await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
          ),
          isNotNull,
        );
      },
    );

    test(
      'aborts a stale replacement before it can repopulate the projection',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Original')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Session 1',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'Song 1',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        await expectLater(
          () => store.replaceActiveProjection(
            userId: 'user-1',
            organizationId: 'org-1',
            plans: [_planRecord(id: 'plan-2', name: 'Stale')],
            sessions: const [
              CachedSessionRecord(
                id: 'session-2',
                planId: 'plan-2',
                position: 10,
                name: 'Session 2',
              ),
            ],
            items: const [
              CachedSessionItemRecord(
                id: 'item-2',
                planId: 'plan-2',
                sessionId: 'session-2',
                position: 10,
                songId: 'song-2',
                songTitle: 'Song 2',
              ),
            ],
            refreshedAt: DateTime.utc(2026, 4, 3, 13),
            shouldContinue: () => false,
          ),
          throwsA(isA<PlanningProjectionAbortedException>()),
        );

        final summaries = await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(summaries.single.id, 'plan-1');
      },
    );

    test(
      'preserves duplicate-song session items as distinct entries keyed by sessionItemId',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Plan')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Session',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'Repeat Song',
            ),
            CachedSessionItemRecord(
              id: 'item-2',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 20,
              songId: 'song-1',
              songTitle: 'Repeat Song',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        final detail = await store.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
        );

        expect(detail!.sessions.single.items.map((item) => item.id).toList(), [
          'item-1',
          'item-2',
        ]);
      },
    );

    test(
      'preserves deterministic ordering for plans, sessions, and session items',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [
            _planRecord(
              id: 'plan-c',
              name: 'Null scheduled',
              scheduledFor: null,
              updatedAt: DateTime.utc(2026, 4, 3, 8),
            ),
            _planRecord(
              id: 'plan-b',
              name: 'Later tie',
              scheduledFor: DateTime.utc(2026, 4, 6, 9),
              updatedAt: DateTime.utc(2026, 4, 3, 9),
            ),
            _planRecord(
              id: 'plan-a',
              name: 'Earlier',
              scheduledFor: DateTime.utc(2026, 4, 5, 9),
              updatedAt: DateTime.utc(2026, 4, 3, 7),
            ),
            _planRecord(
              id: 'plan-d',
              name: 'Later tie newer',
              scheduledFor: DateTime.utc(2026, 4, 6, 9),
              updatedAt: DateTime.utc(2026, 4, 3, 11),
            ),
          ],
          sessions: const [
            CachedSessionRecord(
              id: 'session-b',
              planId: 'plan-a',
              position: 20,
              name: 'Later session',
            ),
            CachedSessionRecord(
              id: 'session-a',
              planId: 'plan-a',
              position: 20,
              name: 'Earlier id session',
            ),
            CachedSessionRecord(
              id: 'session-z',
              planId: 'plan-a',
              position: 10,
              name: 'First session',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-b',
              planId: 'plan-a',
              sessionId: 'session-z',
              position: 20,
              songId: 'song-2',
              songTitle: 'Song 2',
            ),
            CachedSessionItemRecord(
              id: 'item-a',
              planId: 'plan-a',
              sessionId: 'session-z',
              position: 20,
              songId: 'song-1',
              songTitle: 'Song 1',
            ),
            CachedSessionItemRecord(
              id: 'item-z',
              planId: 'plan-a',
              sessionId: 'session-z',
              position: 10,
              songId: 'song-3',
              songTitle: 'Song 3',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        expect(
          (await store.readPlanSummaries(
            userId: 'user-1',
            organizationId: 'org-1',
          )).map((plan) => plan.id).toList(),
          ['plan-a', 'plan-d', 'plan-b', 'plan-c'],
        );

        final detail = await store.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-a',
        );

        expect(detail!.sessions.map((session) => session.id).toList(), [
          'session-z',
          'session-a',
          'session-b',
        ]);
        expect(detail.sessions.first.items.map((item) => item.id).toList(), [
          'item-z',
          'item-a',
          'item-b',
        ]);
      },
    );

    test(
      'preserves ownership metadata and normalized parent keys on child tables',
      () async {
        await store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Plan')],
          sessions: const [
            CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Session',
            ),
          ],
          items: const [
            CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'Song',
            ),
          ],
          refreshedAt: DateTime.utc(2026, 4, 3, 12),
        );

        final owner = await database
            .select(database.planningProjectionOwners)
            .getSingle();
        final session = await database
            .select(database.cachedPlanningSessions)
            .getSingle();
        final item = await database
            .select(database.cachedPlanningSessionItems)
            .getSingle();

        expect(owner.userId, 'user-1');
        expect(owner.organizationId, 'org-1');
        expect(session.planId, 'plan-1');
        expect(item.planId, 'plan-1');
        expect(item.sessionId, 'session-1');
        expect(item.songId, 'song-1');
      },
    );
  });

  group('DriftPlanningLocalStore storage recovery (D1)', () {
    // Mirrors the two-database shape in
    // test/offline/adversarial/storage_pressure_contract_test.dart (which
    // pins the unchanged BudgetedPlanningMutationStore path): the guarded
    // planning database fails every INSERT, and a SEPARATE, unwrapped song
    // catalog database backs the recovery's evictor.
    Future<
      ({
        PlanningLocalDatabase failingDatabase,
        DriftPlanningLocalStore store,
        SongCatalogDatabase evictionDatabase,
        int Function() revisionCount,
      })
    >
    buildGuardedStore({InsertFailureBudget? budget}) async {
      final failingExecutor = InsertFailingExecutor(
        NativeDatabase.memory(),
        budget,
      );
      final failingDatabase = PlanningLocalDatabase.connect(failingExecutor);
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
      final store = DriftPlanningLocalStore(
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
      'a failed replaceActiveProjection write evicts droppable catalog '
      'sources, retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.replaceActiveProjection(
            userId: 'user-1',
            organizationId: 'org-1',
            plans: [_planRecord(id: 'plan-1', name: 'Weekend Service')],
            sessions: const [],
            items: const [],
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

        // Never landed: nothing to read back.
        final summaries = await built.store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(summaries, isEmpty);
      },
    );

    test('a replaceActiveProjection write that fails once and succeeds on '
        'retry lands the projection, after evicting droppable catalog '
        'sources', () async {
      final built = await buildGuardedStore(
        budget: InsertFailureBudget(failuresRemaining: 1),
      );
      addTearDown(built.failingDatabase.close);
      addTearDown(built.evictionDatabase.close);

      await built.store.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [_planRecord(id: 'plan-1', name: 'Weekend Service')],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 8, 4),
      );

      final remainingSources = await built.evictionDatabase
          .select(built.evictionDatabase.cachedCatalogSources)
          .get();
      expect(remainingSources, isEmpty);

      final summaries = await built.store.readPlanSummaries(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(summaries, hasLength(1));
      expect(summaries.single.id, 'plan-1');
    });

    test(
      'a failed upsertSyncedPlan write evicts droppable catalog sources, '
      'retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.upsertSyncedPlan(
            userId: 'user-1',
            organizationId: 'org-1',
            plan: _planRecord(id: 'plan-1', name: 'Weekend Service'),
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

        // Never landed: nothing to read back.
        final summaries = await built.store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        );
        expect(summaries, isEmpty);
      },
    );

    test(
      'a failed upsertSyncedSession write evicts droppable catalog sources, '
      'retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.upsertSyncedSession(
            userId: 'user-1',
            organizationId: 'org-1',
            session: const CachedSessionRecord(
              id: 'session-1',
              planId: 'plan-1',
              position: 10,
              name: 'Worship',
            ),
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

        // Never landed: nothing to read back.
        final detail = await built.store.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
        );
        expect(detail, isNull);
      },
    );

    test(
      'a failed upsertSyncedSessionItem write evicts droppable catalog '
      'sources, retries once, and surfaces a typed LocalStorageWriteFailure',
      () async {
        final built = await buildGuardedStore();
        addTearDown(built.failingDatabase.close);
        addTearDown(built.evictionDatabase.close);

        await expectLater(
          () => built.store.upsertSyncedSessionItem(
            userId: 'user-1',
            organizationId: 'org-1',
            item: const CachedSessionItemRecord(
              id: 'item-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              position: 10,
              songId: 'song-1',
              songTitle: 'Song 1',
            ),
            sessionVersion: 2,
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

        // Never landed: nothing to read back.
        final detail = await built.store.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
        );
        expect(detail, isNull);
      },
    );

    test('PlanningProjectionAbortedException still passes through a guarded '
        'replaceActiveProjection without eviction or retry', () async {
      // No fault injection here: the underlying database is a plain,
      // non-failing database, so the ONLY way this can throw is
      // `shouldContinue` reporting a superseding refresh -- proving the
      // guard recognises PlanningProjectionAbortedException as a
      // LocalStorageDomainRejection rather than storage pressure.
      final database = PlanningLocalDatabase.inMemory();
      final evictionDatabase = SongCatalogDatabase.inMemory();
      addTearDown(database.close);
      addTearDown(evictionDatabase.close);
      var evictions = 0;
      final recovery = LocalStorageWriteRecovery(
        evictor: SongCatalogEvictor(
          database: evictionDatabase,
          accountant: CatalogStorageAccountant(evictionDatabase),
          onStorageFootprintChanged: () => evictions += 1,
        ),
      );
      final store = DriftPlanningLocalStore(database, writeRecovery: recovery);

      await expectLater(
        () => store.replaceActiveProjection(
          userId: 'user-1',
          organizationId: 'org-1',
          plans: [_planRecord(id: 'plan-1', name: 'Weekend Service')],
          sessions: const [],
          items: const [],
          refreshedAt: DateTime.utc(2026, 8, 4),
          shouldContinue: () => false,
        ),
        throwsA(isA<PlanningProjectionAbortedException>()),
      );

      expect(
        evictions,
        0,
        reason: 'a superseded refresh must never trigger eviction',
      );
    });
  });
}

CachedPlanRecord _planRecord({
  required String id,
  required String name,
  String description = 'Plan plan-1',
  DateTime? scheduledFor,
  DateTime? updatedAt,
}) {
  return CachedPlanRecord(
    id: id,
    name: name,
    description: id == 'plan-1' ? description : 'Plan $id',
    scheduledFor: scheduledFor,
    updatedAt: updatedAt ?? DateTime.utc(2026, 4, 3, 9),
  );
}
