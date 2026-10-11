import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/import_run_tracker.dart';

void main() {
  group('ImportRunTracker', () {
    test('isRunningFor is true only for the reporting user', () {
      final tracker = ImportRunTracker();
      final owner = Object();

      tracker.report(owner, userId: 'user-1', running: true);

      expect(tracker.isRunning, isTrue);
      expect(tracker.isRunningFor('user-1'), isTrue);
      expect(tracker.isRunningFor('user-2'), isFalse);
    });

    test('a run whose user is unknown counts for every user', () {
      final tracker = ImportRunTracker();

      tracker.report(Object(), userId: null, running: true);

      expect(tracker.isRunningFor('user-1'), isTrue);
      expect(tracker.isRunningFor('user-2'), isTrue);
    });

    test('removing the owner clears its run', () {
      final tracker = ImportRunTracker();
      final owner = Object();
      tracker.report(owner, userId: 'user-1', running: true);

      tracker.report(owner, userId: null, running: false);

      expect(tracker.isRunning, isFalse);
      expect(tracker.isRunningFor('user-1'), isFalse);
    });

    test('two owners are tracked independently', () {
      final tracker = ImportRunTracker();
      final a = Object();
      final b = Object();
      tracker.report(a, userId: 'user-1', running: true);
      tracker.report(b, userId: 'user-2', running: true);

      tracker.report(a, userId: 'user-1', running: false);

      expect(tracker.isRunningFor('user-1'), isFalse);
      expect(tracker.isRunningFor('user-2'), isTrue);
    });
  });
}
