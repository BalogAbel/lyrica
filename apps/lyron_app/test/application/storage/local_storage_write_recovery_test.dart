import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/application/storage/local_storage_domain_rejection.dart';
import 'package:lyron_app/src/application/storage/local_storage_exhaustion_signal.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:sqlite3/sqlite3.dart';

/// Unit-level tests for the D1 shared storage-recovery boundary itself,
/// independent of any concrete Drift store. The three "recovery reaches
/// every guarded path" tests (song mutation store, catalog snapshot write,
/// planning projection write) live next to their respective stores and
/// exercise this class end-to-end through real Drift fault injection; these
/// tests instead pin [LocalStorageWriteRecovery.guard]'s own policy directly
/// against a fake write function and a fake evictor, so a failure here
/// points straight at the boundary rather than at one of its callers.
void main() {
  group('LocalStorageWriteRecovery.guard', () {
    test('returns the write result on success without touching the '
        'evictor', () async {
      final evictor = _FakeEvictor();
      final recovery = LocalStorageWriteRecovery(evictor: evictor);

      final result = await recovery.guard(() async => 'ok');

      expect(result, 'ok');
      expect(evictor.calls, 0);
    });

    test('rethrows a LocalStorageDomainRejection untouched, without eviction '
        'or retry', () async {
      final evictor = _FakeEvictor();
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      var attempts = 0;
      final rejection = _FakeDomainRejection();

      await expectLater(
        () => recovery.guard(() async {
          attempts += 1;
          throw rejection;
        }),
        throwsA(same(rejection)),
      );

      expect(attempts, 1, reason: 'must not retry a domain rejection');
      expect(evictor.calls, 0);
    });

    test('rethrows an Error untouched, without eviction or retry', () async {
      final evictor = _FakeEvictor();
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      var attempts = 0;

      await expectLater(
        () => recovery.guard(() async {
          attempts += 1;
          throw StateError('programming defect');
        }),
        throwsA(isA<StateError>()),
      );

      expect(attempts, 1, reason: 'must not retry a programming defect');
      expect(
        evictor.calls,
        0,
        reason: 'a defect must never be misreported as storage pressure',
      );
    });

    test('evicts droppable sources once and retries once on a real '
        'SQLITE_FULL exhaustion signal, returning the retry result when it '
        'succeeds', () async {
      final evictor = _FakeEvictor(freed: 42);
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      var attempts = 0;

      final result = await recovery.guard(() async {
        attempts += 1;
        if (attempts == 1) {
          throw SqliteException(
            extendedResultCode: 13, // SQLITE_FULL
            message: 'database or disk is full',
          );
        }
        return 'recovered';
      });

      expect(result, 'recovered');
      expect(attempts, 2);
      expect(evictor.calls, 1);
    });

    test('wraps a second failure as LocalStorageWriteFailure carrying the '
        'retry error and the bytes eviction freed', () async {
      final evictor = _FakeEvictor(freed: 7);
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      final retryError = Exception('still failing');
      var attempts = 0;

      await expectLater(
        () => recovery.guard(() async {
          attempts += 1;
          throw attempts == 1
              ? SqliteException(
                  extendedResultCode: 13, // SQLITE_FULL
                  message: 'database or disk is full',
                )
              : retryError;
        }),
        throwsA(
          isA<LocalStorageWriteFailure>()
              .having((failure) => failure.cause, 'cause', retryError)
              .having(
                (failure) => failure.bytesFreedByEviction,
                'bytesFreedByEviction',
                7,
              ),
        ),
      );

      expect(attempts, 2);
      expect(evictor.calls, 1);
    });

    test('when eviction itself throws, surfaces the ORIGINAL write error as '
        'the failure cause with bytesFreedByEviction: 0, and never retries '
        'the write', () async {
      final evictor = _FakeEvictor(throws: true);
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      final originalError = _FakeExhaustionSignal();
      var attempts = 0;

      await expectLater(
        () => recovery.guard(() async {
          attempts += 1;
          throw originalError;
        }),
        throwsA(
          isA<LocalStorageWriteFailure>()
              .having((failure) => failure.cause, 'cause', originalError)
              .having(
                (failure) => failure.bytesFreedByEviction,
                'bytesFreedByEviction',
                0,
              ),
        ),
      );

      expect(
        attempts,
        1,
        reason:
            'must not retry into a store recovery could not even evict '
            'from',
      );
      expect(evictor.calls, 1);
    });

    test('a plain Exception that is not a recognised exhaustion signal never '
        'evicts, never retries, and surfaces LocalStorageWriteFailure '
        'immediately (D6, LF-T4: a merely transient failure must not be '
        'treated as storage pressure)', () async {
      final evictor = _FakeEvictor();
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      final error = Exception('some unrelated transient failure');
      var attempts = 0;

      await expectLater(
        () => recovery.guard(() async {
          attempts += 1;
          throw error;
        }),
        throwsA(
          isA<LocalStorageWriteFailure>()
              .having((failure) => failure.cause, 'cause', error)
              .having(
                (failure) => failure.bytesFreedByEviction,
                'bytesFreedByEviction',
                0,
              ),
        ),
      );

      expect(attempts, 1, reason: 'must not retry a non-exhaustion failure');
      expect(
        evictor.calls,
        0,
        reason: 'must not evict for a non-exhaustion failure',
      );
    });

    test('a guarded write throwing SqliteException(BUSY) performs no '
        'eviction and surfaces LocalStorageWriteFailure immediately, '
        'without retrying (Acceptance 6, D6, LF-T4)', () async {
      final evictor = _FakeEvictor();
      final recovery = LocalStorageWriteRecovery(evictor: evictor);
      final busyError = SqliteException(
        extendedResultCode: 5, // SQLITE_BUSY
        message: 'database is locked',
      );
      var attempts = 0;

      await expectLater(
        () => recovery.guard(() async {
          attempts += 1;
          throw busyError;
        }),
        throwsA(
          isA<LocalStorageWriteFailure>()
              .having((failure) => failure.cause, 'cause', busyError)
              .having(
                (failure) => failure.bytesFreedByEviction,
                'bytesFreedByEviction',
                0,
              ),
        ),
      );

      expect(
        attempts,
        1,
        reason:
            'SQLITE_BUSY is transient -- retrying without eviction '
            'would fail identically, so guard must not retry it at all',
      );
      expect(
        evictor.calls,
        0,
        reason: 'evictDroppable must never be called for SQLITE_BUSY',
      );
    });

    test('records a best-effort storage-write-failure audit event when the '
        'exception is not an exhaustion signal', () async {
      final evictor = _FakeEvictor();
      final recorder = _FakeEventsRecorder();
      final recovery = LocalStorageWriteRecovery(
        evictor: evictor,
        eventsRecorder: recorder,
      );
      final error = Exception('some unrelated transient failure');

      await expectLater(
        () => recovery.guard(() async => throw error),
        throwsA(isA<LocalStorageWriteFailure>()),
      );

      // The write function above never receives a userId; the audit call
      // must still happen exactly once, without one.
      expect(recorder.calls, 1);
    });

    test('an audit-recording failure must never change the surfaced '
        'failure', () async {
      final evictor = _FakeEvictor();
      final recorder = _FakeEventsRecorder(throws: true);
      final recovery = LocalStorageWriteRecovery(
        evictor: evictor,
        eventsRecorder: recorder,
      );
      final error = Exception('some unrelated transient failure');

      await expectLater(
        () => recovery.guard(() async => throw error),
        throwsA(
          isA<LocalStorageWriteFailure>().having(
            (failure) => failure.cause,
            'cause',
            error,
          ),
        ),
      );
    });
  });
}

