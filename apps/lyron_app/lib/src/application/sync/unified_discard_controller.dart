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
    required UnifiedDiscardStep discardSongs,
    required UnifiedDiscardStep discardPlanning,
    this.acquireSongDiscardLease,
    this.discardSongsWhileOwned,
  }) : _activeContextReader = activeContextReader,
       _discardSongs = discardSongs,
       _discardPlanning = discardPlanning;

  final UnifiedDiscardContextReader _activeContextReader;
  final UnifiedDiscardStep _discardSongs;
  final UnifiedDiscardStep _discardPlanning;
  final UnifiedDiscardLeaseAcquirer? acquireSongDiscardLease;
  final UnifiedDiscardOwnedSongsStep? discardSongsWhileOwned;

  Future<UnifiedDiscardResult> discardAll() async {
    final context = _activeContextReader();
    if (context == null) return UnifiedDiscardResult.discarded;
    await Future.wait([
      _discardSongs(context),
      _discardPlanning(context),
    ], eagerError: false);
    return UnifiedDiscardResult.discarded;
  }
}
