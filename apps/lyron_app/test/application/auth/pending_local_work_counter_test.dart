import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/pending_local_work_counter.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

void main() {
  group('PendingLocalWorkCounter', () {
    test('is zero when planning, pending songs and conflict songs are all '
        'empty', () async {
      final counter = PendingLocalWorkCounter(
        readPlanningPendingMutations:
            ({required userId, required organizationId}) async => const [],
        readPendingSongs: ({required userId, required organizationId}) async =>
            const [],
        readConflictSongs: ({required userId, required organizationId}) async =>
            const [],
      );

      final count = await counter.count(userId: 'u1', organizationId: 'o1');

      expect(count, 0);
    });

    test('sums planning pending mutations, pending songs and conflict '
        'songs when each source contributes', () async {
      final counter = PendingLocalWorkCounter(
        readPlanningPendingMutations:
            ({required userId, required organizationId}) async => [
              PlanningMutationRecord(
                aggregateId: 'plan-1',
                organizationId: organizationId,
                name: 'Weekend Service',
                kind: PlanningMutationKind.planEdit,
                syncStatus: PlanningMutationSyncStatus.pending,
                orderKey: 1,
                updatedAt: DateTime.utc(2026),
              ),
              PlanningMutationRecord(
                aggregateId: 'plan-2',
                organizationId: organizationId,
                name: 'Sunday Service',
                kind: PlanningMutationKind.planEdit,
                syncStatus: PlanningMutationSyncStatus.pending,
                orderKey: 2,
                updatedAt: DateTime.utc(2026),
              ),
            ],
        readPendingSongs: ({required userId, required organizationId}) async =>
            [
              SongMutationRecord(
                id: 'song-1',
                organizationId: organizationId,
                slug: 'alpha',
                title: 'Alpha',
                chordproSource: '',
                version: 1,
                baseVersion: null,
                syncStatus: SongSyncStatus.pendingCreate,
              ),
            ],
        readConflictSongs: ({required userId, required organizationId}) async =>
            [
              SongMutationRecord(
                id: 'song-2',
                organizationId: organizationId,
                slug: 'beta',
                title: 'Beta',
                chordproSource: '',
                version: 2,
                baseVersion: 1,
                syncStatus: SongSyncStatus.conflict,
              ),
              SongMutationRecord(
                id: 'song-3',
                organizationId: organizationId,
                slug: 'gamma',
                title: 'Gamma',
                chordproSource: '',
                version: 2,
                baseVersion: 1,
                syncStatus: SongSyncStatus.conflict,
              ),
            ],
      );

      final count = await counter.count(userId: 'u1', organizationId: 'o1');

      // 2 planning + 1 pending song + 2 conflict songs.
      expect(count, 5);
    });

    test('a source that throws propagates rather than being silently '
        'counted as zero', () async {
      final counter = PendingLocalWorkCounter(
        readPlanningPendingMutations:
            ({required userId, required organizationId}) async =>
                throw StateError('storage failure'),
        readPendingSongs: ({required userId, required organizationId}) async =>
            const [],
        readConflictSongs: ({required userId, required organizationId}) async =>
            const [],
      );

      // Not `0`: an undercount here understates what a wipe destroys, so
      // silently swallowing the failure would be the dangerous behaviour.
      await expectLater(
        counter.count(userId: 'u1', organizationId: 'o1'),
        throwsA(isA<StateError>()),
      );
    });

    test('a conflict-songs read that throws also propagates', () async {
      final counter = PendingLocalWorkCounter(
        readPlanningPendingMutations:
            ({required userId, required organizationId}) async => const [],
        readPendingSongs: ({required userId, required organizationId}) async =>
            const [],
        readConflictSongs: ({required userId, required organizationId}) async =>
            throw StateError('storage failure'),
      );

      await expectLater(
        counter.count(userId: 'u1', organizationId: 'o1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
