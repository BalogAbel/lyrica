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
    'membershipRevokedAt on upgrade and keeps its row intact (D5, '
    'ADR-035 Phase 4)',
    () async {
      final file = await createRelaunchDbFile('identity-migration-v1-v2');
      LastKnownIdentityDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      // Build a genuine pre-migration v1 database by hand via raw sqlite3
      // (not through LastKnownIdentityDatabase, which would create the
      // CURRENT -- post-migration -- schema directly via onCreate and never
      // exercise onUpgrade at all). This is the exact CREATE TABLE text
      // Drift generated for schemaVersion 1, before membershipRevokedAt
      // existed.
      final rawDb = sqlite3.sqlite3.open(file.path);
      rawDb.execute('''
        CREATE TABLE "last_known_identity_rows" (
          "row_id" INTEGER NOT NULL,
          "user_id" TEXT NOT NULL,
          "email" TEXT NOT NULL,
          "organization_id" TEXT,
          "updated_at" INTEGER,
          PRIMARY KEY ("row_id")
        );
      ''');
      rawDb.execute('''
        INSERT INTO last_known_identity_rows
          (row_id, user_id, email, organization_id, updated_at)
        VALUES (1, 'user-1', 'user-1@example.com', 'org-1', 1700000000);
      ''');
      // Drift tracks the schema version via PRAGMA user_version -- this is
      // what tells it to run onUpgrade(from: 1, to: 2) instead of onCreate.
      rawDb.execute('PRAGMA user_version = 1;');
      rawDb.close();

      final db = LastKnownIdentityDatabase.connect(openRelaunchExecutor(file));
      openDb = db;

      final rows = await db.select(db.lastKnownIdentityRows).get();

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.rowId, 1);
      expect(row.userId, 'user-1');
      expect(row.email, 'user-1@example.com');
      expect(row.organizationId, 'org-1');
      expect(row.membershipRevokedAt, isNull);

      // The new column is usable, not merely present.
      await (db.update(db.lastKnownIdentityRows)
            ..where((t) => t.rowId.equals(1)))
          .write(
            LastKnownIdentityRowsCompanion(
              membershipRevokedAt: Value(DateTime.utc(2026, 8, 23)),
            ),
          );
      final updated = await (db.select(
        db.lastKnownIdentityRows,
      )..where((t) => t.rowId.equals(1))).getSingle();
      expect(
        updated.membershipRevokedAt?.toUtc(),
        DateTime.utc(2026, 8, 23),
      );

      await db.close();
      openDb = null;
    },
  );
}
