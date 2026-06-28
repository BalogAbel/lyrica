import 'package:drift/drift.dart';

import 'last_known_identity_database_connection_stub.dart'
    if (dart.library.html) 'last_known_identity_database_connection_web.dart'
    if (dart.library.io) 'last_known_identity_database_connection_io.dart'
    as connection;

QueryExecutor openLastKnownIdentityConnection() {
  return connection.openLastKnownIdentityConnection();
}

QueryExecutor openInMemoryLastKnownIdentityConnection() {
  return connection.openInMemoryLastKnownIdentityConnection();
}
