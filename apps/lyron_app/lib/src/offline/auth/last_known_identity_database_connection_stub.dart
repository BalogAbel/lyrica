import 'package:drift/drift.dart';

QueryExecutor openLastKnownIdentityConnection() {
  throw UnsupportedError(
    'Last known identity persistence is unavailable on this platform.',
  );
}

QueryExecutor openInMemoryLastKnownIdentityConnection() {
  throw UnsupportedError(
    'In-memory last known identity persistence is unavailable on this platform.',
  );
}
