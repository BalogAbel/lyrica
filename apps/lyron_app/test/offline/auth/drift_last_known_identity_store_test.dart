import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';

import '../../support/drift_relaunch.dart';
import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test(
    'a written membershipRevokedAt marker survives a process restart -- a '
    'real Drift row write, not in-memory (D5, Task 4.1)',
    () async {
      final file = await createRelaunchDbFile('identity-quarantine-restart');
      LastKnownIdentityDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      var db = LastKnownIdentityDatabase.connect(openRelaunchExecutor(file));
      openDb = db;
      var store = DriftLastKnownIdentityStore(db);

      final revokedAt = DateTime.utc(2026, 8, 22, 10, 30);
      await store.write(
        LastKnownIdentity(
          userId: 'user-1',
          email: 'user1@example.com',
          organizationId: 'org-1',
          membershipRevokedAt: revokedAt,
        ),
      );

      // Simulate a process restart: close the database and reopen a fresh
      // store/database pair over the same underlying file.
      await db.close();
      openDb = null;

      db = LastKnownIdentityDatabase.connect(openRelaunchExecutor(file));
      openDb = db;
      store = DriftLastKnownIdentityStore(db);

      final reread = await store.read();
      expect(reread, isNotNull);
      expect(reread!.userId, 'user-1');
      expect(reread.membershipRevokedAt, isNotNull);
      expect(
        reread.membershipRevokedAt!.isAtSameMomentAs(revokedAt),
        isTrue,
      );

      await db.close();
      openDb = null;
    },
  );
}
