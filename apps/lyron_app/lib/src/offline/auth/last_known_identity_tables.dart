import 'package:drift/drift.dart';

class LastKnownIdentityRows extends Table {
  IntColumn get rowId => integer()();
  TextColumn get userId => text()();
  TextColumn get email => text()();
  TextColumn get organizationId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {rowId};
}
