import 'package:drift/drift.dart';

QueryExecutor openPlanningLocalConnection() {
  throw UnsupportedError(
    'Planning persistence is unavailable on this platform.',
  );
}

QueryExecutor openInMemoryPlanningLocalConnection() {
  throw UnsupportedError(
    'In-memory planning persistence is unavailable on this platform.',
  );
}
