import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/pending_local_work_counter.dart';

void main() {
  group('PendingLocalWorkCounter', () {
    test('sums the planning and song work counts for one user', () async {
      final counter = PendingLocalWorkCounter(
        readPlanningPendingWorkCount: ({required userId}) async =>
            userId == 'user-1' ? 6 : -100,
        readSongPendingWorkCount: ({required userId}) async =>
            userId == 'user-1' ? 4 : -100,
      );

      final count = await counter.count(userId: 'user-1');

      expect(count, 10);
    });

    test(
      'propagates a planning count failure instead of treating it as zero',
      () async {
        final counter = PendingLocalWorkCounter(
          readPlanningPendingWorkCount: ({required userId}) async =>
              throw StateError('planning storage failure'),
          readSongPendingWorkCount: ({required userId}) async => 4,
        );

        await expectLater(
          counter.count(userId: 'user-1'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'planning storage failure',
            ),
          ),
        );
      },
    );

    test(
      'propagates a song count failure instead of treating it as zero',
      () async {
        final counter = PendingLocalWorkCounter(
          readPlanningPendingWorkCount: ({required userId}) async => 6,
          readSongPendingWorkCount: ({required userId}) async =>
              throw StateError('song storage failure'),
        );

        await expectLater(
          counter.count(userId: 'user-1'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'song storage failure',
            ),
          ),
        );
      },
    );
  });
}
