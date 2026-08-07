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
  IntColumn get version => integer()();

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

class CachedCatalogSongMutations extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  TextColumn get songId => text()();
  TextColumn get slug => text()();
  TextColumn get title => text()();
  TextColumn get source => text()();
  IntColumn get version => integer()();
  TextColumn get syncStatus => text()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get syncErrorContext => text().nullable()();

  // D1 (docs/specs/2026-08-05-sync-snapshot-identity.md): local bookkeeping
  // only, incremented by the store on every local write to this row.
  // Identifies the exact content handed to a sync attempt so a post-sync
  // write can tell whether the row is still that content. This is NOT OCC:
  // `version`/`baseVersion` above track the *server's* view of the song and
  // feed the backend's optimistic-concurrency checks; `localRevision` tracks
  // only "has anything local written to this row since I last looked," is
  // never read by the backend, and is never part of a conflict decision. See
  // ADR-030 for why this exists and why `updatedAt` cannot substitute for it
  // (the device clock is unanchored -- LF-T6).
  IntColumn get localRevision => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {userId, organizationId, songId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, organizationId, slug},
  ];
}
