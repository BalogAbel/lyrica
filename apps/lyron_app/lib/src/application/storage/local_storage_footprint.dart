/// How much local storage the app is using, estimated from row content.
///
/// These are content-derived estimates (see `PlanningStorageAccountant`), not
/// true on-disk sizes: they exclude index and page overhead, and on web they
/// say nothing about what the browser has actually allocated. They are
/// comparable to each other and stable for a fixed corpus, which is what the
/// budget and the pressure classification need.
class LocalStorageFootprint {
  const LocalStorageFootprint({
    required this.mutationBytes,
    required this.mutationCount,
    required this.projectionBytes,
    required this.catalogBytes,
  });

  const LocalStorageFootprint.empty()
    : this(
        mutationBytes: 0,
        mutationCount: 0,
        projectionBytes: 0,
        catalogBytes: 0,
      );

  /// Pending planning mutations — unsynced user intent, never evictable.
  final int mutationBytes;

  /// Number of planning mutation rows, for the user-facing warning.
  final int mutationCount;

  /// Cached planning projection — re-fetchable, but never evicted: offline it
  /// is the only readable view.
  final int projectionBytes;

  /// Cached song catalog, including its own pending song mutations.
  final int catalogBytes;

  int get totalBytes => mutationBytes + projectionBytes + catalogBytes;
}

enum LocalStoragePressure { ok, warning, critical }
