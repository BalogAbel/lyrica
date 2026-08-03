import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';

enum UnifiedDiscardResult { discarded, syncInProgress }

class UnifiedDiscardContext {
  const UnifiedDiscardContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

typedef UnifiedDiscardContextReader = UnifiedDiscardContext? Function();
typedef UnifiedDiscardStep =
    Future<void> Function(UnifiedDiscardContext context);
typedef UnifiedDiscardLeaseAcquirer =
    Future<SongDiscardLeaseAcquisition> Function(UnifiedDiscardContext context);
typedef UnifiedDiscardOwnedSongsStep =
    Future<void> Function(
      UnifiedDiscardContext context,
      SongDiscardLease lease,
    );

class UnifiedDiscardController {
  UnifiedDiscardController({
    required UnifiedDiscardContextReader activeContextReader,
    required UnifiedDiscardStep discardPlanning,
    required this.acquireSongDiscardLease,
    required this.discardSongsWhileOwned,
  }) : _activeContextReader = activeContextReader,
       _discardPlanning = discardPlanning;

  final UnifiedDiscardContextReader _activeContextReader;
  final UnifiedDiscardStep _discardPlanning;
  final UnifiedDiscardLeaseAcquirer acquireSongDiscardLease;
  final UnifiedDiscardOwnedSongsStep discardSongsWhileOwned;

  Future<UnifiedDiscardResult> discardAll() async {
    final context = _activeContextReader();
    // Intentional: no active context means there is nothing to discard, so
    // `discarded` here means "no work was owed", not "work completed". The
    // popup treats this result as success either way, which is correct only
    // because a null context implies zero pending song/planning mutations
    // for this caller in the first place.
    if (context == null) return UnifiedDiscardResult.discarded;

    final acquisition = await acquireSongDiscardLease(context);
    if (acquisition.outcome == SongDiscardLeaseOutcome.syncInProgress) {
      return UnifiedDiscardResult.syncInProgress;
    }

    final lease = acquisition.lease!;
    try {
      await Future.wait([
        discardSongsWhileOwned(context, lease),
        _discardPlanning(context),
      ], eagerError: false);
    } finally {
      lease.release();
    }
    return UnifiedDiscardResult.discarded;
  }
}
