import 'package:drift/drift.dart';

class LastKnownIdentityRows extends Table {
  IntColumn get rowId => integer()();
  TextColumn get userId => text()();
  TextColumn get email => text()();
  TextColumn get organizationId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  // D5 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  // Phase 4): the membership-revocation marker. Null means no empty
  // membership resolution is outstanding; non-null records when the first
  // one was recorded, for the audit trail and for a human reading the row --
  // never as an operand in the cooldown's duration comparison (that is
  // measured on a monotonic clock in LocalDataLifecycle, not here).
  DateTimeColumn get membershipRevokedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {rowId};
}
