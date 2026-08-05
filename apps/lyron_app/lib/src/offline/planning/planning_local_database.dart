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
    CachedPlanningMutations,
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
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 4) {
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.sessionId,
        );
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.songId,
        );
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.songTitle,
        );
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.orderedSiblingIds,
        );
      }
      if (from < 5) {
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.originSnapshotJson,
        );
      }
      if (from < 6) {
        // D1 (docs/specs/2026-08-05-sync-snapshot-identity.md): every
        // pre-migration row predates the concept of a local revision, so it
        // has no sync attempt in flight to distinguish from -- 1 is a sane
        // starting value, matching what a freshly-inserted row gets.
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.localRevision,
        );
      }
    },
  );

  @override
  int get schemaVersion => 6;
}
