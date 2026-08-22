import 'package:drift/drift.dart';

class LastKnownIdentityRows extends Table {
  IntColumn get rowId => integer()();
  TextColumn get userId => text()();
  TextColumn get email => text()();
  TextColumn get organizationId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  // D5 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  // Phase 4 Task 4.1): set on the first verified-empty-membership
  // resolution for this user, before any purge; null means either "never
  // quarantined" or "quarantine has been resolved" (Task 4.3 clears it on
  // a later non-empty resolution).
  DateTimeColumn get membershipRevokedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {rowId};
}
