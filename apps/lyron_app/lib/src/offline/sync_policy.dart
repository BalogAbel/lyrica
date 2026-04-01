enum ConflictResolution { manual }

class SyncPolicy {
  const SyncPolicy({
    required this.maxOfflineWindow,
    required this.conflictResolution,
  });

  final Duration maxOfflineWindow;
  final ConflictResolution conflictResolution;
}

const defaultSyncPolicy = SyncPolicy(
  maxOfflineWindow: Duration(days: 7),
  conflictResolution: ConflictResolution.manual,
);
