import 'dart:async';

import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/application/storage/local_storage_domain_rejection.dart';
import 'package:lyron_app/src/application/storage/local_storage_exhaustion_signal.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:sqlite3/sqlite3.dart';

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
  const LocalStorageWriteRecovery({
    required this._evictor,
    this._eventsRecorder,
  });

  final SongCatalogEvictor _evictor;

  /// Best-effort audit dependency (ADR-035): `null` in tests that construct
  /// this class directly, always supplied in production wiring. A failure
  /// writing the audit record must never change the shape of the failure
  /// this method surfaces -- see [_recordNoEvictionFailure].
  final LocalDataEventsRecorder? _eventsRecorder;

  Future<T> guard<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on LocalStorageDomainRejection {
      rethrow;
    } on Error {
      rethrow;
    } on Exception catch (error) {
      if (!_isExhaustionSignal(error)) {
        unawaited(_recordNoEvictionFailure(error));
        throw LocalStorageWriteFailure(cause: error, bytesFreedByEviction: 0);
      }
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

  /// D6 (docs/specs/2026-08-19-local-data-durability-contract.md): only a
  /// concrete exhaustion signal earns the evict-and-retry treatment. A real
  /// [SqliteException] is recognised structurally by result code --
  /// `SQLITE_FULL` (13) or `SQLITE_IOERR`'s primary code (10, which also
  /// covers every extended `IOERR_*` code via [SqliteException.resultCode]'s
  /// masking) -- rather than by a marker interface, since this codebase
  /// cannot retrofit an interface onto a third-party type.
  /// `SQLITE_BUSY` (primary code 5) deliberately does NOT match: it means a
  /// transient lock contention that would fail identically on immediate
  /// retry, not that storage is actually exhausted (Acceptance 6).
  bool _isExhaustionSignal(Exception error) {
    if (error is LocalStorageExhaustionSignal) {
      return true;
    }
    if (error is SqliteException) {
      return error.resultCode == 13 || error.resultCode == 10;
    }
    return false;
  }

  /// Best-effort: writes the "no eviction ran" audit record without letting
  /// a failure here change the shape of the [LocalStorageWriteFailure]
  /// already being thrown by the caller -- mirroring [LocalDataLifecycle]'s
  /// own "an audit-write failure must never masquerade as the real failure
  /// changing shape" policy (ADR-035).
  Future<void> _recordNoEvictionFailure(Exception error) async {
    final recorder = _eventsRecorder;
    if (recorder == null) {
      return;
    }
    try {
      await recorder.recordStorageWriteFailure();
    } catch (_) {
      // Best-effort only: the write's own failure (surfaced by guard's
      // caller) is what matters, not whether this audit record landed.
    }
  }
}
