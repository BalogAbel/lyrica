/// Thrown when a local write fails at the storage layer and still fails after
/// eviction and one retry (LF-T4).
///
/// The failure is never swallowed: the caller learns that the edit did not
/// reach local storage.
class LocalStorageWriteFailure implements Exception {
  const LocalStorageWriteFailure({
    required this.cause,
    required this.bytesFreedByEviction,
  });

  final Object cause;
  final int bytesFreedByEviction;

  @override
  String toString() =>
      'LocalStorageWriteFailure(cause: $cause, '
      'bytesFreedByEviction: $bytesFreedByEviction)';
}
