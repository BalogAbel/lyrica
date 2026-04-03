import 'package:drift/drift.dart';

import 'planning_local_database_connection.dart';
import 'planning_local_tables.dart';

part 'planning_local_database.g.dart';

@DriftDatabase(
  tables: [
    PlanningProjectionOwners,
    CachedPlanningPlans,
    CachedPlanningSessions,
    CachedPlanningSessionItems,
  ],
)
class PlanningLocalDatabase extends _$PlanningLocalDatabase {
  PlanningLocalDatabase._(super.connection);

  factory PlanningLocalDatabase.connect(QueryExecutor executor) {
    return PlanningLocalDatabase._(executor);
  }

  factory PlanningLocalDatabase.local() {
    return PlanningLocalDatabase._(openPlanningLocalConnection());
  }

  factory PlanningLocalDatabase.inMemory() {
    return PlanningLocalDatabase._(openInMemoryPlanningLocalConnection());
  }

  @override
  int get schemaVersion => 1;
}
