import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';

import 'local_data_events_database.dart';

class DriftLocalDataEventsStore implements LocalDataEventsRecorder {
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
    await _database.into(_database.localDataEvents).insert(
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
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {
    await _database.into(_database.localDataEvents).insert(
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
}
