import 'package:drift/drift.dart';

class PlanningProjectionOwners extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  DateTimeColumn get refreshedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId};
}

class CachedPlanningPlans extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  TextColumn get planId => text()();
  TextColumn get slug => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId, planId};
}

class CachedPlanningSessions extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  TextColumn get sessionId => text()();
  TextColumn get planId => text()();
  TextColumn get slug => text()();
  IntColumn get position => integer()();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId, sessionId};
}

class CachedPlanningSessionItems extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  TextColumn get sessionItemId => text()();
  TextColumn get planId => text()();
  TextColumn get sessionId => text()();
  IntColumn get position => integer()();
  TextColumn get songId => text()();
  TextColumn get songTitle => text()();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId, sessionItemId};
}
