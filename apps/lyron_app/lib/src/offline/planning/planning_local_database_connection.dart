import 'package:drift/drift.dart';

import 'planning_local_database_connection_stub.dart'
    if (dart.library.html) 'planning_local_database_connection_web.dart'
    if (dart.library.io) 'planning_local_database_connection_io.dart'
    as connection;

QueryExecutor openPlanningLocalConnection() {
  return connection.openPlanningLocalConnection();
}

QueryExecutor openInMemoryPlanningLocalConnection() {
  return connection.openInMemoryPlanningLocalConnection();
}
