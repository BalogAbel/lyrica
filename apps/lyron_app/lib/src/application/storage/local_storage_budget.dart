import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';

/// Thresholds for the two storage ladders.
///
/// The mutation thresholds bound unsynced local intent (LF-T3). Catalog
/// eviction cannot relieve them, because pending mutations are protected, so
/// the only remedies are syncing or discarding.
///
/// The total thresholds describe overall storage pressure (LF-T4) and drive
/// the surfaced pressure classification (`warning`/`critical`). Crossing a
/// total threshold does not itself trigger eviction: the only production
/// eviction trigger is a storage write that actually fails (see
/// `SongCatalogEvictor`).
///
/// Defaults are deliberately out of reach of normal use. A budget that bites
/// during ordinary planning would be the wrong budget: the purpose is to make
/// growth bounded and observable, and to give a signal before the storage
/// substrate fails. They are constructor parameters so tests can use tiny
/// budgets.
class LocalStorageBudget {
  const LocalStorageBudget({
    this.mutationWarnBytes = 1 * 1024 * 1024,
    this.mutationRefuseBytes = 4 * 1024 * 1024,
    this.totalWarnBytes = 128 * 1024 * 1024,
    this.totalCriticalBytes = 192 * 1024 * 1024,
  });

  final int mutationWarnBytes;
  final int mutationRefuseBytes;
  final int totalWarnBytes;
  final int totalCriticalBytes;

  bool refusesNewMutation(int mutationBytes) =>
      mutationBytes >= mutationRefuseBytes;

  LocalStoragePressure classify(LocalStorageFootprint footprint) {
    if (footprint.mutationBytes >= mutationRefuseBytes ||
        footprint.totalBytes >= totalCriticalBytes) {
      return LocalStoragePressure.critical;
    }
    if (footprint.mutationBytes >= mutationWarnBytes ||
        footprint.totalBytes >= totalWarnBytes) {
      return LocalStoragePressure.warning;
    }
    return LocalStoragePressure.ok;
  }
}
