import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

QueryExecutor openSongCatalogConnection() {
  return DatabaseConnection.delayed(_openPersistentConnection());
}

QueryExecutor openInMemorySongCatalogConnection() {
  return DatabaseConnection.delayed(_openInMemoryConnection());
}

Future<DatabaseConnection> _openPersistentConnection() async {
  final sqlite3 = await _loadSqlite3();
  final fileSystem = await IndexedDbFileSystem.open(
    dbName: 'lyron_song_catalog',
  );
  sqlite3.registerVirtualFileSystem(fileSystem, makeDefault: true);

  return DatabaseConnection(
    WasmDatabase(
      sqlite3: sqlite3,
      path: '/lyron_song_catalog.sqlite',
      fileSystem: fileSystem,
    ),
  );
}

Future<DatabaseConnection> _openInMemoryConnection() async {
  final sqlite3 = await _loadSqlite3();
  return DatabaseConnection(WasmDatabase.inMemory(sqlite3));
}

Future<WasmSqlite3>? _sqlite3Loader;

Future<WasmSqlite3> _loadSqlite3() {
  return _sqlite3Loader ??= WasmSqlite3.loadFromUrl(
    Uri.base.resolve('sqlite3.wasm'),
  );
}
