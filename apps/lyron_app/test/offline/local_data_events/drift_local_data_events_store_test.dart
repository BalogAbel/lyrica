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

  test(
    'multiple recordPurge calls insert independent rows, not overwritten',
    () async {
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
    },
  );

  test(
    'recordEviction inserts one row with kind eviction and null reason',
    () async {
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
    },
  );

  test('target.name for each PurgeTarget round-trips as plain text', () async {
    for (final target in PurgeTarget.values) {
      await store.recordPurge(target: target, reason: PurgeReason.userSignOut);
    }

    final rows = await database.select(database.localDataEvents).get();

    expect(rows.map((r) => r.target).toSet(), {
      'songCatalog',
      'planningData',
      'identity',
    });
  });

  test('readRecent returns empty list on an empty store', () async {
    final records = await store.readRecent();

    expect(records, isEmpty);
  });

  test('readRecent orders records newest-first', () async {
    await store.recordPurge(
      target: PurgeTarget.songCatalog,
      reason: PurgeReason.userSignOut,
      userId: 'u1',
    );
    await store.recordPurge(
      target: PurgeTarget.planningData,
      reason: PurgeReason.accountDeleted,
      userId: 'u2',
    );
    await store.recordEviction(target: 'cachedCatalogSources', userId: 'u3');

    final records = await store.readRecent();

    expect(records, hasLength(3));
    expect(records[0].target, 'cachedCatalogSources');
    expect(records[1].target, 'planningData');
    expect(records[2].target, 'songCatalog');
  });

  test('readRecent respects limit', () async {
    for (var i = 0; i < 5; i++) {
      await store.recordPurge(
        target: PurgeTarget.songCatalog,
        reason: PurgeReason.userSignOut,
        userId: 'u$i',
      );
    }

    final records = await store.readRecent(limit: 2);

    expect(records, hasLength(2));
  });

  test('recordRejectedEmptySnapshot inserts one row with kind '
      'empty-snapshot-rejected, target songCatalog, and reason carrying '
      'the organizationId (D4, local-data-durability-contract)', () async {
    await store.recordRejectedEmptySnapshot(
      userId: 'u1',
      organizationId: 'org-1',
    );

    final rows = await database.select(database.localDataEvents).get();

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.kind, 'empty-snapshot-rejected');
    expect(row.target, 'songCatalog');
    expect(row.reason, 'org-1');
    expect(row.userId, 'u1');
    expect(row.rowsAffected, isNull);
  });

  test(
    'recordEviction and recordRejectedEmptySnapshot are reachable through '
    'the LocalDataEventsRecorder interface, not just the concrete class',
    () async {
      final LocalDataEventsRecorder recorder = store;

      await recorder.recordEviction(target: 'cachedCatalogSources');
      await recorder.recordRejectedEmptySnapshot(
        userId: 'u1',
        organizationId: 'org-1',
      );

      final rows = await database.select(database.localDataEvents).get();
      expect(rows.map((r) => r.kind).toSet(), {
        'eviction',
        'empty-snapshot-rejected',
      });
    },
  );

  test('readRecent round-trips all fields correctly including nulls', () async {
    await store.recordPurge(
      target: PurgeTarget.identity,
      reason: PurgeReason.accountDeleted,
      userId: 'u1',
      rowsAffected: 3,
    );
    await store.recordEviction(target: 'cachedCatalogSources');

    final records = await store.readRecent();

    final purgeRecord = records.firstWhere((r) => r.kind == 'purge');
    expect(purgeRecord.id, isPositive);
    expect(purgeRecord.occurredAt, isA<DateTime>());
    expect(purgeRecord.target, 'identity');
    expect(purgeRecord.reason, 'accountDeleted');
    expect(purgeRecord.userId, 'u1');
    expect(purgeRecord.rowsAffected, 3);

    final evictionRecord = records.firstWhere((r) => r.kind == 'eviction');
    expect(evictionRecord.target, 'cachedCatalogSources');
    expect(evictionRecord.reason, isNull);
    expect(evictionRecord.userId, isNull);
    expect(evictionRecord.rowsAffected, isNull);
  });

  // YELLOW 3 (final whole-branch review, D5.4): a purge that was authorized
  // but did not run must still be audited -- this is the diagnostic that
  // explains why.
  test(
    'recordMembershipRevocationPurgeDeclined inserts a row naming the '
    'decline reason',
    () async {
      await store.recordMembershipRevocationPurgeDeclined(
        userId: 'u1',
        reason: MembershipRevocationPurgeDeclineReason.pendingWorkIncreased,
      );

      final rows = await database.select(database.localDataEvents).get();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.kind, 'membership-revocation-purge-declined');
      expect(row.target, 'identity');
      expect(row.reason, 'pendingWorkIncreased');
      expect(row.userId, 'u1');
      expect(row.rowsAffected, isNull);
    },
  );
}
