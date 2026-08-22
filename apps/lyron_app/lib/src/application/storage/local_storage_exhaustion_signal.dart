/// Marker for exceptions that mean "the storage layer is actually
/// exhausted", as opposed to a merely transient failure (e.g. SQLITE_BUSY)
/// that would fail identically on immediate retry without eviction (D6,
/// LF-T4). A caller opts a synthetic/web-side exception into this treatment
/// by implementing this marker directly, mirroring
/// [LocalStorageDomainRejection]'s pattern. A real [SqliteException] does
/// NOT need to implement this -- it is recognised structurally by result
/// code instead (see [LocalStorageWriteRecovery.guard]), since it is a
/// third-party type this codebase cannot retrofit an interface onto.
abstract interface class LocalStorageExhaustionSignal implements Exception {}
