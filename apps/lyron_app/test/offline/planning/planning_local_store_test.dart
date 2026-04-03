import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

void main() {
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
