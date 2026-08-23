import 'package:drift/drift.dart';

import 'last_known_identity_database_connection.dart';
import 'last_known_identity_tables.dart';

part 'last_known_identity_database.g.dart';

@DriftDatabase(tables: [LastKnownIdentityRows])
class LastKnownIdentityDatabase extends _$LastKnownIdentityDatabase {
  LastKnownIdentityDatabase._(super.connection);

  factory LastKnownIdentityDatabase.connect(QueryExecutor executor) {
    return LastKnownIdentityDatabase._(executor);
  }

  factory LastKnownIdentityDatabase.local() {
    return LastKnownIdentityDatabase._(openLastKnownIdentityConnection());
  }

  factory LastKnownIdentityDatabase.inMemory() {
    return LastKnownIdentityDatabase._(
      openInMemoryLastKnownIdentityConnection(),
    );
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    // schemaVersion 1 was the initial shipped schema; no historical column
    // delta exists before this. This is this database's first onUpgrade
    // delta -- never rely on createAll() to bring an existing installation
    // forward.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // D5 (docs/specs/2026-08-19-local-data-durability-contract.md,
        // ADR-035 Phase 4): every pre-migration row predates the
        // membership-revocation marker, so it has no empty resolution in
        // flight to distinguish from -- nullable, defaulting to null on
        // upgrade, is the correct starting state (the same as a freshly
        // inserted row).
        await m.addColumn(
          lastKnownIdentityRows,
          lastKnownIdentityRows.membershipRevokedAt,
        );
      }
    },
  );

  @override
  int get schemaVersion => 2;
}
