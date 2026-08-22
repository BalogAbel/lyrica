import 'package:drift/drift.dart';

class CachedCatalogSnapshots extends Table {
  TextColumn get userId => text()();
  TextColumn get organizationId => text()();
  IntColumn get snapshotVersion => integer()();
  DateTimeColumn get refreshedAt => dateTime()();

  // D4 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  // Task 3.1): set the first time an incoming empty `listSongs()` response
  // is rejected against this (non-empty) stored snapshot -- the persisted
  // "one empty resolution already seen" fact `SongCatalogStore
  // .resolveEmptySnapshot` checks before deciding whether a second,
  // independent empty response may finally replace the snapshot. Persisted
  // on the row (not held in memory) so the confirmation can span cold
  // starts. Cleared back to null by every accepted `replaceActiveSnapshot`
  // call -- see that method's companion for why this must be written
  // explicitly rather than left to `insertOnConflictUpdate`'s column-omission
  // behavior.
  DateTimeColumn get pendingEmptyConfirmationAt => dateTime().nullable()();

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
