import 'package:drift/drift.dart';

import 'song_catalog_database_connection_stub.dart'
    if (dart.library.html) 'song_catalog_database_connection_web.dart'
    if (dart.library.io) 'song_catalog_database_connection_io.dart'
    as connection;

QueryExecutor openSongCatalogConnection() {
  return connection.openSongCatalogConnection();
}

QueryExecutor openInMemorySongCatalogConnection() {
  return connection.openInMemorySongCatalogConnection();
}
