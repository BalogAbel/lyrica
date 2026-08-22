import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';

import 'local_data_events_database.dart';

/// A single row of the [LocalDataEvents] audit trail, read back for display
/// (e.g. the diagnostics screen) rather than for further mutation.
class LocalDataEventRecord {
  const LocalDataEventRecord({
    required this.id,
    required this.occurredAt,
    required this.kind,
    required this.target,
    required this.reason,
    required this.userId,
    required this.rowsAffected,
  });

  final int id;
  final DateTime occurredAt;
  final String kind;
  final String target;
  final String? reason;
  final String? userId;
  final int? rowsAffected;
}

/// Read-only access to the [LocalDataEvents] audit trail, separate from
/// [LocalDataEventsRecorder]'s write-only contract.
abstract interface class LocalDataEventsReader {
  Future<List<LocalDataEventRecord>> readRecent({int limit});
}

class DriftLocalDataEventsStore
    implements LocalDataEventsRecorder, LocalDataEventsReader {
  const DriftLocalDataEventsStore(this._database);

  final LocalDataEventsDatabase _database;

  factory DriftLocalDataEventsStore.local() {
    return DriftLocalDataEventsStore(LocalDataEventsDatabase.local());
  }

  factory DriftLocalDataEventsStore.inMemory() {
    return DriftLocalDataEventsStore(LocalDataEventsDatabase.inMemory());
  }

  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {
    await _database
        .into(_database.localDataEvents)
        .insert(
          LocalDataEventsCompanion.insert(
            occurredAt: DateTime.now().toUtc(),
            kind: 'purge',
            target: target.name,
            reason: Value(reason.name),
            userId: Value(userId),
            rowsAffected: Value(rowsAffected),
          ),
        );
  }

  /// Eviction events are recorded here too, under a distinct non-purge kind.
  /// Schema/store readiness only -- no eviction call site exists yet; a
  /// later phase wires a caller.
  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {
    await _database
        .into(_database.localDataEvents)
        .insert(
          LocalDataEventsCompanion.insert(
            occurredAt: DateTime.now().toUtc(),
            kind: 'eviction',
            target: target,
            reason: const Value(null),
            userId: Value(userId),
            rowsAffected: Value(rowsAffected),
          ),
        );
  }

  /// D4 (docs/specs/2026-08-19-local-data-durability-contract.md): records
  /// an empty `listSongs()` response rejected against a non-empty stored
  /// snapshot. Not a purge -- no [PurgeReason] applies here, unlike
  /// `recordPurge` above.
  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {
    await _database
        .into(_database.localDataEvents)
        .insert(
          LocalDataEventsCompanion.insert(
            occurredAt: DateTime.now().toUtc(),
            kind: 'empty-snapshot-rejected',
            target: 'songCatalog',
            // `reason` is generically "context detail for this kind", not
            // always a PurgeReason: for this non-purge kind, repurpose it to
            // carry organizationId so a multi-org user's audit trail can
            // tell which org's catalog was rejected.
            reason: Value(organizationId),
            userId: Value(userId),
            rowsAffected: const Value(null),
          ),
        );
  }

  /// D6 (docs/specs/2026-08-19-local-data-durability-contract.md): records a
  /// guarded write's failure when [LocalStorageWriteRecovery.guard] did not
  /// recognise the exception as a concrete storage-exhaustion signal, so no
  /// eviction ran. `target` is fixed to `'songCatalog'`: `guard()` is the
  /// generic storage-recovery boundary shared by every guarded write
  /// (planning and catalog alike) and has no store-specific context to
  /// attribute the failure to at the point it calls this method -- the song
  /// catalog is nonetheless the more useful default to surface on the
  /// diagnostics screen, since it is the store this contract (D6) exists
  /// for. `reason`/`rowsAffected` are always null: there is no eviction
  /// reason and no rows were touched, unlike `recordEviction`.
  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {
    await _database
        .into(_database.localDataEvents)
        .insert(
          LocalDataEventsCompanion.insert(
            occurredAt: DateTime.now().toUtc(),
            kind: 'storage-write-failure-no-eviction',
            target: 'songCatalog',
            reason: const Value(null),
            userId: Value(userId),
            rowsAffected: const Value(null),
          ),
        );
  }

  @override
  Future<List<LocalDataEventRecord>> readRecent({int limit = 200}) async {
    // Ordered by the autoincrement primary key alone, not `occurredAt`: `id`
    // is strictly monotonic with insertion order (no second-level precision
    // loss, no tiebreak needed) and, being the primary key, this lets SQLite
    // satisfy the query from the primary-key index instead of a full-table
    // scan + sort on an unbounded, never-trimmed table.
    final query = _database.select(_database.localDataEvents)
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => LocalDataEventRecord(
            id: row.id,
            occurredAt: row.occurredAt,
            kind: row.kind,
            target: row.target,
            reason: row.reason,
            userId: row.userId,
            rowsAffected: row.rowsAffected,
          ),
        )
        .toList();
  }
}
