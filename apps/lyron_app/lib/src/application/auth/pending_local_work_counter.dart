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
/// rather than being silently counted as zero. An undercount from a swallowed
/// failure could make a wipe look safe when it is not.
class PendingLocalWorkCounter {
  PendingLocalWorkCounter({
    required PlanningPendingWorkCountReader readPlanningPendingWorkCount,
    required SongPendingWorkCountReader readSongPendingWorkCount,
  }) : _readPlanningPendingWorkCount = readPlanningPendingWorkCount,
       _readSongPendingWorkCount = readSongPendingWorkCount;

  final PlanningPendingWorkCountReader _readPlanningPendingWorkCount;
  final SongPendingWorkCountReader _readSongPendingWorkCount;

  Future<int> count({required String userId}) async {
    final planningCount = await _readPlanningPendingWorkCount(userId: userId);
    final songCount = await _readSongPendingWorkCount(userId: userId);
    return planningCount + songCount;
  }
}
