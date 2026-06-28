import 'package:drift/drift.dart';

import 'last_known_identity_database_connection.dart';
import 'last_known_identity_tables.dart';

part 'last_known_identity_database.g.dart';

@DriftDatabase(
  tables: [
    LastKnownIdentityRows,
  ],
)
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
  );

  @override
  int get schemaVersion => 1;
}