/// A domain rejection distinct from any real one in the app, so a passing
/// test proves the boundary reacts to the marker interface itself rather
/// than to some concrete type it happens to special-case.
class _FakeDomainRejection implements LocalStorageDomainRejection {
  @override
  String toString() => '_FakeDomainRejection()';
}

/// Controls eviction outcome without touching a real database, so these
/// tests exercise only [LocalStorageWriteRecovery]'s own policy.
class _FakeEvictor implements SongCatalogEvictor {
  _FakeEvictor({this.freed = 0, this.throws = false});

  final int freed;
  final bool throws;
  int calls = 0;

  @override
  Future<int> evictDroppable() async {
    calls += 1;
    if (throws) {
      throw Exception('simulated eviction failure');
    }
    return freed;
  }

  @override
  Future<int> evictToBudget({
    required int targetBytes,
    required String activeUserId,
    required String activeOrganizationId,
  }) {
    throw UnimplementedError(
      'not exercised by LocalStorageWriteRecovery.guard, which only ever '
      'calls evictDroppable (the emergency path)',
    );
  }
}

/// A synthetic exhaustion signal distinct from any real one in the app, so a
/// passing test proves the boundary reacts to the marker interface itself
/// (not to a hardcoded concrete type such as [SqliteException]).
class _FakeExhaustionSignal implements LocalStorageExhaustionSignal {
  @override
  String toString() => '_FakeExhaustionSignal()';
}

/// Records whether the no-eviction audit path was reached, without touching
/// a real database.
class _FakeEventsRecorder implements LocalDataEventsRecorder {
  _FakeEventsRecorder({this.throws = false});

  final bool throws;
  int calls = 0;

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {
    calls += 1;
    if (throws) {
      throw Exception('simulated audit-write failure');
    }
  }

  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}
}
