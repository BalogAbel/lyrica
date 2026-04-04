import 'package:drift/drift.dart';

class CachedCatalogSnapshots extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  DateTimeColumn get refreshedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId};
}

class CachedCatalogSummaries extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  TextColumn get songId => text()();
  TextColumn get slug => text()();
  TextColumn get title => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId, songId};
}

class CachedCatalogSources extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  TextColumn get songId => text()();
  TextColumn get source => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId, songId};
}
