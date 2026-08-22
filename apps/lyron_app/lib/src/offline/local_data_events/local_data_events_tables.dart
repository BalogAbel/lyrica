import 'package:drift/drift.dart';

class LocalDataEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get occurredAt => dateTime()();
  // 'purge' | 'eviction' -- stored as plain text, not a Drift enum column,
  // for forward-compat simplicity.
  TextColumn get kind => text()();
  // PurgeTarget.name equivalent, or an eviction-specific target string.
  TextColumn get target => text()();
  // PurgeReason.name; null only for eviction events (no PurgeReason applies
  // to eviction).
  TextColumn get reason => text().nullable()();
  TextColumn get userId => text().nullable()();
  IntColumn get rowsAffected => integer().nullable()();
}
