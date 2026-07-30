import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

/// Matches [PlanningMutationStore.readPendingMutations]'s signature, taken as
/// an injected reader so this counter is testable without Drift.
typedef PlanningPendingMutationsReader =
    Future<List<PlanningMutationRecord>> Function({
      required String userId,
      required String organizationId,
    });

/// Matches [SongMutationStore.readPendingSongs]'s signature.
typedef SongPendingSongsReader =
    Future<List<SongMutationRecord>> Function({
      required String userId,
      required String organizationId,
    });

/// Matches [SongMutationStore.readConflictSongs]'s signature.
typedef SongConflictSongsReader =
    Future<List<SongMutationRecord>> Function({
      required String userId,
      required String organizationId,
    });

/// Combined count of local work a different-user sign-in wipe would destroy:
/// planning pending mutations + pending songs + conflict songs. The wipe
/// deletes both subsystems, so leaving either source out of the count would
/// understate what is at stake -- a specific wrong number, worse than none.
///
/// Each source is read in full and none is caught here: if a source throws,
/// the failure propagates rather than being silently counted as zero. An
/// undercount from a swallowed failure could make a wipe look safe when it
/// is not.
class PendingLocalWorkCounter {
  PendingLocalWorkCounter({
    required PlanningPendingMutationsReader readPlanningPendingMutations,
    required SongPendingSongsReader readPendingSongs,
    required SongConflictSongsReader readConflictSongs,
  }) : _readPlanningPendingMutations = readPlanningPendingMutations,
       _readPendingSongs = readPendingSongs,
       _readConflictSongs = readConflictSongs;

  final PlanningPendingMutationsReader _readPlanningPendingMutations;
  final SongPendingSongsReader _readPendingSongs;
  final SongConflictSongsReader _readConflictSongs;

  Future<int> count({
    required String userId,
    required String organizationId,
  }) async {
    final planningPending = await _readPlanningPendingMutations(
      userId: userId,
      organizationId: organizationId,
    );
    final pendingSongs = await _readPendingSongs(
      userId: userId,
      organizationId: organizationId,
    );
    final conflictSongs = await _readConflictSongs(
      userId: userId,
      organizationId: organizationId,
    );
    return planningPending.length + pendingSongs.length + conflictSongs.length;
  }
}
