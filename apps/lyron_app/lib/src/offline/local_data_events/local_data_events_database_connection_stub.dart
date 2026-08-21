import 'package:drift/drift.dart';

QueryExecutor openLocalDataEventsConnection() {
  throw UnsupportedError(
    'Local data events persistence is unavailable on this platform.',
  );
}

QueryExecutor openInMemoryLocalDataEventsConnection() {
  throw UnsupportedError(
    'In-memory local data events persistence is unavailable on this platform.',
  );
}
