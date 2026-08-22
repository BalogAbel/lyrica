import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../support/drift_relaunch.dart';
import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  test(
    'an existing pre-migration (v1) identity database gains '
    'membershipRevokedAt on upgrade and keeps its populated row intact '
    '(D5, local-data-durability-contract Task 4.1)',
    () async {
      final file = await createRelaunchDbFile('identity-migration-v1-v2');
      LastKnownIdentityDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      // Build a genuine pre-migration v1 database by hand, via raw sqlite3
      // (not through LastKnownIdentityDatabase, which would create the
      // CURRENT -- post-migration -- schema directly via onCreate and never
      // touch onUpgrade at all). This is the exact v1 shape, before
      // membership_revoked_at existed.
      final rawDb = sqlite3.sqlite3.open(file.path);
      rawDb.execute('''
        CREATE TABLE "last_known_identity_rows" (
          "row_id" INTEGER NOT NULL,
          "user_id" TEXT NOT NULL,
          "email" TEXT NOT NULL,
          "organization_id" TEXT NULL,
          "updated_at" INTEGER NULL,
          PRIMARY KEY ("row_id")
        );
      ''');
      rawDb.execute('''
        INSERT INTO last_known_identity_rows (
          row_id, user_id, email, organization_id, updated_at
        ) VALUES (
          1, 'user-1', 'user1@example.com', 'org-1', 1774000000000
        );
      ''');
      // Drift tracks the schema version via PRAGMA user_version -- this is
      // what makes onUpgrade(m, from: 1, to: 2) fire below, instead of
      // onCreate (which would build the CURRENT schema directly and never
      // touch the migration code at all).
      rawDb.execute('PRAGMA user_version = 1;');
      rawDb.close();

      final db = LastKnownIdentityDatabase.connect(openRelaunchExecutor(file));
      openDb = db;

      final rows = await db.select(db.lastKnownIdentityRows).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.userId, 'user-1');
      expect(row.email, 'user1@example.com');
      expect(row.organizationId, 'org-1');
      expect(
        row.membershipRevokedAt,
        isNull,
        reason:
            'a pre-migration row predates the concept of membership '
            'revocation, so the new column must read back null rather '
            'than throw or default to a sentinel value',
      );

      // The migrated column is real and usable, not just present: a
      // subsequent write must be able to set it, exactly as it would for a
      // row that was always on the current schema.
      await (db.update(db.lastKnownIdentityRows)
            ..where((table) => table.rowId.equals(1)))
          .write(
            LastKnownIdentityRowsCompanion(
              membershipRevokedAt: Value(DateTime.utc(2026, 8, 22)),
            ),
          );
      final afterUpdate = await (db.select(
        db.lastKnownIdentityRows,
      )..where((table) => table.rowId.equals(1))).getSingle();
      expect(
        afterUpdate.membershipRevokedAt!.isAtSameMomentAs(
          DateTime.utc(2026, 8, 22),
        ),
        isTrue,
      );
      // The rest of the row survived the migration unchanged.
      expect(afterUpdate.userId, 'user-1');
      expect(afterUpdate.email, 'user1@example.com');
      expect(afterUpdate.organizationId, 'org-1');

      await db.close();
      openDb = null;
    },
  );
}
