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
  IntColumn get version => integer()();

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
  IntColumn get version => integer()();

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

class CachedPlanningMutations extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  TextColumn get aggregateType => text()();
  TextColumn get aggregateId => text()();
  TextColumn get mutationKind => text()();
  TextColumn get syncStatus => text()();
  TextColumn get planId => text().nullable()();
  TextColumn get slug => text().nullable()();
  TextColumn get name => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  IntColumn get position => integer().nullable()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get orderKey => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    userId,
    organizationId,
    aggregateType,
    aggregateId,
  };
}
