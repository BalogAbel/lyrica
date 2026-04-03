import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';

abstract interface class PlanningRemoteRefreshRepository {
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  });
}
