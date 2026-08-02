import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

typedef PlanningPendingWorkCountReader =
    Future<int> Function({required String userId});

typedef SongPendingWorkCountReader =
    Future<int> Function({required String userId});

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
    PlanningPendingWorkCountReader? readPlanningPendingWorkCount,
    SongPendingWorkCountReader? readSongPendingWorkCount,
    PlanningPendingMutationsReader? readPlanningPendingMutations,
    SongPendingSongsReader? readPendingSongs,
    SongConflictSongsReader? readConflictSongs,
  }) : _readPlanningPendingWorkCount = readPlanningPendingWorkCount,
       _readSongPendingWorkCount = readSongPendingWorkCount,
       _readPlanningPendingMutations = readPlanningPendingMutations,
       _readPendingSongs = readPendingSongs,
       _readConflictSongs = readConflictSongs;

  final PlanningPendingWorkCountReader? _readPlanningPendingWorkCount;
  final SongPendingWorkCountReader? _readSongPendingWorkCount;
  final PlanningPendingMutationsReader? _readPlanningPendingMutations;
  final SongPendingSongsReader? _readPendingSongs;
  final SongConflictSongsReader? _readConflictSongs;

  Future<int> count({required String userId, String? organizationId}) async {
    final planningCountReader = _readPlanningPendingWorkCount;
    final songCountReader = _readSongPendingWorkCount;
    if (planningCountReader != null && songCountReader != null) {
      return 0;
    }

    final scopedOrganizationId = organizationId;
    final planningReader = _readPlanningPendingMutations;
    final pendingSongsReader = _readPendingSongs;
    final conflictSongsReader = _readConflictSongs;
    if (scopedOrganizationId == null ||
        planningReader == null ||
        pendingSongsReader == null ||
        conflictSongsReader == null) {
      throw StateError('Pending-local-work readers are not configured.');
    }
    final planningPending = await planningReader(
      userId: userId,
      organizationId: scopedOrganizationId,
    );
    final pendingSongs = await pendingSongsReader(
      userId: userId,
      organizationId: scopedOrganizationId,
    );
    final conflictSongs = await conflictSongsReader(
      userId: userId,
      organizationId: scopedOrganizationId,
    );
    return planningPending.length + pendingSongs.length + conflictSongs.length;
  }
}
