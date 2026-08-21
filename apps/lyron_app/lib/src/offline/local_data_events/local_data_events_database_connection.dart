import 'package:drift/drift.dart';

import 'local_data_events_database_connection_stub.dart'
    if (dart.library.html) 'local_data_events_database_connection_web.dart'
    if (dart.library.io) 'local_data_events_database_connection_io.dart'
    as connection;

QueryExecutor openLocalDataEventsConnection() {
  return connection.openLocalDataEventsConnection();
}

QueryExecutor openInMemoryLocalDataEventsConnection() {
  return connection.openInMemoryLocalDataEventsConnection();
}
