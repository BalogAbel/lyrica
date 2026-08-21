import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/offline/local_data_events/drift_local_data_events_store.dart';
import 'package:lyron_app/src/offline/local_data_events/local_data_events_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late LocalDataEventsDatabase database;
  late DriftLocalDataEventsStore store;

  setUp(() {
    database = LocalDataEventsDatabase.inMemory();
    store = DriftLocalDataEventsStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('recordPurge with all fields populated inserts one row with all '
      'columns correct', () async {
    await store.recordPurge(
      target: PurgeTarget.songCatalog,
      reason: PurgeReason.userSignOut,
      userId: 'u1',
      rowsAffected: 42,
    );

    final rows = await database.select(database.localDataEvents).get();

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.kind, 'purge');
    expect(row.target, 'songCatalog');
    expect(row.reason, 'userSignOut');
    expect(row.userId, 'u1');
    expect(row.rowsAffected, 42);
  });

  test('recordPurge with null userId/rowsAffected inserts a row with those '
      'columns null but reason still populated', () async {
    await store.recordPurge(
      target: PurgeTarget.identity,
      reason: PurgeReason.accountDeleted,
    );

    final rows = await database.select(database.localDataEvents).get();

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.userId, isNull);
    expect(row.rowsAffected, isNull);
    expect(row.reason, 'accountDeleted');
  });

  test('multiple recordPurge calls insert independent rows, not overwritten', () async {
    await store.recordPurge(
      target: PurgeTarget.planningData,
      reason: PurgeReason.differentUserSignIn,
      userId: 'u1',
    );
    await store.recordPurge(
      target: PurgeTarget.planningData,
      reason: PurgeReason.membershipRevokedConfirmed,
      userId: 'u2',
    );

    final rows = await database.select(database.localDataEvents).get();

    expect(rows, hasLength(2));
    expect(rows.map((r) => r.id).toSet(), hasLength(2));
    expect(rows.map((r) => r.userId), containsAll(['u1', 'u2']));
  });

  test('recordEviction inserts one row with kind eviction and null reason', () async {
    await store.recordEviction(
      target: 'cachedCatalogSources',
      userId: 'u1',
      rowsAffected: 7,
    );

    final rows = await database.select(database.localDataEvents).get();

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.kind, 'eviction');
    expect(row.target, 'cachedCatalogSources');
    expect(row.reason, isNull);
    expect(row.userId, 'u1');
    expect(row.rowsAffected, 7);
  });

  test('target.name for each PurgeTarget round-trips as plain text', () async {
    for (final target in PurgeTarget.values) {
      await store.recordPurge(
        target: target,
        reason: PurgeReason.userSignOut,
      );
    }

    final rows = await database.select(database.localDataEvents).get();

    expect(
      rows.map((r) => r.target).toSet(),
      {'songCatalog', 'planningData', 'identity'},
    );
  });
}
