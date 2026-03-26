import 'package:drift/drift.dart';

QueryExecutor openSongCatalogConnection() {
  throw UnsupportedError(
    'Song catalog persistence is unavailable on this platform.',
  );
}

QueryExecutor openInMemorySongCatalogConnection() {
  throw UnsupportedError(
    'In-memory song catalog persistence is unavailable on this platform.',
  );
}
