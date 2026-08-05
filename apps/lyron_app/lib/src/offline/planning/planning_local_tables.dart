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
  TextColumn get sessionId => text().nullable()();
  TextColumn get slug => text().nullable()();
  TextColumn get name => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  IntColumn get position => integer().nullable()();
  TextColumn get songId => text().nullable()();
  TextColumn get songTitle => text().nullable()();
  TextColumn get orderedSiblingIds => text().nullable()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get originSnapshotJson => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get orderKey => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Local bookkeeping only: incremented by the store on every local write
  /// to this row (a fold, a status write, anything). It identifies the
  /// exact content that was handed to a sync attempt, so a post-sync write
  /// can detect whether the row is still the one that was sent.
  ///
  /// This is NOT part of OCC and NEVER leaves the device -- unlike
  /// [baseVersion], which tracks the server's view of the aggregate.
  /// `updatedAt` cannot serve this purpose: two local writes inside the
  /// same millisecond collide, and a device clock can step backwards
  /// (LF-T6), so only a store-owned counter is guaranteed monotonic. See
  /// `docs/specs/2026-08-05-sync-snapshot-identity.md` (D1).
  IntColumn get localRevision => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {
    userId,
    organizationId,
    aggregateType,
    aggregateId,
  };
}
