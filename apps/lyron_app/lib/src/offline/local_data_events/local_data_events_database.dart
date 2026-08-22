import 'package:drift/drift.dart';

import 'local_data_events_database_connection.dart';
import 'local_data_events_tables.dart';

part 'local_data_events_database.g.dart';

@DriftDatabase(tables: [LocalDataEvents])
class LocalDataEventsDatabase extends _$LocalDataEventsDatabase {
  LocalDataEventsDatabase._(super.connection);

  factory LocalDataEventsDatabase.connect(QueryExecutor executor) {
    return LocalDataEventsDatabase._(executor);
  }

  factory LocalDataEventsDatabase.local() {
    return LocalDataEventsDatabase._(openLocalDataEventsConnection());
  }

  factory LocalDataEventsDatabase.inMemory() {
    return LocalDataEventsDatabase._(openInMemoryLocalDataEventsConnection());
  }

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) async => m.createAll());

  @override
  int get schemaVersion => 1;
}
