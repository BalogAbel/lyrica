import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late LastKnownIdentityDatabase database;
  late DriftLastKnownIdentityStore store;

  setUp(() {
    database = LastKnownIdentityDatabase.inMemory();
    store = DriftLastKnownIdentityStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('empty read returns null', () async {
    expect(await store.read(), isNull);
  });

  test('write then read returns the identity', () async {
    await store.write(
      const LastKnownIdentity(
        userId: 'u1',
        email: 'e@x',
        organizationId: 'org1',
      ),
    );

    final got = await store.read();

    expect(got?.userId, 'u1');
    expect(got?.email, 'e@x');
    expect(got?.organizationId, 'org1');
  });

  test('clear removes the identity', () async {
    await store.write(
      const LastKnownIdentity(userId: 'u1', email: 'e@x', organizationId: null),
    );

    await store.clear();

    expect(await store.read(), isNull);
  });
}
