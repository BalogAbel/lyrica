/// Marker for exceptions that mean "this specific write was rejected by
/// domain policy", as opposed to "the write failed at the storage layer"
/// (LF-T4, see [LocalStorageWriteFailure]).
///
/// [LocalStorageWriteRecovery.guard] rethrows these untouched: retrying would
/// fail identically, and evicting droppable catalog sources would destroy
/// cached data for no benefit.
///
/// A caller opts an exception into this treatment by having the exception
/// class implement this marker directly (e.g.
/// `class LocalPlanningSlugConflictException implements
/// LocalStorageDomainRejection`), rather than the generic recovery boundary
/// hardcoding concrete exception types from every module that uses it. That
/// would be a layering violation: `application/storage` is lower-level than
/// both `application/planning` and `offline/song_catalog`, so it must not
/// import their exception types to recognise them. With the marker, planning
/// and the song catalog each declare their own domain rejections against a
/// contract `application/storage` owns, without either module needing to
/// know about the other, and any future domain rejection joins the same
/// policy the same way.
abstract interface class LocalStorageDomainRejection implements Exception {}
