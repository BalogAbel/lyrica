typedef PlanningPendingWorkCountReader =
    Future<int> Function({required String userId});

typedef SongPendingWorkCountReader =
    Future<int> Function({required String userId});

/// Combined count of local work a different-user sign-in wipe would destroy.
/// The wipe deletes both subsystems across every organization owned by the
/// prior user, so leaving either source out of the count would understate what
/// is at stake -- a specific wrong number, worse than none.
///
/// Neither count is caught here: if a source throws, the failure propagates
/// out of [count] rather than being silently counted as zero. This class does
/// not decide what a caller does with that failure -- in production,
/// `auth_providers.dart`'s `countPriorPendingWorkFor` wraps the call in
/// `catch (_) { return null; }`, turning it into "unknown," and
/// `resolveReauth`'s D5 contract treats unknown the same as nonzero (never as
/// zero), so a storage failure here still requires confirmation rather than
/// silently authorising a wipe (N3, PR #64 review: this paragraph replaces a
/// version that implied propagation alone was what prevented that outcome).
class PendingLocalWorkCounter {
  PendingLocalWorkCounter({
    required PlanningPendingWorkCountReader readPlanningPendingWorkCount,
    required SongPendingWorkCountReader readSongPendingWorkCount,
  }) : _readPlanningPendingWorkCount = readPlanningPendingWorkCount,
       _readSongPendingWorkCount = readSongPendingWorkCount;

  final PlanningPendingWorkCountReader _readPlanningPendingWorkCount;
  final SongPendingWorkCountReader _readSongPendingWorkCount;

  Future<int> count({required String userId}) async {
    // Read in parallel: the two sources are independent, so there is no
    // reason to pay their latency serially before the confirmation dialog
    // can show a count (N3, PR #64 review). Future.wait still propagates a
    // failure from either source, matching the class doc above.
    final counts = await Future.wait([
      _readPlanningPendingWorkCount(userId: userId),
      _readSongPendingWorkCount(userId: userId),
    ]);
    return counts[0] + counts[1];
  }
}
