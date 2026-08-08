import 'package:lyron_app/src/application/storage/local_storage_domain_rejection.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';

/// The single storage-recovery boundary shared by every local write that can
/// grow stored bytes (ADR-028; decision D1 of
/// `docs/specs/2026-08-04-storage-recovery-boundary-and-budget-admission.md`).
///
/// [guard] runs [write] and applies one policy to how it can fail:
///
/// 1. it succeeds -- the result is returned as-is;
/// 2. it throws a [LocalStorageDomainRejection] (a caller-declared domain
///    rejection such as a slug conflict) -- rethrown untouched. Retrying
///    would fail identically, and evicting would destroy cached data for
///    nothing;
/// 3. it throws an [Error] -- rethrown untouched. By Dart convention `Error`
///    subclasses (`ArgumentError`, `StateError`, `TypeError`, ...) mean a
///    programming defect, never storage pressure, and must never be
///    misreported as such;
/// 4. it throws any other [Exception] -- treated as storage pressure
///    (LF-T4): droppable catalog sources are evicted and [write] is retried
///    once. Every write guarded by this boundary is an upsert (or otherwise
///    idempotent) keyed by its own aggregate, so a partially applied first
///    attempt cannot duplicate on retry. If the retry also fails, the
///    failure is wrapped as a typed [LocalStorageWriteFailure] rather than
///    swallowed. If eviction itself throws, the write is never retried, and
///    the ORIGINAL write error is surfaced as the failure's cause (with
///    `bytesFreedByEviction: 0`) -- that is what the caller actually needs
///    to see, since the eviction failure is a secondary symptom, plausibly
///    of the same underlying condition (disk full, quota).
///
/// [SongCatalogEvictor.evictDroppable] deletes only cached song sources via a
/// raw SQL statement against [SongCatalogDatabase] -- it never goes through
/// any [guard]ed write itself. So a guarded catalog write's recovery path can
/// never recurse back into a guard: eviction is structurally outside every
/// write this boundary protects, and shrinking writes (deletes) are never
/// guarded in the first place (see the call sites for why).
class LocalStorageWriteRecovery {
  const LocalStorageWriteRecovery({required this._evictor});

  final SongCatalogEvictor _evictor;

  Future<T> guard<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on LocalStorageDomainRejection {
      rethrow;
    } on Exception catch (error) {
      final int freed;
      try {
        freed = await _evictor.evictDroppable();
      } on Exception {
        throw LocalStorageWriteFailure(cause: error, bytesFreedByEviction: 0);
      }
      try {
        return await write();
      } catch (retryError) {
        throw LocalStorageWriteFailure(
          cause: retryError,
          bytesFreedByEviction: freed,
        );
      }
    }
  }
}
